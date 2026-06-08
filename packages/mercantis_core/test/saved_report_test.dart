import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers ADR-050: generic saved reports. Exercises projection, filter →
/// predicate mapping, field validation against DocType metadata, ownership /
/// visibility gating, the in-memory registry, conversion from built-in report
/// definitions, JSON round-trip, and an end-to-end run through a real
/// DocumentEngine.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late MetadataRegistry registry;
  const owner = 'user-1';

  const salesInvoice = DocType(
    id: 'Sales Invoice',
    name: 'Sales Invoice',
    fields: [
      FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.data),
      FieldDefinition(
          key: 'grand_total', label: 'Total', type: FieldType.currency),
      FieldDefinition(key: 'region', label: 'Region', type: FieldType.data),
    ],
  );

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    registry = MetadataRegistry(database.db);
    await registry.register(salesInvoice);
  });

  tearDown(() => database.close());

  Document inv(String id,
          {required String customer,
          required num total,
          String region = 'North'}) =>
      Document(id: id, docType: 'Sales Invoice', payload: {
        'customer': customer,
        'grand_total': total,
        'region': region,
      });

  // A fake lister that records the predicates/sort it was called with and
  // returns canned documents — isolates the engine from SQL.
  ({List<ListFilter>? predicates, List<({String field, bool ascending})>? sortBy})
      captured = (predicates: null, sortBy: null);
  SavedReportListFn listerReturning(List<Document> docs) {
    return (
      String docType, {
      List<ListFilter>? predicates,
      List<({String field, bool ascending})>? sortBy,
      Set<String>? userRoles,
    }) async {
      captured = (predicates: predicates, sortBy: sortBy);
      return docs;
    };
  }

  SavedReportDefinition saved({
    List<SavedReportColumn>? columns,
    List<SavedReportFilter> filters = const [],
    List<SavedReportSort> sorts = const [],
    SavedReportVisibility visibility = SavedReportVisibility.private,
    String ownerUserId = owner,
  }) =>
      SavedReportDefinition(
        id: 'sr-1',
        name: 'My Invoices',
        sourceDocType: 'Sales Invoice',
        ownerUserId: ownerUserId,
        visibility: visibility,
        columns: columns ??
            const [
              SavedReportColumn(fieldKey: 'customer', order: 0),
              SavedReportColumn(fieldKey: 'grand_total', order: 1),
            ],
        filters: filters,
        sorts: sorts,
      );

  group('projection', () {
    test('projects visible columns in order with derived types', () async {
      final engine = SavedReportEngine(
        listerReturning([inv('A', customer: 'Acme', total: 1234.5)]),
        registry,
      );
      final result = await engine.execute(saved());

      expect(result.columnLabels, ['customer', 'grand_total']);
      // grand_total type derived from FieldType.currency → grouped 2dp.
      expect(result.rows.single, ['Acme', '1,234.50']);
    });

    test('honours order, visibility and label override', () async {
      final engine = SavedReportEngine(
        listerReturning([inv('A', customer: 'Acme', total: 10)]),
        registry,
      );
      final result = await engine.execute(saved(columns: const [
        SavedReportColumn(fieldKey: 'grand_total', order: 2),
        SavedReportColumn(fieldKey: 'region', order: 0, visible: false),
        SavedReportColumn(
            fieldKey: 'customer', labelOverride: 'Client', order: 1),
      ]));

      expect(result.columnLabels, ['Client', 'grand_total']); // region hidden
    });
  });

  group('filters → predicates', () {
    test('maps operators and resolves runtime > value > default', () async {
      final engine = SavedReportEngine(listerReturning([]), registry);
      await engine.execute(
        saved(filters: const [
          SavedReportFilter(
              fieldKey: 'region',
              op: SavedReportFilterOperator.equals,
              defaultValue: 'North'),
          SavedReportFilter(
              fieldKey: 'customer',
              op: SavedReportFilterOperator.contains,
              value: 'Ac'),
          SavedReportFilter(
              fieldKey: 'grand_total',
              op: SavedReportFilterOperator.greaterThanOrEqual,
              value: 100),
        ]),
        runtimeFilterValues: {'region': 'South'}, // overrides the default
      );

      final preds = captured.predicates!;
      expect(preds, hasLength(3));
      expect(preds[0].field, 'region');
      expect(preds[0].op, FilterOp.eq);
      expect(preds[0].value, 'South'); // runtime override won
      expect(preds[1].op, FilterOp.like);
      expect(preds[1].value, '%Ac%');
      expect(preds[2].op, FilterOp.gte);
      expect(preds[2].value, 100);
    });

    test('unary operators ignore values; optional unset filters skip',
        () async {
      final engine = SavedReportEngine(listerReturning([]), registry);
      await engine.execute(saved(filters: const [
        SavedReportFilter(
            fieldKey: 'region', op: SavedReportFilterOperator.isNotNull),
        SavedReportFilter(
            fieldKey: 'customer', op: SavedReportFilterOperator.equals),
      ]));

      final preds = captured.predicates!;
      expect(preds, hasLength(1)); // the unset optional equals filter is skipped
      expect(preds.single.op, FilterOp.isNotNull);
    });

    test('a required filter with no value throws', () async {
      final engine = SavedReportEngine(listerReturning([]), registry);
      expect(
        () => engine.execute(saved(filters: const [
          SavedReportFilter(
              fieldKey: 'customer',
              op: SavedReportFilterOperator.equals,
              required: true),
        ])),
        throwsA(isA<SavedReportException>()),
      );
    });

    test('sorts map to sortBy', () async {
      final engine = SavedReportEngine(listerReturning([]), registry);
      await engine.execute(saved(sorts: const [
        SavedReportSort(
            fieldKey: 'grand_total',
            direction: SavedReportSortDirection.descending),
      ]));
      expect(captured.sortBy, [(field: 'grand_total', ascending: false)]);
    });
  });

  group('validation', () {
    test('rejects an unknown field reference', () async {
      final engine = SavedReportEngine(listerReturning([]), registry);
      expect(
        () => engine.execute(saved(columns: const [
          SavedReportColumn(fieldKey: 'not_a_field', order: 0),
        ])),
        throwsA(isA<SavedReportException>()),
      );
    });

    test('rejects a report with no visible columns', () async {
      final engine = SavedReportEngine(listerReturning([]), registry);
      expect(
        () => engine.execute(saved(columns: const [
          SavedReportColumn(fieldKey: 'customer', order: 0, visible: false),
        ])),
        throwsA(isA<SavedReportException>()),
      );
    });

    test('rejects an unregistered source DocType', () async {
      final engine = SavedReportEngine(listerReturning([]), registry);
      expect(
        () => engine.execute(SavedReportDefinition(
          name: 'x',
          sourceDocType: 'Ghost',
          ownerUserId: owner,
          columns: const [SavedReportColumn(fieldKey: 'id', order: 0)],
        )),
        throwsA(isA<SavedReportException>()),
      );
    });
  });

  group('access control', () {
    test('private report blocks non-owners, shared allows anyone', () async {
      final engine = SavedReportEngine(listerReturning([]), registry);

      expect(
        () => engine.execute(saved(), requestingUserId: 'someone-else'),
        throwsA(isA<SavedReportException>()),
      );
      // Owner is fine.
      await engine.execute(saved(), requestingUserId: owner);
      // Shared is fine for anyone.
      await engine.execute(
        saved(visibility: SavedReportVisibility.shared),
        requestingUserId: 'someone-else',
      );
    });

    test('accessibleSavedReports = shared + own private, sorted', () {
      final engine = SavedReportEngine(listerReturning([]), registry);
      engine.register(SavedReportDefinition(
          id: 'b', name: 'Bravo', sourceDocType: 'Sales Invoice', ownerUserId: owner));
      engine.register(SavedReportDefinition(
          id: 'a',
          name: 'Alpha',
          sourceDocType: 'Sales Invoice',
          ownerUserId: 'other',
          visibility: SavedReportVisibility.shared));
      engine.register(SavedReportDefinition(
          id: 'c', name: 'Charlie', sourceDocType: 'Sales Invoice', ownerUserId: 'other'));

      final names = engine.accessibleSavedReports(owner).map((r) => r.name);
      expect(names, ['Alpha', 'Bravo']); // Charlie (other's private) excluded
    });
  });

  group('registry + conversion', () {
    test('register / get / remove / all sorted by name', () {
      final engine = SavedReportEngine(listerReturning([]), registry);
      engine.register(saved());
      expect(engine.get('sr-1')!.name, 'My Invoices');
      engine.remove('sr-1');
      expect(engine.get('sr-1'), isNull);
    });

    test('convert clones a built-in report definition', () {
      final engine = SavedReportEngine(listerReturning([]), registry);
      const def = ReportDefinition(
        id: 'sales-register',
        name: 'Sales Register',
        docType: 'Sales Invoice',
        columns: [
          ReportColumn(fieldKey: 'customer', label: 'Customer'),
          ReportColumn(fieldKey: 'grand_total', label: 'Total'),
        ],
      );
      final sr = engine.convert(def, ownerUserId: owner);

      expect(sr.baseReportId, 'sales-register');
      expect(sr.sourceDocType, 'Sales Invoice');
      expect(sr.columns.map((c) => c.fieldKey), ['customer', 'grand_total']);
      expect(sr.columns.every((c) => c.visible), isTrue);
      expect(engine.get(sr.id), isNotNull);
    });
  });

  test('JSON round-trip preserves config (operator under "operator" key)', () {
    final sr = saved(
      filters: const [
        SavedReportFilter(
            fieldKey: 'grand_total',
            op: SavedReportFilterOperator.greaterThan,
            value: 50,
            required: true),
      ],
      sorts: const [SavedReportSort(fieldKey: 'customer')],
    );
    final json = sr.toJson();
    expect(json['filters'][0]['operator'], 'greaterThan');

    final restored = SavedReportDefinition.fromJson(json);
    expect(restored.id, 'sr-1');
    expect(restored.visibility, SavedReportVisibility.private);
    expect(restored.filters.single.op, SavedReportFilterOperator.greaterThan);
    expect(restored.filters.single.required, isTrue);
    expect(restored.sorts.single.fieldKey, 'customer');
    expect(restored.columns.map((c) => c.fieldKey), ['customer', 'grand_total']);
  });

  test('end-to-end through a real DocumentEngine filters via SQL', () async {
    final composer = MetaComposer(registry, database.db);
    final sync = SyncEngine(database: database.db, registry: registry);
    final engine = DocumentEngine(
      database: database.db,
      registry: registry,
      metaComposer: composer,
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(database.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: EventEmitter(),
      deviceId: 'd',
      userId: 'u',
    );
    const roles = {'System Manager'};
    await engine.save(inv('', customer: 'Acme', total: 100), roles);
    await engine.save(inv('', customer: 'Globex', total: 900), roles);

    final saver = SavedReportEngine(engine.list, registry);
    final result = await saver.execute(saved(
      columns: const [
        SavedReportColumn(fieldKey: 'customer', order: 0),
        SavedReportColumn(fieldKey: 'grand_total', order: 1),
      ],
      filters: const [
        SavedReportFilter(
            fieldKey: 'grand_total',
            op: SavedReportFilterOperator.greaterThan,
            value: 500),
      ],
    ));

    expect(result.rowCount, 1);
    expect(result.rows.single, ['Globex', '900.00']);
  });
}
