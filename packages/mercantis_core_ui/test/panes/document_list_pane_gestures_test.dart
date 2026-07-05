import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Row swipe actions + pull-to-refresh on the shared document list pane.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('onRefresh renders a pull-to-refresh indicator', (tester) async {
    await tester.pumpWidget(host(DocumentListPane(
      title: 'Items',
      rows: const [DocumentListPaneRow(id: 'A', title: 'Alpha')],
      onRefresh: () async {},
    )));
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('a row without a swipe action has no Dismissible',
      (tester) async {
    await tester.pumpWidget(host(const DocumentListPane(
      title: 'Items',
      rows: [DocumentListPaneRow(id: 'A', title: 'Alpha')],
    )));
    expect(find.byType(Dismissible), findsNothing);
  });

  testWidgets('a row with a swipe action fires it on swipe (row stays)',
      (tester) async {
    var fired = 0;
    await tester.pumpWidget(host(DocumentListPane(
      title: 'Invoices',
      rows: [
        DocumentListPaneRow(
          id: 'INV-1',
          title: 'INV-1',
          swipeAction: RowSwipeAction(
            label: 'Record payment',
            icon: Icons.payments_outlined,
            onTrigger: () async => fired++,
          ),
        ),
      ],
    )));

    expect(find.byType(Dismissible), findsOneWidget);
    await tester.drag(find.text('INV-1'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(fired, 1); // action ran…
    expect(find.text('INV-1'), findsOneWidget); // …and the row snapped back
  });
}
