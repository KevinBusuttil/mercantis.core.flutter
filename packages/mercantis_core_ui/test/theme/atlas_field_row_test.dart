import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The Atlas field-row primitive: a mobile-first list row (tinted icon · quiet
/// label · readable value · chevron) that replaces the outlined input box.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders icon, placeholder, and a chevron when tappable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(AtlasFieldRow(
      icon: Icons.person_outline,
      label: 'Customer',
      required: true,
      placeholder: 'Choose Customer',
      onTap: () => taps++,
    )));
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.text('Choose Customer'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.text('Choose Customer'));
    expect(taps, 1);
  });

  testWidgets('shows the value instead of the placeholder when set',
      (tester) async {
    await tester.pumpWidget(wrap(const AtlasFieldRow(
      label: 'Customer',
      value: 'ACME Corp',
      placeholder: 'Choose Customer',
    )));
    expect(find.text('ACME Corp'), findsOneWidget);
    expect(find.text('Choose Customer'), findsNothing);
    // No onTap → not a selector → no chevron.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('trailing widget overrides the chevron', (tester) async {
    await tester.pumpWidget(wrap(AtlasFieldRow(
      label: 'Active',
      trailing: Switch(value: true, onChanged: (_) {}),
      onTap: () {},
    )));
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('AtlasSummaryCard shows its title and groups total rows',
      (tester) async {
    await tester.pumpWidget(wrap(const AtlasSummaryCard(
      title: 'Totals',
      children: [
        AtlasTotalRow(label: 'Net Total', value: '100.00'),
        AtlasTotalRow(label: 'Grand Total', value: '118.00', emphasize: true),
      ],
    )));
    expect(find.text('TOTALS'), findsOneWidget); // header is upper-cased
    expect(find.byType(AtlasTotalRow), findsNWidgets(2));
    expect(find.text('Net Total'), findsOneWidget);
    expect(find.text('Grand Total'), findsOneWidget);
  });

  testWidgets('AtlasSummaryCard omits the header when title is blank',
      (tester) async {
    await tester.pumpWidget(wrap(const AtlasSummaryCard(
      children: [AtlasTotalRow(label: 'Total', value: '5.00')],
    )));
    expect(find.byType(AtlasTotalRow), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
  });

  group('atlasFieldIcon', () {
    IconData? ic(String key, FieldType type) =>
        atlasFieldIcon(FieldDefinition(key: key, label: key, type: type));

    test('prefers a match on the field key', () {
      expect(ic('customer', FieldType.link), Icons.person_outline);
      expect(ic('supplier', FieldType.link), Icons.local_shipping_outlined);
      expect(ic('item', FieldType.link), Icons.inventory_2_outlined);
      expect(ic('warehouse', FieldType.link), Icons.warehouse_outlined);
      expect(ic('tax_code', FieldType.link), Icons.percent);
      expect(ic('currency', FieldType.link), Icons.attach_money);
    });

    test('falls back to the field type', () {
      expect(ic('transaction_date', FieldType.date), Icons.calendar_today_outlined);
      expect(ic('priority', FieldType.select), Icons.expand_more);
    });

    test('returns null (chip-less) when nothing meaningful fits', () {
      expect(ic('some_flag', FieldType.data), isNull);
    });
  });
}
