import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// C3 — recursive child-row validation, child-row version diffs, and
/// post-submit immutability of child rows.
void main() {
  setUpAll(sqfliteFfiInit);

  const itemType = DocType(id: 'Item', name: 'Item', fields: [
    FieldDefinition(key: 'item_name', type: FieldType.data, label: 'Name'),
  ]);
  const salesLine = DocType(
    id: 'Sales Line',
    name: 'Sales Line',
    isChild: true,
    fields: [
      FieldDefinition(
          key: 'item',
          type: FieldType.link,
          label: 'Item',
          linkDocType: 'Item',
          required: true),
      FieldDefinition(key: 'qty', type: FieldType.float, label: 'Qty', required: true),
    ],
    indexes: [IndexDefinition(fieldKey: 'item', isUnique: true)],
  );
  const salesOrder = DocType(
    id: 'Sales Order',
    name: 'Sales Order',
    isSubmittable: true,
    fields: [
      FieldDefinition(key: 'customer', type: FieldType.data, label: 'Customer'),
      FieldDefinition(
          key: 'lines', type: FieldType.table, label: 'Lines', tableDocType: 'Sales Line'),
    ],
  );

  const roles = {'System Manager'};
  late MercantisDatabase database;
  late MetadataRegistry registry;

  setUp(() async {
    database = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    registry = MetadataRegistry(database.db);
    await registry.register(itemType);
    await registry.register(salesLine);
    await registry.register(salesOrder);
    for (final id in ['ITEM-1', 'ITEM-2']) {
      await database.db.insert('documents', {
        'id': id,
        'doctype': 'Item',
        'company': null,
        'docstatus': 0,
        'payload': '{}',
        'created_at': 0,
        'modified_at': 0,
        'sync_version': null,
        'sync_state': 'local',
        'amended_from': null,
      });
    }
  });

  tearDown(() => database.close());

  Document orderWith(List<Map<String, dynamic>> lines) {
    final doc =
        Document(id: '', docType: 'Sales Order', payload: {'customer': 'ACME'});
    doc.children['lines'] = [
      for (var i = 0; i < lines.length; i++)
        ChildRow(
          id: '',
          parentId: '',
          parentDocType: 'Sales Order',
          tableName: 'lines',
          rowIndex: i,
          payload: lines[i],
        ),
    ];
    return doc;
  }

  group('pipeline', () {
    Future<List<ValidationError>> validate(Document doc) async {
      final r = await ValidationPipeline().run(
        doc,
        salesOrder,
        database.db,
        DocumentOperation.create,
        roles,
        childDocTypeProvider: registry.get,
      );
      return r.errors;
    }

    test('valid child rows pass', () async {
      expect(await validate(orderWith([
        {'item': 'ITEM-1', 'qty': 2}
      ])), isEmpty);
    });

    test('missing required child field → Row-pathed error', () async {
      final errs = await validate(orderWith([
        {'item': 'ITEM-1'}
      ]));
      expect(
          errs.any((e) =>
              e.fieldKey == 'lines[0].qty' && e.message.startsWith('Row 1:')),
          isTrue);
    });

    test('dangling child link → error', () async {
      final errs = await validate(orderWith([
        {'item': 'NOPE', 'qty': 1}
      ]));
      expect(errs.any((e) => e.fieldKey == 'lines[0].item'), isTrue);
    });

    test('duplicate unique child rows → error on the second row', () async {
      final errs = await validate(orderWith([
        {'item': 'ITEM-1', 'qty': 1},
        {'item': 'ITEM-1', 'qty': 2},
      ]));
      expect(
          errs.any((e) =>
              e.fieldKey == 'lines[1].item' &&
              e.message.contains('duplicates')),
          isTrue);
    });

    test('untyped table (no resolver) is skipped — behaviour unchanged', () async {
      final r = await ValidationPipeline().run(
        orderWith([
          {'item': 'NOPE'}
        ]),
        salesOrder,
        database.db,
        DocumentOperation.create,
        roles,
      );
      expect(r.errors, isEmpty);
    });
  });

  group('engine integration', () {
    late DocumentEngine engine;

    setUp(() {
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
        deviceId: 'd',
        userId: 'u',
      );
    });

    test('save rejects an invalid child row', () async {
      await expectLater(
        engine.save(orderWith([
          {'item': 'ITEM-1'}
        ]), roles),
        throwsA(isA<DocumentEngineError>()),
      );
    });

    test('child-row edits are captured in version history', () async {
      final saved = await engine.save(orderWith([
        {'item': 'ITEM-1', 'qty': 2}
      ]), roles);
      final fetched = await engine.fetch('Sales Order', saved.id);
      fetched!.children['lines']![0].payload['qty'] = 5;
      await engine.save(fetched, roles);

      final audit = await database.db
          .query('audit_log', where: 'document_id = ?', whereArgs: [saved.id]);
      expect(
          audit.any((r) => r['payload'].toString().contains('lines[0].qty')),
          isTrue);
    });

    test('child rows are frozen after submit', () async {
      final saved = await engine.save(orderWith([
        {'item': 'ITEM-1', 'qty': 2}
      ]), roles);
      await engine.submit(saved, roles);
      // Editing a child row then re-saving must fail — submit immutability
      // covers children (save rejects any write to a submitted document).
      saved.children['lines']![0].payload['qty'] = 9;
      await expectLater(
          engine.save(saved, roles), throwsA(isA<DocumentEngineError>()));
    });
  });
}
