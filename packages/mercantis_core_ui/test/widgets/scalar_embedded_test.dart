import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Phase 1c: the composite scalar editors gain an `embedded` (labelless,
/// borderless) mode so an Atlas field row can supply the card + label on a
/// form, while their default outlined rendering is preserved for child-table
/// cells / other callers.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('RatingField: outlined by default, bare when embedded',
      (tester) async {
    await tester.pumpWidget(wrap(RatingField(
      label: 'Score',
      required: false,
      value: 3,
      readOnly: false,
      onChanged: (_) {},
    )));
    expect(find.byType(InputDecorator), findsOneWidget);
    expect(find.byIcon(Icons.star), findsWidgets);

    await tester.pumpWidget(wrap(RatingField(
      label: 'Score',
      required: false,
      value: 3,
      readOnly: false,
      onChanged: (_) {},
      embedded: true,
    )));
    expect(find.byType(InputDecorator), findsNothing);
    expect(find.byIcon(Icons.star), findsWidgets);
  });

  testWidgets('DurationField: outlined by default, bare when embedded',
      (tester) async {
    await tester.pumpWidget(wrap(DurationField(
      label: 'Length',
      required: false,
      value: 3660,
      readOnly: false,
      onChanged: (_) {},
    )));
    // The outer outlined box carries the floating label (the two hours/minutes
    // TextFields have their own inner decorators, so count the label instead).
    expect(find.text('Length'), findsOneWidget);

    await tester.pumpWidget(wrap(DurationField(
      label: 'Length',
      required: false,
      value: 3660,
      readOnly: false,
      onChanged: (_) {},
      embedded: true,
    )));
    // Embedded drops the outer label; only the hours + minutes fields remain.
    expect(find.text('Length'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('ColorField: outlined by default, bare when embedded',
      (tester) async {
    await tester.pumpWidget(wrap(const ColorField(
      label: 'Tag',
      required: false,
      value: null,
      readOnly: false,
      onChanged: _noop,
    )));
    expect(find.byType(InputDecorator), findsOneWidget);
    expect(find.text('No colour'), findsOneWidget);

    await tester.pumpWidget(wrap(const ColorField(
      label: 'Tag',
      required: false,
      value: '#FF0000',
      readOnly: false,
      onChanged: _noop,
      embedded: true,
    )));
    expect(find.byType(InputDecorator), findsNothing);
    expect(find.text('#FF0000'), findsOneWidget);
  });

  testWidgets('CodeField embedded still edits', (tester) async {
    String? typed;
    await tester.pumpWidget(wrap(CodeField(
      label: 'Snippet',
      required: false,
      value: '',
      readOnly: false,
      onChanged: (v) => typed = v,
      embedded: true,
    )));
    await tester.enterText(find.byType(TextField), 'x=1');
    expect(typed, 'x=1');
  });
}

void _noop(dynamic _) {}
