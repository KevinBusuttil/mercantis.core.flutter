import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Phase 0.8 (gap analysis §8 "also noted"): the audit log recorded only
/// created/updated — the OFFICIAL lifecycle (submit, cancel, amend, delete)
/// left no audit trace. Every transition now writes a row with actor and
/// device, readable through AuditLogReader like any other entry.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late AuditLogReader reader;
  const roles = {'System Manager'};

  const voucher = DocType(
    id: 'Voucher',
    name: 'Voucher',
    isSubmittable: true,
    fields: [
      FieldDefinition(key: 'title', label: 'Title', type: FieldType.data),
    ],
  );

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    await registry.register(voucher);
    engine = DocumentEngine(
      database: db.db,
      registry: registry,
      metaComposer: MetaComposer(registry, db.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(db.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: SyncEngine(database: db.db, registry: registry),
      emitter: EventEmitter(),
      deviceId: 'devA',
      userId: 'auditor',
      interceptors: const [],
    );
    reader = AuditLogReader(db.db);
  });

  tearDown(() async => db.close());

  Future<List<String>> actionsFor(String id) async => [
        for (final e in await reader.entries(documentId: id)) e.action,
      ];

  test('submit, cancel and amend each leave an audit row with the actor',
      () async {
    final doc = await engine.save(
        Document(id: 'V-1', docType: 'Voucher', payload: {'title': 'x'}),
        roles);
    await engine.submit(doc, roles);
    await engine.cancel(doc, roles);
    final amended = await engine.amend(doc, roles);

    final entries = await reader.entries(documentId: 'V-1');
    // Newest first: amended, cancelled, submitted, created.
    expect([for (final e in entries) e.action],
        ['amended', 'cancelled', 'submitted', 'created']);
    final submitted = entries.firstWhere((e) => e.action == 'submitted');
    expect(submitted.userId, 'auditor');
    expect(submitted.deviceId, 'devA');
    // The amendment names its successor.
    expect(await actionsFor(amended.id), ['created']);
  });

  test('deleting a draft is audited even though the document is gone',
      () async {
    await engine.save(
        Document(id: 'V-2', docType: 'Voucher', payload: {'title': 'y'}),
        roles);
    await engine.delete('Voucher', 'V-2', roles);
    expect(await actionsFor('V-2'), ['deleted', 'created']);
  });
}
