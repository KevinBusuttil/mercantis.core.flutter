import 'package:mercantis_core/mercantis_core.dart';
import 'package:test/test.dart';

/// Phase 1 (core report/dashboard execution) — verifies the engine that
/// every Hub report and dashboard will build on, without standing up a
/// database: a fake lister stands in for `DocumentEngine.list`.
void main() {
  Document doc(
    String id, {
    int docStatus = 0,
    Map<String, dynamic> payload = const {},
  }) =>
      Document(id: id, docType: 'Sales Invoice', docStatus: docStatus, payload: {
        ...payload,
      });

  // Records a fake document store keyed by docType, and captures the
  // arguments the engine passes through so we can assert on them.
  DocumentListFn listerReturning(List<Document> docs, {List<dynamic>? capture}) {
    return (
      String docType, {
      Map<String, dynamic>? filters,
      String? whereExpression,
      List<({String field, bool ascending})>? sortBy,
      int? limit,
      int? offset,
      Set<String>? userRoles,
    }) async {
      capture?.add((
        docType: docType,
        filters: filters,
        whereExpression: whereExpression,
        limit: limit,
      ));
      return docs;
    };
  }

  group('ReportValueFormatter', () {
    const f = ReportValueFormatter();

    test('absent values stay null, not the string "null"', () {
      expect(f.format(null), isNull);
      expect(f.format(null, type: 'currency'), isNull);
    });

    test('currency renders fixed 2dp with grouped thousands', () {
      expect(f.format(1234.5, type: 'currency'), '1,234.50');
      expect(f.format(-1000000, type: 'currency'), '-1,000,000.00');
    });

    test('numbers trim trailing zeros, booleans read as Yes/No', () {
      expect(f.format(1234.0, type: 'number'), '1,234');
      expect(f.format(true, type: 'check'), 'Yes');
      expect(f.format(false), 'No');
    });

    test('epoch ints and ISO strings format as dates', () {
      final epoch = DateTime.utc(2026, 1, 2).millisecondsSinceEpoch;
      expect(f.format(epoch, type: 'date'), '2026-01-02');
      expect(f.format('2026-06-04', type: 'date'), '2026-06-04');
    });
  });

  group('ReportEngine', () {
    ReportEngine engineWith(List<Document> docs, {List<dynamic>? capture}) =>
        ReportEngine(listerReturning(docs, capture: capture));

    const salesRegister = ReportDefinition(
      id: 'sales-register',
      name: 'Sales Register',
      docType: 'Sales Invoice',
      roles: ['Sales', 'Finance'],
      columns: [
        ReportColumn(fieldKey: 'id', label: 'Invoice'),
        ReportColumn(fieldKey: 'customer', label: 'Customer'),
        ReportColumn(fieldKey: 'grand_total', label: 'Total', type: 'currency'),
        ReportColumn(fieldKey: 'docstatus', label: 'Status'),
      ],
    );

    test('availableReports gates on role intersection; empty roles = public',
        () {
      final engine = engineWith([])
        ..register(salesRegister)
        ..register(const ReportDefinition(
          id: 'public', name: 'Public', docType: 'Item'));

      expect(
        engine.availableReports({'Finance'}).map((r) => r.id),
        containsAll(<String>['public', 'sales-register']),
      );
      expect(
        engine.availableReports({'Stock'}).map((r) => r.id),
        ['public'],
      );
    });

    test('project maps system + payload columns and formats currency', () {
      final engine = engineWith([]);
      final result = engine.project(salesRegister, [
        doc('SINV-0001',
            docStatus: 1,
            payload: {'customer': 'Acme', 'grand_total': 1500}),
      ]);

      expect(result.columnLabels, ['Invoice', 'Customer', 'Total', 'Status']);
      expect(result.rows.single, ['SINV-0001', 'Acme', '1,500.00', 'Submitted']);
      expect(result.isEmpty, isFalse);
    });

    test('execute forwards docType + filterExpression to the lister', () async {
      final capture = <dynamic>[];
      final engine = engineWith([doc('SINV-1')], capture: capture)
        ..register(const ReportDefinition(
          id: 'r',
          name: 'R',
          docType: 'Sales Invoice',
          filterExpression: 'docstatus == 1',
          columns: [ReportColumn(fieldKey: 'id', label: 'ID')],
        ));

      final result = await engine.execute('r', filters: {'customer': 'Acme'});
      expect(result.rowCount, 1);
      expect(capture.single.docType, 'Sales Invoice');
      expect(capture.single.whereExpression, 'docstatus == 1');
      expect(capture.single.filters, {'customer': 'Acme'});
    });

    test('execute throws for an unknown report id', () {
      expect(() => engineWith([]).execute('nope'), throwsArgumentError);
    });

    test('CSV escapes commas and quotes', () {
      final result = engineWith([]).project(
        const ReportDefinition(
          id: 'r',
          name: 'R',
          docType: 'X',
          columns: [ReportColumn(fieldKey: 'customer', label: 'Customer')],
        ),
        [doc('X-1', payload: {'customer': 'Acme, "Inc"'})],
      );
      expect(result.toCsv().trim().split('\n'),
          ['Customer', '"Acme, ""Inc"""']);
    });
  });

  group('DashboardEngine', () {
    test('resolves count / list / shortcut and isolates a bad widget',
        () async {
      final reportEngine = ReportEngine(listerReturning([]));
      final engine = DashboardEngine(
        listerReturning([
          doc('A', payload: {'customer': 'Acme'}),
          doc('B', payload: {'customer': 'Globex'}),
        ]),
        reportEngine,
      )..register(const DashboardDefinition(
          id: 'sales-overview',
          name: 'Sales Overview',
          widgets: [
            DashboardWidget(
                id: 'open', type: 'count', label: 'Open', config: {
              'docType': 'Sales Invoice',
            }),
            DashboardWidget(id: 'recent', type: 'list', label: 'Recent', config: {
              'docType': 'Sales Invoice',
              'columns': ['customer'],
            }),
            DashboardWidget(id: 'go', type: 'shortcut', label: 'All', config: {
              'route': '/list/Sales Invoice',
            }),
            DashboardWidget(
                id: 'broken', type: 'count', label: 'Broken', config: {}),
          ],
        ));

      final result = await engine.resolve('sales-overview');
      final byId = {for (final w in result.widgets) w.id: w};

      expect(byId['open']!.count, 2);
      expect(byId['recent']!.rows!.first['customer'], 'Acme');
      expect(byId['go']!.route, '/list/Sales Invoice');
      // Missing docType is isolated to its own tile, not fatal.
      expect(byId['broken']!.isError, isTrue);
      expect(byId['broken']!.error, contains('docType'));
    });
  });
}
