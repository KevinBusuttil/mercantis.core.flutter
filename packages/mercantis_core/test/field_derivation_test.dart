import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// C8 — save-time declarative field derivation: empty-numeric → null coercion,
/// `fetchFrom` population from a linked document, and `formulaExpression`
/// recompute on the header and child rows.
void main() {
  setUpAll(sqfliteFfiInit);

  const item = DocType(
    id: 'Item',
    name: 'Item',
    fields: [
      FieldDefinition(key: 'item_name', label: 'Name', type: FieldType.data),
    ],
  );

  const orderLine = DocType(
    id: 'Order Line',
    name: 'Order Line',
    isChild: true,
    fields: [
      FieldDefinition(
          key: 'item', label: 'Item', type: FieldType.link,
          linkDocType: 'Item', options: 'Item'),
      FieldDefinition(
          key: 'item_name', label: 'Name', type: FieldType.data,
          fetchFrom: 'item.item_name'),
      FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.float),
      FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency),
      FieldDefinition(
          key: 'amount', label: 'Amount', type: FieldType.currency,
          readOnly: true, formulaExpression: 'qty * rate'),
    ],
  );

  const order = DocType(
    id: 'Order',
    name: 'Order',
    fields: [
      FieldDefinition(
          key: 'item', label: 'Item', type: FieldType.link,
          linkDocType: 'Item', options: 'Item'),
      FieldDefinition(
          key: 'item_name', label: 'Name', type: FieldType.data,
          fetchFrom: 'item.item_name'),
      FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.float),
      FieldDefinition(key: 'price', label: 'Price', type: FieldType.currency),
      FieldDefinition(
          key: 'total', label: 'Total', type: FieldType.currency,
          readOnly: true, formulaExpression: 'qty * price'),
      FieldDefinition(
          key: 'lines', label: 'Lines', type: FieldType.table,
          tableDocType: 'Order Line', options: 'Order Line'),
    ],
  );

  late MercantisDatabase db;
  late DocumentEngine engine;
  const roles = {'System Manager'};

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    for (final dt in [item, orderLine, order]) {
      await registry.register(dt);
    }
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
      deviceId: 'd',
      userId: 'u',
    );
    await engine.save(
        Document(id: 'ITM1', docType: 'Item', payload: {'item_name': 'Widget'}),
        roles);
  });

  tearDown(() => db.close());

  test('empty numeric fields coerce to null (not "")', () async {
    final saved = await engine.save(
        Document(id: 'O1', docType: 'Order', payload: {
          'qty': 2,
          'price': '   ', // blank numeric input
        }),
        roles);
    expect(saved.payload['price'], isNull);
    // Persisted as null too.
    final back = await engine.fetch('Order', 'O1');
    expect(back!.payload['price'], isNull);
  });

  test('fetchFrom populates a field from the linked document', () async {
    final saved = await engine.save(
        Document(id: 'O2', docType: 'Order', payload: {'item': 'ITM1'}),
        roles);
    expect(saved.payload['item_name'], 'Widget');
  });

  test('formulaExpression recomputes on the header', () async {
    final saved = await engine.save(
        Document(id: 'O3', docType: 'Order', payload: {
          'qty': 3,
          'price': 50,
          'total': 1, // stale value gets recomputed
        }),
        roles);
    expect(saved.payload['total'], 150);
  });

  test('derivation runs on child rows (fetchFrom + formula)', () async {
    final doc = Document(id: 'O4', docType: 'Order', payload: {'item': 'ITM1'});
    doc.children['lines'] = [
      ChildRow(
          id: '', parentId: '', parentDocType: 'Order', tableName: 'lines',
          rowIndex: 0,
          payload: {'item': 'ITM1', 'qty': 4, 'rate': 25}),
    ];
    await engine.save(doc, roles);

    final back = await engine.fetch('Order', 'O4');
    final line = back!.children['lines']!.single;
    expect(line.payload['item_name'], 'Widget'); // fetched from the Item
    expect(line.payload['amount'], 100); // 4 * 25
  });

  test('fetchFrom survives FieldDefinition JSON round-trip', () {
    final f = FieldDefinition.fromJson(const FieldDefinition(
            key: 'item_name', label: 'Name', type: FieldType.data,
            fetchFrom: 'item.item_name')
        .toJson());
    expect(f.fetchFrom, 'item.item_name');
  });

  test('fetchFrom survives resolution into ResolvedFieldDefinition', () {
    final resolved = ResolvedFieldDefinition.fromFieldDefinition(
        const FieldDefinition(
            key: 'item_name', label: 'Name', type: FieldType.data,
            fetchFrom: 'item.item_name'));
    expect(resolved.fetchFrom, 'item.item_name');
  });
}
