import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// ResponsiveScaffold has no AppBar, so a page pushed onto a Navigator would
/// lose the implicit back button. `automaticallyImplyLeading` restores it — a
/// back button appears only when the route can pop, and an explicit leading or
/// opting out suppresses it.
void main() {
  Future<void> pushScaffold(WidgetTester tester, ResponsiveScaffold scaffold)
      async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => scaffold),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a back button when the route can pop', (tester) async {
    await pushScaffold(
        tester, const ResponsiveScaffold(title: 'Detail', body: SizedBox()));
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('shows no back button at the root (nothing to pop)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ResponsiveScaffold(title: 'Home', body: SizedBox()),
    ));
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('automaticallyImplyLeading: false suppresses the back button',
      (tester) async {
    await pushScaffold(
      tester,
      const ResponsiveScaffold(
        title: 'Detail',
        automaticallyImplyLeading: false,
        body: SizedBox(),
      ),
    );
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('an explicit leading wins over the auto back button',
      (tester) async {
    await pushScaffold(
      tester,
      const ResponsiveScaffold(
        title: 'Detail',
        leading: Icon(Icons.close),
        body: SizedBox(),
      ),
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });
}
