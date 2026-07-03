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

  testWidgets('wide pane renders the full grid header row without overflow',
      (tester) async {
    await pumpAt(tester, const Size(1100, 900));
    expect(tester.takeException(), isNull);
    // The "#" index label appears only in the grid header row (card mode uses
    // numbered chips instead), so it uniquely proves the grid rendered.
    expect(find.text('#'), findsOneWidget);
    // Column labels are present. They're also echoed as each data cell's hint
    // text (kept in the tree even when the cell has a value), so match
    // one-or-more rather than a strict count.
    expect(find.text('Item Code'), findsWidgets);
    expect(find.text('Amount'), findsWidgets);
  });

  testWidgets(
      'narrow pane collapses to summary cards (no header, tappable row titles) '
      'without overflow', (tester) async {
    await pumpAt(tester, const Size(380, 900));
    expect(tester.takeException(), isNull);
    // No grid header row on a narrow pane...
    expect(find.text('#'), findsNothing);
    expect(find.text('Item Code'), findsNothing);
    // ...instead each row is a summary card titled by its first text value,
    // with the featured currency amount shown to two decimals.
    expect(find.text('WIDGET'), findsOneWidget);
    expect(find.text('GADGET'), findsOneWidget);
    expect(find.text('36.00'), findsOneWidget);
    expect(find.text('50.00'), findsOneWidget);
  });

  testWidgets(
      'card-mode editor recomputes the row formula (amount = qty * rate) '
      'and saves the derived value', (tester) async {
    // 700px: the field pane is still < 720 (card mode), but the screen is
    // wide enough that the per-row editor opens as a dialog rather than a
    // draggable sheet — keeping the "Done" action reliably on-screen.
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    List<Map<String, dynamic>>? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChildTableField(
            field: tableField,
            childDocType: childType,
            rows: [
              {'item_code': 'WIDGET', 'qty': 3, 'rate': 12.0, 'amount': 36.0},
            ],
            readOnly: false,
            onChanged: (next) => captured = next,
          ),
        ),
      ),
    ));
    await tester.pump();

    // Open the per-row editor by tapping the summary card.
    await tester.tap(find.text('WIDGET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Change qty 3 -> 5 via the Atlas quantity stepper; amount must re-derive
    // to 5 * 12 = 60 and be saved.
    final stepper = find.byType(AtlasQuantityStepper);
    expect(stepper, findsOneWidget);
    final qtyField =
        find.descendant(of: stepper, matching: find.byType(TextField));
    await tester.enterText(qtyField, '5');
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(captured, isNotNull);
    expect(captured!.single['qty'], 5);
    expect(captured!.single['amount'], 60.0);
  });

  testWidgets('a float `discount` column is not treated as a quantity stepper',
      (tester) async {
    const withDiscount = DocType(
      id: 'Disc Item',
      name: 'Disc Item',
      module: 'Sales',
      permissions: [
        PermissionRule(
            role: 'System Manager', read: true, write: true, create: true),
      ],
      fields: [
        FieldDefinition(key: 'item_code', label: 'Item Code', type: FieldType.data),
        FieldDefinition(
            key: 'qty', label: 'Qty', type: FieldType.integer, defaultValue: '1'),
        FieldDefinition(key: 'discount', label: 'Discount', type: FieldType.float),
      ],
    );
    final discField = ResolvedFieldDefinition.fromFieldDefinition(
      const FieldDefinition(
        key: 'items',
        label: 'Items',
        type: FieldType.table,
        tableDocType: 'Disc Item',
      ),
    );
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChildTableField(
            field: discField,
            childDocType: withDiscount,
            rows: [
              {'item_code': 'WIDGET', 'qty': 3, 'discount': 1.5},
            ],
            readOnly: false,
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('WIDGET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Only qty (integer) becomes a stepper; the float `discount` (which merely
    // *contains* "count") stays a plain numeric field.
    expect(find.byType(AtlasQuantityStepper), findsOneWidget);
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
      // Business-worded empty state derived from the table label ("Items"),
      // with a single "Add Item" call to action (the footer add is hidden
      // while empty).
      expect(find.text('No items yet'), findsOneWidget, reason: 'at $size');
      expect(find.text('Add Item'), findsOneWidget, reason: 'at $size');
    }
  });

  testWidgets('read-only empty table shows no add action', (tester) async {
    tester.view.physicalSize = const Size(380, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChildTableField(
            field: tableField,
            childDocType: childType,
            rows: const [],
            readOnly: true,
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('No items yet'), findsOneWidget);
    expect(find.text('Add Item'), findsNothing);
  });
}
