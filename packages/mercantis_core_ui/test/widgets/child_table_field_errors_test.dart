import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Phase 3c: the engine's per-row `ValidationError`s (field keys like
/// `items[1].rate`) are distributed onto the offending child rows. These pin
/// that a row flagged by [ChildTableField.errors] shows a badge in both the
/// grid and card layouts, and surfaces the message inline in the row editor —
/// so a failed save points at the exact line, not just a top-of-form banner.
void main() {
  const childType = DocType(
    id: 'Quote Item',
    name: 'Quote Item',
    module: 'Sales',
    permissions: [
      PermissionRule(
          role: 'System Manager', read: true, write: true, create: true),
    ],
    fields: [
      FieldDefinition(key: 'item_code', label: 'Item Code', type: FieldType.data),
      FieldDefinition(
          key: 'qty', label: 'Qty', type: FieldType.integer, defaultValue: '1'),
      FieldDefinition(
          key: 'rate', label: 'Rate', type: FieldType.currency, required: true),
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
        {'item_code': 'WIDGET', 'qty': 3, 'rate': 12.0},
        {'item_code': 'GADGET', 'qty': 2, 'rate': null},
      ];

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    Map<int, Map<String, String>>? errors,
  }) async {
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
            errors: errors,
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('grid: only the flagged row shows an error badge', (tester) async {
    await pumpAt(tester, const Size(1100, 900), errors: {
      1: {'rate': 'Rate is required'},
    });
    expect(tester.takeException(), isNull);
    // Exactly one row is flagged, so exactly one trailing error badge shows;
    // the clean row keeps its plain "edit row" affordance.
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('card: the flagged row shows the message inline', (tester) async {
    await pumpAt(tester, const Size(380, 900), errors: {
      1: {'rate': 'Rate is required'},
    });
    expect(tester.takeException(), isNull);
    // Card mode surfaces the actual message under the row title.
    expect(find.text('Rate is required'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('no errors => no badges at either width', (tester) async {
    for (final size in const [Size(1100, 900), Size(380, 900)]) {
      await pumpAt(tester, size);
      expect(find.byIcon(Icons.error_outline), findsNothing,
          reason: 'at $size');
    }
  });

  testWidgets('row editor shows a field error inline', (tester) async {
    // 700px keeps the field in card mode but opens the editor as a dialog so
    // the "Done" action stays on-screen.
    await pumpAt(tester, const Size(700, 900), errors: {
      1: {'rate': 'Rate is required'},
    });

    // Open the flagged row's editor.
    await tester.tap(find.text('GADGET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Editor is open (Done present) and the field error is rendered inline.
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Rate is required'), findsWidgets);
  });

  testWidgets('row editor shows a row-level error banner', (tester) async {
    await pumpAt(tester, const Size(700, 900), errors: {
      0: {'': "Row 1 duplicates 'item_code' from row 2."},
    });

    await tester.tap(find.text('WIDGET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Done'), findsOneWidget);
    expect(find.text("Row 1 duplicates 'item_code' from row 2."),
        findsWidgets);
  });

  group('partitionValidationErrors', () {
    test('routes parent, child-field and whole-row errors by fieldKey', () {
      final split = partitionValidationErrors(const [
        ValidationError(
            stage: 'RequiredField',
            fieldKey: 'customer_type',
            message: 'Customer Type is required'),
        ValidationError(
            stage: 'ChildTableValidation',
            fieldKey: 'items[2].rate',
            message: 'Row 3: Rate is required'),
        ValidationError(
            stage: 'ChildTableValidation',
            fieldKey: 'items[0]',
            message: "Row 1: duplicates 'item' from row 2."),
      ]);

      // Parent field lands in the flat map.
      expect(split.parent, {'customer_type': 'Customer Type is required'});

      // Child field is nested table → row → field, with the "Row N:" prefix
      // stripped (the index is already the key).
      expect(split.child['items']![2]!['rate'], 'Rate is required');
      // Whole-row error uses the empty-string field key.
      expect(split.child['items']![0]![''], "duplicates 'item' from row 2.");
    });

    test('ignores errors with no fieldKey and handles an empty list', () {
      final split = partitionValidationErrors(const [
        ValidationError(stage: 'X', message: 'no field attribution'),
      ]);
      expect(split.parent, isEmpty);
      expect(split.child, isEmpty);
      expect(partitionValidationErrors(const []).parent, isEmpty);
    });
  });
}
