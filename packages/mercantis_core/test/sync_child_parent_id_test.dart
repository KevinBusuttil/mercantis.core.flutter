import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Regression for the child-sync parent-id bug: a child added to a brand-new
/// document still carries the pre-save empty parentId. The mutation must
/// serialize children under the *assigned* document id, otherwise a peer
/// inserts orphaned rows that `fetch(id)` can't load.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase dbA;
  late MercantisDatabase dbB;
  late DocumentEngine engine;
  const roles = {'System Manager'};

  DocumentEngine engineFor(MercantisDatabase db) {
    final registry = MetadataRegistry(db.db);
    return DocumentEngine(
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
      userId: 'u',
      interceptors: const [],
    );
  }

  setUp(() async {
    dbA = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    dbB = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(dbA.db);
    await registry.register(const DocType(
        id: 'Order Line', name: 'Order Line', isChild: true, fields: [
      FieldDefinition(key: 'item', label: 'Item', type: FieldType.data),
      FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.float),
    ]));
    await registry.register(const DocType(
        id: 'Order', name: 'Order', namingRule: 'ORD-.####', fields: [
      FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.data),
      FieldDefinition(
          key: 'lines', label: 'Lines', type: FieldType.table, tableDocType: 'Order Line'),
    ]));
    engine = engineFor(dbA);
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  test('a new document syncs its children under the assigned id', () async {
    final doc = Document(id: '', docType: 'Order', payload: {'customer': 'ACME'});
    // Children built the way GenericFormView does for a new record: parentId
    // copied from the (still empty) base id.
    doc.children['lines'] = [
      ChildRow(id: '', parentId: '', parentDocType: 'Order', tableName: 'lines', rowIndex: 0, payload: {'item': 'A', 'qty': 2}),
      ChildRow(id: '', parentId: '', parentDocType: 'Order', tableName: 'lines', rowIndex: 1, payload: {'item': 'B', 'qty': 3}),
    ];

    final saved = await engine.save(doc, roles);
    expect(saved.id, startsWith('ORD-')); // got a real id

    // The queued mutation must stamp the saved id onto its children.
    final rows = await dbA.db
        .query('sync_queue', where: 'status = ?', whereArgs: ['pending']);
    final mutation = MutationRecord.fromDbRow(rows.last);
    final lines = (mutation.payload['__children'] as Map)['lines'] as List;
    expect(lines, hasLength(2));
    for (final line in lines) {
      expect((line as Map)['parent_id'], saved.id);
    }

    // End-to-end: a peer applying the mutation loads the lines via fetch().
    final engineB = engineFor(dbB);
    await SyncEngine(database: dbB.db, registry: MetadataRegistry(dbB.db))
        .applyRemoteMutations([mutation]);
    final onPeer = await engineB.fetch('Order', saved.id);
    expect(onPeer, isNotNull);
    expect(onPeer!.children['lines'], hasLength(2));
  });
}
