import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The business-worded child-table empty state (title + message + add CTA).
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(theme: MercantisTheme.light(), home: Scaffold(body: child));

  testWidgets('shows title, message and a firing add action', (tester) async {
    var added = false;
    await tester.pumpWidget(wrap(AtlasChildTableEmptyState(
      title: 'No items yet',
      message: 'Add an item to get started.',
      addLabel: 'Add Item',
      onAdd: () => added = true,
    )));
    expect(find.text('No items yet'), findsOneWidget);
    expect(find.text('Add an item to get started.'), findsOneWidget);
    await tester.tap(find.text('Add Item'));
    expect(added, isTrue);
  });

  testWidgets('omits the add button without an action', (tester) async {
    await tester.pumpWidget(wrap(const AtlasChildTableEmptyState(
      title: 'No items yet',
    )));
    expect(find.text('No items yet'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
