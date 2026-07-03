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

  testWidgets('AtlasTextInputRow renders prefix/suffix affixes in the editor',
      (tester) async {
    await tester.pumpWidget(wrap(const AtlasTextInputRow(
      label: 'Weight',
      value: '5',
      suffixText: 'kg',
      prefixText: '≈',
      onChanged: _noop,
    )));
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('≈'), findsOneWidget);
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

  testWidgets(
      'AtlasTextFieldEditor does not corrupt live input when the parent '
      'feeds back a normalised value while typing', (tester) async {
    // Regression for the money-input corruption: a parent that rebuilds on
    // every keystroke and normalises "1" -> "1.0" must NOT be echoed back into
    // the field while it has focus (which turned the next digit into "1.02"
    // instead of "12"). The editor only re-syncs from an external value when
    // it isn't focused.
    await tester.pumpWidget(wrap(_NormalisingEditorHarness()));

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, '1');
    await tester.pump();

    // The raw text the user typed survives — it is not rewritten to "1.00".
    expect(find.text('1'), findsOneWidget);
    expect(find.text('1.00'), findsNothing);
  });

  testWidgets(
      'AtlasTextFieldEditor reconciles to the external value on blur so stale '
      'text cannot outlive editing', (tester) async {
    // The focus guard drops external updates while typing; this pins the other
    // half of the contract — once focus is lost the controller must snap back
    // to the authoritative value. Here an unparsable entry is coerced to blank
    // by the parent, so after blur the field must show blank, not the stale
    // text that a save would never persist.
    await tester.pumpWidget(wrap(_NormalisingEditorHarness()));

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, 'abc');
    await tester.pump();
    // While focused, the just-typed text is still shown (update was dropped).
    expect(find.text('abc'), findsOneWidget);

    // Blur: the controller reconciles to the parent's coerced blank value.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(find.text('abc'), findsNothing);
  });

  testWidgets(
      'AtlasDateFieldRow exposes a clear button that fires onCleared, and only '
      'when there is a value and a handler', (tester) async {
    var cleared = false;
    await tester.pumpWidget(wrap(AtlasDateFieldRow(
      label: 'Delivery Date',
      value: '2026-07-03',
      onChanged: (_) {},
      onCleared: () => cleared = true,
    )));
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    expect(cleared, isTrue);

    // No value -> nothing to clear.
    await tester.pumpWidget(wrap(AtlasDateFieldRow(
      label: 'Delivery Date',
      value: null,
      onChanged: (_) {},
      onCleared: () {},
    )));
    expect(find.byIcon(Icons.close), findsNothing);

    // Value but no handler -> no clear affordance.
    await tester.pumpWidget(wrap(AtlasDateFieldRow(
      label: 'Delivery Date',
      value: '2026-07-03',
      onChanged: (_) {},
    )));
    expect(find.byIcon(Icons.close), findsNothing);
  });
}

/// A parent that mimics the form's per-keystroke rebuild: it stores whatever
/// the editor emits but feeds back a *normalised* copy ("1" -> "1.0"). If the
/// editor re-synced from that while focused it would corrupt the caret.
class _NormalisingEditorHarness extends StatefulWidget {
  @override
  State<_NormalisingEditorHarness> createState() =>
      _NormalisingEditorHarnessState();
}

class _NormalisingEditorHarnessState extends State<_NormalisingEditorHarness> {
  String _value = '';

  String _normalise(String raw) {
    // Mimics a money parent: parse to a number and echo back a *reformatted*
    // string ("1" -> "1.00"), and coerce an unparsable entry to blank — both
    // of which diverge from the user's raw keystrokes.
    final n = num.tryParse(raw);
    return n == null ? '' : n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return AtlasTextFieldEditor(
      value: _value,
      decoration: const InputDecoration(),
      readOnly: false,
      keyboardType: TextInputType.number,
      onChanged: (raw) => setState(() => _value = _normalise(raw)),
    );
  }
}

void _noop(String _) {}
