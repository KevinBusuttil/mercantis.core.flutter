import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The single required-asterisk label used across every Atlas surface (rows,
/// stepper, link picker, floating labels) — required fields must announce
/// identically whichever constructor is used.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('announces "<label>, required" and hides the asterisk from a11y',
      (tester) async {
    await tester.pumpWidget(wrap(
      const AtlasLabel(label: 'Customer', required: true),
    ));
    expect(find.bySemanticsLabel('Customer, required'), findsOneWidget);
    // The asterisk is drawn but excluded from semantics (no bare "*" node).
    expect(find.bySemanticsLabel('*'), findsNothing);
  });

  testWidgets('optional field announces just the label', (tester) async {
    await tester.pumpWidget(wrap(const AtlasLabel(label: 'Notes')));
    expect(find.bySemanticsLabel('Notes'), findsOneWidget);
  });

  testWidgets('inheritStyle variant keeps the same required semantics',
      (tester) async {
    await tester.pumpWidget(wrap(
      const DefaultTextStyle(
        style: TextStyle(fontSize: 20),
        child: AtlasLabel.inheritStyle(label: 'Amount', required: true),
      ),
    ));
    expect(find.bySemanticsLabel('Amount, required'), findsOneWidget);
  });
}
