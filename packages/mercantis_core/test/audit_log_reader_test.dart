import 'package:test/test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The audit-log read API: engine writes are queryable per document, newest
/// first, with parsed field diffs.
void main() {
  setUpAll(sqfliteFfiInit);

  test('reads engine-written history with diffs, newest first', () async {
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(db.close);
    const roles = {'System Manager'};
    final registry = MetadataRegistry(db.db);
    await registry.register(const DocType(id: 'Note', name: 'Note', module: 'm', fields: [
      FieldDefinition(key: 'title', label: 'Title', type: FieldType.data),
    ]));
    final engine = DocumentEngine(
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
      userId: 'tester',
    );

    final doc = await engine.save(
        Document(id: 'N-1', docType: 'Note', payload: {'title': 'first'}),
        roles);
    doc.payload['title'] = 'second';
    await engine.save(doc, roles);

    final reader = AuditLogReader(db.db);
    final entries =
        await reader.entries(docType: 'Note', documentId: 'N-1');
    expect(entries.length, 2);
    expect(entries.first.action, 'updated'); // newest first
    expect(entries.first.userId, 'tester');
    expect(entries.first.deviceId, 'devA');
    final diff =
        entries.first.diffs.firstWhere((d) => d.fieldKey == 'title');
    expect(diff.oldValue, 'first');
    expect(diff.newValue, 'second');
    expect(entries.last.action, 'created');
    expect(entries.last.diffs, isEmpty);

    // Filters actually filter.
    expect(await reader.entries(docType: 'Other'), isEmpty);
  });
}
