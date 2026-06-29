import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// C1 (ExecutionContext) + the C2 UnitOfWork atomic-with-submit seam.
void main() {
  setUpAll(sqfliteFfiInit);

  // Submittable DocType gated to the 'Accountant' role, so an explicit context
  // with no roles is denied (fail-closed) while a system context bypasses.
  const note = DocType(
    id: 'Note',
    name: 'Note',
    isSubmittable: true,
    permissions: [
      PermissionRule(
          role: 'Accountant',
          read: true,
          write: true,
          create: true,
          delete: true,
          submit: true),
    ],
    fields: [FieldDefinition(key: 'title', type: FieldType.data, label: 'Title')],
  );

  late MercantisDatabase database;
  late DocumentEngine engine;
  late PostingBatchStore postings;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final registry = MetadataRegistry(database.db);
    await registry.register(note);
    engine = DocumentEngine(
      database: database.db,
      registry: registry,
      metaComposer: MetaComposer(registry, database.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(database.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: SyncEngine(database: database.db, registry: registry),
      emitter: EventEmitter(),
      deviceId: 'engine-device',
      userId: 'engine-user',
    );
    postings = PostingBatchStore(database);
  });

  tearDown(() => database.close());

  Future<Document> draftWithId(String id,
      {Set<String> roles = const {'Accountant'}}) async {
    final saved =
        await engine.save(Document(id: '', docType: 'Note', payload: {'title': id}), roles);
    // Re-set id for deterministic test references via a follow-up fetch.
    return saved;
  }

  group('ExecutionContext threading', () {
    test('explicit context attributes audit + mutation to the operator', () async {
      final ctx = ExecutionContext(
          operatorId: 'alice', deviceId: 'alice-device', roles: {'Accountant'});
      final doc = await engine.save(
          Document(id: '', docType: 'Note', payload: {'title': 'a'}), const {},
          context: ctx);

      final audit = await database.db.query('audit_log',
          where: 'document_id = ?', whereArgs: [doc.id], limit: 1);
      expect(audit.single['user_id'], 'alice');
      expect(audit.single['device_id'], 'alice-device');
    });

    test('legacy fallback (no context) keeps the engine identity', () async {
      final doc = await engine.save(
          Document(id: '', docType: 'Note', payload: {'title': 'b'}),
          const {'Accountant'});
      final audit = await database.db.query('audit_log',
          where: 'document_id = ?', whereArgs: [doc.id], limit: 1);
      expect(audit.single['user_id'], 'engine-user');
      expect(audit.single['device_id'], 'engine-device');
    });

    test('explicit context with no roles is denied (fail-closed)', () async {
      final ctx = ExecutionContext(operatorId: 'bob', deviceId: 'd', roles: {});
      await expectLater(
        engine.save(
            Document(id: '', docType: 'Note', payload: {'title': 'c'}), const {},
            context: ctx),
        throwsA(isA<DocumentEngineError>()),
      );
    });

    test('system context bypasses permission gating', () async {
      final ctx = ExecutionContext.system(deviceId: 'sys');
      final doc = await engine.save(
          Document(id: '', docType: 'Note', payload: {'title': 'd'}), const {},
          context: ctx);
      expect(doc.id, isNotEmpty);
      final audit = await database.db.query('audit_log',
          where: 'document_id = ?', whereArgs: [doc.id], limit: 1);
      expect(audit.single['user_id'], 'system');
    });
  });

  group('submit + UnitOfWork atomic posting', () {
    test('records a posting batch atomically with submit', () async {
      final doc = await draftWithId('a1');
      final batchId = PostingBatch.makeId(doc.id);

      await engine.submit(doc, const {'Accountant'}, inTransaction: (uow) async {
        expect(await uow.postingBatchExists(batchId), isFalse);
        await uow.recordPostingBatch(PostingBatch(
          id: batchId,
          sourceType: 'Note',
          sourceId: doc.id,
          status: PostingStatus.posted,
          postedAt: DateTime.now(),
        ));
      });

      expect(doc.docStatus, 1);
      final batch = await postings.batch(batchId);
      expect(batch, isNotNull);
      expect(batch!.status, PostingStatus.posted);
      // postedBy is stamped from the operator context.
      expect(batch.postedBy, 'engine-user');
      final refetched = await engine.fetch('Note', doc.id);
      expect(refetched!.docStatus, 1);
    });

    test('a failing posting callback rolls back the whole submit', () async {
      final doc = await draftWithId('a2');
      final batchId = PostingBatch.makeId(doc.id);

      await expectLater(
        engine.submit(doc, const {'Accountant'}, inTransaction: (uow) async {
          await uow.recordPostingBatch(PostingBatch(
              id: batchId,
              sourceType: 'Note',
              sourceId: doc.id,
              status: PostingStatus.posted));
          throw StateError('posting failed');
        }),
        throwsA(isA<StateError>()),
      );

      // No batch survived, and the document is still Draft on disk.
      expect(await postings.batch(batchId), isNull);
      final refetched = await engine.fetch('Note', doc.id);
      expect(refetched!.docStatus, 0);
    });
  });
}
