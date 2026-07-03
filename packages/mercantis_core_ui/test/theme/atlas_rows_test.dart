import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The form rows extracted from generic_form_view into public, reusable Atlas
/// components. These lock the APIs so any screen (incl. the hub) can render an
/// Atlas row.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(theme: MercantisTheme.light(), home: Scaffold(body: child));

  testWidgets('AtlasSelectorRow shows a placeholder and picks from the sheet',
      (tester) async {
    String? picked;
    await tester.pumpWidget(wrap(AtlasSelectorRow(
      label: 'Priority',
      value: null,
      options: const ['Low', 'High'],
      onChanged: (v) => picked = v,
    )));
    expect(find.text('Select Priority'), findsOneWidget);

    await tester.tap(find.text('Select Priority'));
    await tester.pumpAndSettle();
    expect(find.text('Low'), findsOneWidget);
    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    expect(picked, 'High');
  });

  testWidgets('AtlasDateFieldRow shows placeholder empty and formats a value',
      (tester) async {
    await tester.pumpWidget(wrap(AtlasDateFieldRow(
      label: 'Order Date',
      value: null,
      onChanged: (_) {},
    )));
    expect(find.text('Choose Order Date'), findsOneWidget);

    await tester.pumpWidget(wrap(AtlasDateFieldRow(
      label: 'Order Date',
      value: '2026-07-03',
      onChanged: (_) {},
    )));
    expect(find.text('3 Jul 2026'), findsOneWidget);
  });

  testWidgets('AtlasTimeFieldRow renders as a selector row', (tester) async {
    await tester.pumpWidget(wrap(AtlasTimeFieldRow(
      label: 'Start',
      value: null,
      onChanged: (_) {},
    )));
    expect(find.text('Choose Start'), findsOneWidget);
    expect(find.byType(AtlasFieldRow), findsOneWidget);
  });

  testWidgets('AtlasTextInputRow edits when writable, shows value when read-only',
      (tester) async {
    String? typed;
    await tester.pumpWidget(wrap(AtlasTextInputRow(
      label: 'Notes',
      value: 'hello',
      onChanged: (v) => typed = v,
    )));
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'world');
    expect(typed, 'world');

    await tester.pumpWidget(wrap(const AtlasTextInputRow(
      label: 'Notes',
      value: 'read me',
      readOnly: true,
      onChanged: _noop,
    )));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('read me'), findsOneWidget);
  });

  testWidgets('AtlasMoneyField shows a prefix and emits a num', (tester) async {
    num? emitted;
    await tester.pumpWidget(wrap(AtlasMoneyField(
      label: 'Rate',
      value: 12,
      prefixText: '€',
      onChanged: (v) => emitted = v,
    )));
    await tester.enterText(find.byType(TextField), '18.5');
    expect(emitted, 18.5);
  });

  testWidgets('AtlasSectionCard shows an upper-cased title over its child',
      (tester) async {
    await tester.pumpWidget(wrap(const AtlasSectionCard(
      name: 'Totals',
      child: Text('body'),
    )));
    expect(find.text('TOTALS'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });
}

void _noop(String _) {}
