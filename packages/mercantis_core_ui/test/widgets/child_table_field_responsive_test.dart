import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Increment 2 of the responsive-forms work: the child-table line grid must
/// fill wide panes (desktop / tablet-landscape) and collapse to stacked
/// summary cards on narrow panes (phone / tablet-portrait) — both without
/// layout overflow. These pin that behaviour so the shared widget, which
/// renders every document's line items, can't silently regress.
void main() {
  const childType = DocType(
    id: 'Quote Item',
    name: 'Quote Item',
    module: 'Sales',
    permissions: [
      PermissionRule(role: 'System Manager', read: true, write: true, create: true),
    ],
    fields: [
      FieldDefinition(key: 'item_code', label: 'Item Code', type: FieldType.data),
      FieldDefinition(
          key: 'qty', label: 'Qty', type: FieldType.integer, defaultValue: '1'),
      FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency),
      FieldDefinition(
        key: 'amount',
        label: 'Amount',
        type: FieldType.currency,
        readOnly: true,
        formulaExpression: 'qty * rate',
      ),
    ],
  );

  final tableField = ResolvedFieldDefinition.fromFieldDefinition(
    const FieldDefinition(
      key: 'items',
      label: 'Items',
      type: FieldType.table,
      tableDocType: 'Quote Item',
    ),
  );

  List<Map<String, dynamic>> rows() => [
        {'item_code': 'WIDGET', 'qty': 3, 'rate': 12.0, 'amount': 36.0},
        {'item_code': 'GADGET', 'qty': 2, 'rate': 25.0, 'amount': 50.0},
      ];

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChildTableField(
            field: tableField,
            childDocType: childType,
            rows: rows(),
            readOnly: false,
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('wide pane renders the full grid (column headers) without overflow',
      (tester) async {
    await pumpAt(tester, const Size(1100, 900));
    expect(tester.takeException(), isNull);
    // Grid header labels are present on wide panes.
    expect(find.text('Item Code'), findsOneWidget);
    expect(find.text('Qty'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
  });

  testWidgets(
      'narrow pane collapses to summary cards (no header, tappable row titles) '
      'without overflow', (tester) async {
    await pumpAt(tester, const Size(380, 900));
    expect(tester.takeException(), isNull);
    // The grid header is gone; each row is a summary card titled by its first
    // text value, with the featured currency amount shown to two decimals.
    expect(find.text('Item Code'), findsNothing);
    expect(find.text('WIDGET'), findsOneWidget);
    expect(find.text('GADGET'), findsOneWidget);
    expect(find.text('36.00'), findsOneWidget);
    expect(find.text('50.00'), findsOneWidget);
  });

  testWidgets('empty child table shows the empty-state at both widths',
      (tester) async {
    for (final size in const [Size(1100, 900), Size(380, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChildTableField(
              field: tableField,
              childDocType: childType,
              rows: const [],
              readOnly: false,
              onChanged: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'layout error at $size');
      expect(find.text('No rows yet.'), findsOneWidget, reason: 'at $size');
    }
  });
}
