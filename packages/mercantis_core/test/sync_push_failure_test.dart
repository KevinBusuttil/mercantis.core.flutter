import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// A failed push must strand nothing (the HTTP transport made this real:
/// networks drop). Mutations marked `pushing` whose adapter call throws go
/// back to `pending` so the next cycle retries them — and the failure
/// propagates so the caller can surface it.
class _FlakyAdapter implements CloudAdapter {
  int attempts = 0;
  bool failNext = true;

  @override
  Future<void> push(List<MutationRecord> mutations) async {
    attempts++;
    if (failNext) throw Exception('network down');
  }

  @override
  Future<List<MutationRecord>> pull(String? afterSyncVersion) async => [];
  @override
  Future<void> acknowledge(List<String> mutationIds) async {}
  @override
  Future<void> pushBlob(String sha256, List<int> bytes) async {}
  @override
  Future<List<int>?> pullBlob(String sha256) async => null;
  @override
  Future<bool> hasBlob(String sha256) async => false;
}

/// Rejects — like the Team backend's sync plane — any batch containing a
/// mutation whose document is officially posted (409), accepting the rest.
class _RejectingAdapter implements CloudAdapter {
  _RejectingAdapter(this.poisonedIds);

  final Set<String> poisonedIds;
  final pushedIds = <String>[];

  @override
  Future<void> push(List<MutationRecord> mutations) async {
    for (final m in mutations) {
      if (poisonedIds.contains(m.id)) {
        throw CloudHttpException(
            409, '${m.docType} ${m.documentId} is officially posted');
      }
    }
    pushedIds.addAll([for (final m in mutations) m.id]);
  }

  @override
  Future<List<MutationRecord>> pull(String? afterSyncVersion) async => [];
  @override
  Future<void> acknowledge(List<String> mutationIds) async {}
  @override
  Future<void> pushBlob(String sha256, List<int> bytes) async {}
  @override
  Future<List<int>?> pullBlob(String sha256) async => null;
  @override
  Future<bool> hasBlob(String sha256) async => false;
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('a failed push returns the batch to pending and retries cleanly',
      () async {
    final database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final adapter = _FlakyAdapter();
    final sync = SyncEngine(
      database: database.db,
      registry: MetadataRegistry(database.db),
      cloudAdapter: adapter,
    );
    addTearDown(sync.dispose);

    await sync.appendMutation(MutationRecord(
      id: 'mut-1',
      type: MutationType.createDocument,
      docType: 'Item',
      documentId: 'ITEM-1',
      payload: {'id': 'ITEM-1'},
      deviceId: 'devA',
      userId: 'u',
      localTimestamp: DateTime.now(),
    ));

    // First cycle: the adapter throws; the failure propagates and the
    // mutation is back to pending — NOT stranded in `pushing`.
    await expectLater(sync.pushPendingMutations(), throwsException);
    var rows = await database.db
        .query('sync_queue', where: 'id = ?', whereArgs: ['mut-1']);
    expect(rows.single['status'], MutationStatus.pending.name);
    expect(await sync.pendingCount(), 1);

    // Second cycle: network back — the same mutation ships and is marked
    // pushed.
    adapter.failNext = false;
    await sync.pushPendingMutations();
    expect(adapter.attempts, 2);
    rows = await database.db
        .query('sync_queue', where: 'id = ?', whereArgs: ['mut-1']);
    expect(rows.single['status'], MutationStatus.pushed.name);
    expect(await sync.pendingCount(), 0);
  });

  test(
      'a permanent rejection quarantines the poisoned mutation as failed; '
      'innocents in the batch still ship', () async {
    final database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    final adapter = _RejectingAdapter({'mut-bad'});
    final sync = SyncEngine(
      database: database.db,
      registry: MetadataRegistry(database.db),
      cloudAdapter: adapter,
    );
    addTearDown(sync.dispose);

    MutationRecord record(String id) => MutationRecord(
          id: id,
          type: MutationType.updateDocument,
          docType: 'Sales Invoice',
          documentId: 'SINV-$id',
          payload: {'id': 'SINV-$id'},
          deviceId: 'devA',
          userId: 'u',
          localTimestamp: DateTime.now(),
        );
    await sync.appendMutation(record('mut-good-1'));
    await sync.appendMutation(record('mut-bad'));
    await sync.appendMutation(record('mut-good-2'));

    // The batch 409s; the engine isolates the poison per-mutation.
    await expectLater(
        sync.pushPendingMutations(), throwsA(isA<CloudHttpException>()));

    Future<String> status(String id) async => (await database.db
        .query('sync_queue', where: 'id = ?', whereArgs: [id]))
        .single['status'] as String;
    expect(await status('mut-good-1'), MutationStatus.pushed.name);
    expect(await status('mut-good-2'), MutationStatus.pushed.name);
    expect(await status('mut-bad'), MutationStatus.failed.name);
    expect(adapter.pushedIds, ['mut-good-1', 'mut-good-2']);

    // The queue is healthy again: nothing pending, the poison quarantined
    // and visible — the next cycle does NOT retry it.
    expect(await sync.pendingCount(), 0);
    expect(await sync.failedCount(), 1);
    await sync.pushPendingMutations();
    expect(await sync.failedCount(), 1); // untouched by normal cycles

    // Explicit user action requeues it (e.g. after amending the document).
    expect(await sync.requeueFailed(), 1);
    expect(await sync.pendingCount(), 1);
    expect(await sync.failedCount(), 0);
  });

  test('408 and 429 stay transient: the batch re-pends, nothing quarantines',
      () async {
    final database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    var status = 429;
    final sync = SyncEngine(
      database: database.db,
      registry: MetadataRegistry(database.db),
      cloudAdapter: _ThrowingAdapter(() => CloudHttpException(status, 'x')),
    );
    addTearDown(sync.dispose);

    await sync.appendMutation(MutationRecord(
      id: 'mut-1',
      type: MutationType.createDocument,
      docType: 'Item',
      documentId: 'ITEM-1',
      payload: {'id': 'ITEM-1'},
      deviceId: 'devA',
      userId: 'u',
      localTimestamp: DateTime.now(),
    ));

    for (final transient in [429, 408, 500, 503]) {
      status = transient;
      await expectLater(
          sync.pushPendingMutations(), throwsA(isA<CloudHttpException>()));
      expect(await sync.pendingCount(), 1, reason: 'HTTP $transient');
      expect(await sync.failedCount(), 0, reason: 'HTTP $transient');
    }
  });
}

class _ThrowingAdapter implements CloudAdapter {
  _ThrowingAdapter(this.error);

  final Object Function() error;

  @override
  Future<void> push(List<MutationRecord> mutations) async => throw error();
  @override
  Future<List<MutationRecord>> pull(String? afterSyncVersion) async => [];
  @override
  Future<void> acknowledge(List<String> mutationIds) async {}
  @override
  Future<void> pushBlob(String sha256, List<int> bytes) async {}
  @override
  Future<List<int>?> pullBlob(String sha256) async => null;
  @override
  Future<bool> hasBlob(String sha256) async => false;
}
