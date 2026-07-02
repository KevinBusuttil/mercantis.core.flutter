import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// A child-table link column (e.g. a Quotation line's Item) must render a real
/// LinkPickerField you can search/select — not a raw-id text box. Covers both
/// the wide grid cell and the per-row editor (the only edit path on a phone).
void main() {
  const childType = DocType(
    id: 'Quote Item',
    name: 'Quote Item',
    module: 'Sales',
    permissions: [
      PermissionRule(role: 'System Manager', read: true, write: true, create: true),
    ],
    fields: [
      FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item'),
      FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.integer, defaultValue: '1'),
    ],
  );

  final tableField = ResolvedFieldDefinition.fromFieldDefinition(
    const FieldDefinition(
        key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Quote Item'),
  );

  Future<void> pump(WidgetTester tester, Size size,
      {required List<Map<String, dynamic>> rows}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChildTableField(
              field: tableField,
              childDocType: childType,
              rows: rows,
              readOnly: false,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('wide grid renders a LinkPickerField for the Item cell',
      (tester) async {
    await pump(tester, const Size(1100, 900), rows: [
      {'item': '', 'qty': 1},
    ]);
    expect(tester.takeException(), isNull);
    expect(find.byType(LinkPickerField), findsOneWidget);
  });

  testWidgets('the per-row editor renders a LinkPickerField for the Item field',
      (tester) async {
    // 700px: card mode for the field, but wide enough that the editor opens as
    // a dialog (not a phone sheet).
    await pump(tester, const Size(700, 900), rows: [
      {'item': '', 'qty': 1},
    ]);
    // Card mode shows a summary; tap it to open the editor.
    await tester.tap(find.text('Row 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(LinkPickerField), findsWidgets);
  });
}
