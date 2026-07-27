import 'dart:convert';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Phase 0.10 (gap analysis §8-C6): a version-check conflict used to drop
/// the remote mutation on the floor — the document sat in
/// `sync_state=conflict` with nothing to resolve against. The engine now
/// keeps the losing candidate, and ConflictService offers whole-document
/// keep-mine / take-theirs.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late MetadataRegistry registry;
  late SyncEngine sync;
  late ConflictService service;

  const noteType = DocType(
    id: 'Note',
    name: 'Note',
    syncPolicy:
        SyncPolicy(conflictResolution: ConflictResolution.versionCheckedMerge),
    fields: [
      FieldDefinition(key: 'title', label: 'Title', type: FieldType.data),
    ],
  );

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    registry = MetadataRegistry(database.db);
    await registry.register(noteType);
    sync = SyncEngine(database: database.db, registry: registry);
    service = ConflictService(
      database: database.db,
      syncEngine: sync,
      deviceId: 'devA',
      userId: 'u',
    );
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
  });

  Map<String, dynamic> envelope(String title, String? syncVersion) => {
        'id': 'N-1',
        'doctype': 'Note',
        'company': null,
        'docstatus': 0,
        'payload': jsonEncode({'title': title}),
        'created_at': 1,
        'modified_at': 2,
        'sync_version': syncVersion,
        'sync_state': 'local',
        'amended_from': null,
      };

  MutationRecord remoteUpdate(String title, String syncVersion) =>
      MutationRecord(
        id: 'mut-$syncVersion',
        type: MutationType.updateDocument,
        docType: 'Note',
        documentId: 'N-1',
        payload: envelope(title, syncVersion),
        deviceId: 'devB',
        userId: 'maria',
        localTimestamp: DateTime.fromMillisecondsSinceEpoch(1751800000000),
        syncVersion: syncVersion,
      );

  /// A local document carrying unshipped edits ("mine",
  /// `sync_state=local`), then a remote candidate with different content
  /// ("theirs") — both sides changed it, so the policy demands a human.
  Future<void> seedConflict() async {
    await database.db.insert(
      'documents',
      envelope('mine', '5'), // sync_state 'local' — unshipped edits
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await sync.applyRemoteMutations([remoteUpdate('theirs', '9')]);
  }

  test('the losing remote candidate is kept, not dropped', () async {
    await seedConflict();

    final docs = await database.db
        .query('documents', where: 'id = ?', whereArgs: ['N-1']);
    expect(docs.single['sync_state'], 'conflict');
    expect(jsonDecode(docs.single['payload'] as String)['title'],
        'mine'); // local untouched

    expect(await service.count(), 1);
    final conflict = (await service.listConflicts()).single;
    expect(conflict.documentId, 'N-1');
    expect(conflict.docType, 'Note');
    expect(conflict.local, isNotNull);
    expect(conflict.local!.payload['title'], 'mine');
    expect(jsonDecode(conflict.remote.payload['payload'] as String)['title'],
        'theirs');
    expect(conflict.remote.deviceId, 'devB');
  });

  test('a newer candidate for the same document replaces the older one',
      () async {
    await seedConflict();
    await sync.applyRemoteMutations([remoteUpdate('theirs v2', '11')]);
    expect(await service.count(), 1); // still one row per document
    final conflict = (await service.listConflicts()).single;
    expect(jsonDecode(conflict.remote.payload['payload'] as String)['title'],
        'theirs v2');
  });

  test('keepMine clears the conflict and re-enqueues the local version',
      () async {
    await seedConflict();
    await service.keepMine('Note', 'N-1');

    expect(await service.count(), 0);
    final docs = await database.db
        .query('documents', where: 'id = ?', whereArgs: ['N-1']);
    expect(docs.single['sync_state'], 'local');
    expect(jsonDecode(docs.single['payload'] as String)['title'], 'mine');

    // A pending mutation now carries "mine" back out, with a fresh
    // timestamp so last-write-wins favours it downstream.
    final queue = await database.db.query('sync_queue',
        where: 'document_id = ? AND status = ?',
        whereArgs: ['N-1', MutationStatus.pending.name]);
    final mutation = MutationRecord.fromDbRow(queue.single);
    expect(mutation.type, MutationType.updateDocument);
    expect(jsonDecode(mutation.payload['payload'] as String)['title'],
        'mine');
    expect(
        mutation.localTimestamp
            .isAfter(DateTime.fromMillisecondsSinceEpoch(1751800000000)),
        isTrue);
  });

  test('takeTheirs applies the candidate and abandons un-pushed local edits',
      () async {
    await seedConflict();
    // An un-pushed local edit that would resurrect "mine" on next push.
    await sync.appendMutation(MutationRecord(
      id: 'mut-local-edit',
      type: MutationType.updateDocument,
      docType: 'Note',
      documentId: 'N-1',
      payload: envelope('mine', '5'),
      deviceId: 'devA',
      userId: 'u',
      localTimestamp: DateTime.fromMillisecondsSinceEpoch(1751800000001),
      status: MutationStatus.pending,
    ));

    await service.takeTheirs('Note', 'N-1');

    expect(await service.count(), 0);
    final docs = await database.db
        .query('documents', where: 'id = ?', whereArgs: ['N-1']);
    expect(jsonDecode(docs.single['payload'] as String)['title'], 'theirs');
    expect(docs.single['sync_state'], 'synced');
    expect(docs.single['sync_version'], '9');

    final pending = await database.db.query('sync_queue',
        where: 'document_id = ? AND status = ?',
        whereArgs: ['N-1', MutationStatus.pending.name]);
    expect(pending, isEmpty); // the local edit is gone with the choice
  });

  test('resolving an unknown document is a no-op, not a crash', () async {
    await service.keepMine('Note', 'missing');
    await service.takeTheirs('Note', 'missing');
    expect(await service.count(), 0);
  });

  test('a clean local copy fast-forwards — no conflict for a plain update',
      () async {
    await database.db.insert(
      'documents',
      {...envelope('old', '5'), 'sync_state': 'synced'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await sync.applyRemoteMutations([remoteUpdate('new', '9')]);

    final doc = (await database.db
            .query('documents', where: 'id = ?', whereArgs: ['N-1']))
        .single;
    expect(jsonDecode(doc['payload'] as String)['title'], 'new');
    expect(doc['sync_state'], 'synced');
    expect(await service.count(), 0);
  });

  test('identical content applies silently even when both sides "edited"',
      () async {
    // Deterministic seeds: both devices lay down the same record. The
    // local copy is unshipped (`local`), the remote candidate identical —
    // a conflict here would greet every joining device with ~70 of them.
    await database.db.insert(
      'documents',
      envelope('same', '5'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await sync.applyRemoteMutations([remoteUpdate('same', '9')]);

    final doc = (await database.db
            .query('documents', where: 'id = ?', whereArgs: ['N-1']))
        .single;
    expect(doc['sync_state'], 'synced');
    expect(doc['sync_version'], '9');
    expect(await service.count(), 0);
  });

  test('push holds a conflicted document but ships the rest', () async {
    await seedConflict();

    final shipped = <MutationRecord>[];
    final pushSync = SyncEngine(
      database: database.db,
      registry: registry,
      cloudAdapter: _RecordingAdapter(shipped),
    );
    addTearDown(pushSync.dispose);

    Future<void> enqueue(String docId, String title) =>
        pushSync.appendMutation(MutationRecord(
          id: 'mut-$docId',
          type: MutationType.updateDocument,
          docType: 'Note',
          documentId: docId,
          payload: {...envelope(title, null), 'id': docId},
          deviceId: 'devA',
          userId: 'u',
          localTimestamp: DateTime.now(),
          status: MutationStatus.pending,
        ));
    await enqueue('N-1', 'mine'); // conflicted — must be held
    await enqueue('N-2', 'other'); // unrelated — must ship

    await pushSync.pushPendingMutations();

    expect(shipped.map((m) => m.documentId), ['N-2']);
    // The held mutation stays pending for after the user resolves.
    final held = await database.db.query('sync_queue',
        where: 'document_id = ? AND status = ?',
        whereArgs: ['N-1', MutationStatus.pending.name]);
    expect(held, hasLength(1));
    expect(await service.count(), 1); // conflict untouched
  });

  test('a successful push flips the shipped documents to synced', () async {
    await database.db.insert(
      'documents',
      envelope('mine', null), // sync_state 'local'
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final pushSync = SyncEngine(
      database: database.db,
      registry: registry,
      cloudAdapter: _RecordingAdapter([]),
    );
    addTearDown(pushSync.dispose);
    await pushSync.appendMutation(MutationRecord(
      id: 'mut-ship',
      type: MutationType.updateDocument,
      docType: 'Note',
      documentId: 'N-1',
      payload: envelope('mine', null),
      deviceId: 'devA',
      userId: 'u',
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));

    await pushSync.pushPendingMutations();

    final doc = (await database.db
            .query('documents', where: 'id = ?', whereArgs: ['N-1']))
        .single;
    expect(doc['sync_state'], 'synced');
  });
}

class _RecordingAdapter extends NoOpCloudAdapter {
  const _RecordingAdapter(this.shipped);
  final List<MutationRecord> shipped;

  @override
  Future<void> push(List<MutationRecord> mutations) async =>
      shipped.addAll(mutations);
}
