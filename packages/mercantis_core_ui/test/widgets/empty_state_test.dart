import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The Atlas empty state: a tinted icon disc + title, with optional message
/// and action. This is the one shared placeholder for empty lists/tables/search.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders icon, title, message and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(EmptyState(
      icon: Icons.search_off,
      title: 'No matches',
      message: 'Try a different search term.',
      action: FilledButton(
        onPressed: () => tapped = true,
        child: const Text('Clear'),
      ),
    )));

    expect(find.byIcon(Icons.search_off), findsOneWidget);
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Try a different search term.'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    expect(tapped, isTrue);
  });

  testWidgets('message and action are optional', (tester) async {
    await tester.pumpWidget(wrap(const EmptyState(title: 'Nothing here')));
    expect(find.text('Nothing here'), findsOneWidget);
    // Defaults to the inbox glyph.
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
