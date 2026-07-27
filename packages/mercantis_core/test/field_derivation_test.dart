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

  const gadget = DocType(
    id: 'Gadget',
    name: 'Gadget',
    fields: [
      FieldDefinition(key: 'name', label: 'Name', type: FieldType.data),
      FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check),
      FieldDefinition(key: 'count', label: 'Count', type: FieldType.integer),
      FieldDefinition(key: 'weight', label: 'Weight', type: FieldType.float),
      FieldDefinition(
          key: 'runtime', label: 'Runtime', type: FieldType.duration),
      FieldDefinition(key: 'stars', label: 'Stars', type: FieldType.rating),
    ],
  );

  late MercantisDatabase db;
  late DocumentEngine engine;
  const roles = {'System Manager'};

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    for (final dt in [item, orderLine, order, gadget]) {
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

  group('scalar type normalization', () {
    test('stringly check and numeric values persist typed', () async {
      await engine.save(
          Document(id: 'G1', docType: 'Gadget', payload: {
            'name': 'A',
            'enabled': '1', // seeders/interceptors write flag strings
            'count': '42',
            'weight': '18.5',
            'runtime': '3600',
            'stars': '4',
          }),
          roles);
      final back = (await engine.fetch('Gadget', 'G1'))!;
      expect(back.payload['enabled'], 1);
      expect(back.payload['count'], 42);
      expect(back.payload['weight'], 18.5);
      expect(back.payload['runtime'], 3600);
      expect(back.payload['stars'], 4);
    });

    test('check accepts every legacy form and stores 0/1', () async {
      Future<dynamic> roundTrip(dynamic raw) async {
        final saved = await engine.save(
            Document(id: '', docType: 'Gadget', payload: {
              'name': 'B',
              'enabled': raw,
            }),
            roles);
        return (await engine.fetch('Gadget', saved.id))!.payload['enabled'];
      }

      expect(await roundTrip(true), 1);
      expect(await roundTrip(false), 0);
      expect(await roundTrip('true'), 1);
      expect(await roundTrip('0'), 0);
      expect(await roundTrip(1), 1);
    });

    test('typed values and unparseable strings pass through unchanged',
        () async {
      await engine.save(
          Document(id: 'G2', docType: 'Gadget', payload: {
            'name': 'C',
            'enabled': 0,
            'count': 7,
            'weight': 2.25,
          }),
          roles);
      final back = (await engine.fetch('Gadget', 'G2'))!;
      expect(back.payload['enabled'], 0);
      expect(back.payload['count'], 7);
      expect(back.payload['weight'], 2.25);
      // A non-numeric string in a numeric field is left for validation —
      // normalization never invents a value.
      await engine.save(
          Document(id: 'G3', docType: 'Gadget', payload: {
            'name': 'D',
            'weight': 'heavy',
          }),
          roles);
      expect((await engine.fetch('Gadget', 'G3'))!.payload['weight'], 'heavy');
    });

    test('whole-number floats in int fields become ints', () async {
      await engine.save(
          Document(id: 'G4', docType: 'Gadget', payload: {
            'name': 'E',
            'count': 5.0, // JSON round-trips can widen ints to doubles
            'stars': '3.0',
          }),
          roles);
      final back = (await engine.fetch('Gadget', 'G4'))!;
      expect(back.payload['count'], 5);
      expect(back.payload['count'], isA<int>());
      expect(back.payload['stars'], 3);
    });
  });

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
