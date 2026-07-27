import 'dart:convert';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers ADR-046: bulk CSV/JSON import & export.
void main() {
  setUpAll(sqfliteFfiInit);

  const item = DocType(
    id: 'Item',
    name: 'Item',
    fields: [
      FieldDefinition(key: 'item_name', label: 'Name', type: FieldType.data),
      FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.integer),
      FieldDefinition(key: 'price', label: 'Price', type: FieldType.currency),
      FieldDefinition(key: 'active', label: 'Active', type: FieldType.check),
    ],
  );
  const roles = {'System Manager'};

  Future<({MercantisDatabase db, DocumentEngine engine, MetadataRegistry registry})>
      newStack() async {
    final db = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final registry = MetadataRegistry(db.db);
    await registry.register(item);
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
      deviceId: 'd',
      userId: 'u',
    );
    return (db: db, engine: engine, registry: registry);
  }

  group('CsvCodec', () {
    test('encode quotes cells with separators/quotes/newlines', () {
      final csv = CsvCodec.encode(
        headers: ['a', 'b', 'c'],
        rows: [
          {'a': 'plain', 'b': 'has,comma', 'c': 'say "hi"'},
          {'a': 'line\nbreak', 'b': '', 'c': 'x'},
        ],
      );
      expect(csv, 'a,b,c\n'
          'plain,"has,comma","say ""hi"""\n'
          '"line\nbreak",,x\n');
    });

    test('decode round-trips quoted fields incl embedded comma/quote/newline',
        () {
      const csv = 'a,b,c\n'
          'plain,"has,comma","say ""hi"""\n'
          '"line\nbreak",,x\n';
      final table = CsvCodec.decode(csv);
      expect(table.headers, ['a', 'b', 'c']);
      expect(table.rows[0],
          {'a': 'plain', 'b': 'has,comma', 'c': 'say "hi"'});
      expect(table.rows[1], {'a': 'line\nbreak', 'b': '', 'c': 'x'});
    });

    test('empty input yields an empty table', () {
      final table = CsvCodec.decode('');
      expect(table.headers, isEmpty);
      expect(table.rows, isEmpty);
    });

    test('an unterminated quoted cell throws', () {
      expect(() => CsvCodec.decode('a,b\n"oops,nope\n'),
          throwsA(isA<ImportExportException>()));
    });
  });

  group('export', () {
    test('CSV header order + value stringification', () async {
      final s = await newStack();
      await s.engine.save(
          Document(id: 'I-2', docType: 'Item', payload: {
            'item_name': 'Widget',
            'qty': 5,
            'price': 9.5,
            'active': true,
          }),
          roles);
      await s.engine.save(
          Document(id: 'I-1', docType: 'Item', payload: {'item_name': 'Gadget'}),
          roles);

      final csv = await DataExporter(s.engine, s.registry)
          .export(docType: 'Item', format: ImportExportFormat.csv);

      final table = CsvCodec.decode(csv);
      expect(table.headers,
          ['id', 'company', 'docstatus', 'item_name', 'qty', 'price', 'active']);
      // Sorted by id ascending → I-1 first.
      expect(table.rows[0]['id'], 'I-1');
      expect(table.rows[0]['item_name'], 'Gadget');
      expect(table.rows[0]['qty'], ''); // absent → empty
      expect(table.rows[1]['id'], 'I-2');
      expect(table.rows[1]['qty'], '5');
      expect(table.rows[1]['price'], '9.5');
      // Checks persist canonically as 0/1 (save-time normalization), so
      // that's what stringifies — and what the importer reads back as true.
      expect(table.rows[1]['active'], '1');
      await s.db.close();
    });

    test('JSON envelope carries payload + children', () async {
      final s = await newStack();
      await s.engine.save(
          Document(id: 'I-1', docType: 'Item', payload: {'item_name': 'X'},
              children: {
                'lines': [
                  ChildRow(
                      id: 'c1',
                      parentId: 'I-1',
                      parentDocType: 'Item',
                      tableName: 'lines',
                      rowIndex: 0,
                      payload: {'sku': 'A'}),
                ],
              }),
          roles);

      final json = await DataExporter(s.engine, s.registry)
          .export(docType: 'Item', format: ImportExportFormat.json);
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['docType'], 'Item');
      final docs = decoded['documents'] as List;
      expect(docs, hasLength(1));
      expect(docs[0]['payload']['item_name'], 'X');
      expect(docs[0]['children']['lines'][0]['sku'], 'A');
      await s.db.close();
    });

    test('exporting an unregistered DocType throws', () async {
      final s = await newStack();
      expect(
        () => DataExporter(s.engine, s.registry)
            .export(docType: 'Ghost', format: ImportExportFormat.csv),
        throwsA(isA<ImportExportException>()),
      );
      await s.db.close();
    });
  });

  group('import', () {
    test('CSV inserts new docs with coerced types', () async {
      final s = await newStack();
      const csv = 'id,qty,price,active,item_name\n'
          'I-1,3,4.25,yes,Bolt\n';
      final report = await DataImporter(s.engine, s.registry).import(
        docType: 'Item',
        data: csv,
        format: ImportExportFormat.csv,
      );

      expect(report.rowsRead, 1);
      expect(report.insertedCount, 1);
      final doc = await s.engine.fetch('Item', 'I-1');
      expect(doc!.payload['qty'], 3); // int
      expect(doc.payload['price'], 4.25); // double
      expect(doc.payload['active'], 1); // check, normalized to 0/1 on save
      expect(doc.payload['item_name'], 'Bolt');
      await s.db.close();
    });

    test('a bad cell fails only its own row; others still import', () async {
      final s = await newStack();
      const csv = 'id,qty\n'
          'I-1,notanumber\n'
          'I-2,7\n';
      final report = await DataImporter(s.engine, s.registry).import(
          docType: 'Item', data: csv, format: ImportExportFormat.csv);

      expect(report.rowsRead, 2);
      expect(report.failedCount, 1);
      expect(report.insertedCount, 1);
      expect(report.outcomes[0].status, ImportRowStatus.failed);
      expect(report.outcomes[0].rowIndex, 0);
      expect(await s.engine.fetch('Item', 'I-2'), isNotNull);
      expect(await s.engine.fetch('Item', 'I-1'), isNull);
      await s.db.close();
    });

    test('conflict policies: overwrite / skipExisting / fail', () async {
      final s = await newStack();
      await s.engine.save(
          Document(id: 'I-1', docType: 'Item', payload: {'item_name': 'Old'}),
          roles);
      String csv(String name) => 'id,item_name\nI-1,$name\n';

      final overwrite = await DataImporter(s.engine, s.registry).import(
          docType: 'Item',
          data: csv('New'),
          format: ImportExportFormat.csv,
          conflictPolicy: ImportConflictPolicy.overwrite);
      expect(overwrite.updatedCount, 1);
      expect((await s.engine.fetch('Item', 'I-1'))!.payload['item_name'], 'New');

      final skip = await DataImporter(s.engine, s.registry).import(
          docType: 'Item',
          data: csv('Skipped'),
          format: ImportExportFormat.csv,
          conflictPolicy: ImportConflictPolicy.skipExisting);
      expect(skip.skippedCount, 1);
      expect((await s.engine.fetch('Item', 'I-1'))!.payload['item_name'], 'New');

      final fail = await DataImporter(s.engine, s.registry).import(
          docType: 'Item',
          data: csv('Nope'),
          format: ImportExportFormat.csv,
          conflictPolicy: ImportConflictPolicy.fail);
      expect(fail.failedCount, 1);
      await s.db.close();
    });

    test('JSON import inserts docs, retargets docType, rebuilds children',
        () async {
      final s = await newStack();
      final json = jsonEncode({
        'docType': 'SomethingElse',
        'documents': [
          {
            'id': 'J-1',
            'docType': 'SomethingElse',
            'docStatus': 0,
            'payload': {'item_name': 'FromJson'},
            'children': {
              'lines': [
                {'sku': 'A'},
                {'sku': 'B'},
              ],
            },
          },
        ],
      });

      final report = await DataImporter(s.engine, s.registry).import(
          docType: 'Item', data: json, format: ImportExportFormat.json);

      expect(report.insertedCount, 1);
      final doc = await s.engine.fetch('Item', 'J-1');
      expect(doc!.docType, 'Item'); // retargeted
      expect(doc.payload['item_name'], 'FromJson');
      expect(doc.children['lines'], hasLength(2));
      expect(doc.children['lines']![1].payload['sku'], 'B');
      await s.db.close();
    });

    test('malformed JSON throws', () async {
      final s = await newStack();
      expect(
        () => DataImporter(s.engine, s.registry)
            .import(docType: 'Item', data: '{not json', format: ImportExportFormat.json),
        throwsA(isA<ImportExportException>()),
      );
      await s.db.close();
    });

    test('importing into an unregistered DocType throws', () async {
      final s = await newStack();
      expect(
        () => DataImporter(s.engine, s.registry).import(
            docType: 'Ghost', data: 'id\n', format: ImportExportFormat.csv),
        throwsA(isA<ImportExportException>()),
      );
      await s.db.close();
    });
  });

  test('CSV export → import round-trips into a fresh store', () async {
    final src = await newStack();
    await src.engine.save(
        Document(id: 'I-1', docType: 'Item', payload: {
          'item_name': 'Round, Trip',
          'qty': 2,
          'price': 1.5,
          'active': false,
        }),
        roles);
    final csv = await DataExporter(src.engine, src.registry)
        .export(docType: 'Item', format: ImportExportFormat.csv);
    await src.db.close();

    final dst = await newStack();
    final report = await DataImporter(dst.engine, dst.registry)
        .import(docType: 'Item', data: csv, format: ImportExportFormat.csv);

    expect(report.insertedCount, 1);
    final doc = await dst.engine.fetch('Item', 'I-1');
    expect(doc!.payload['item_name'], 'Round, Trip'); // comma survived quoting
    expect(doc.payload['qty'], 2);
    expect(doc.payload['price'], 1.5);
    expect(doc.payload['active'], 0); // check, normalized to 0/1 on save
    await dst.db.close();
  });
}
