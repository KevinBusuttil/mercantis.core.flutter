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
}
