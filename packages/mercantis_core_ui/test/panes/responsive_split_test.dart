import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Phase 4: the master-detail split sizes its panes from its own layout
/// constraints (not the window), caps the list at a fraction of the available
/// width, and protects a minimum detail width by dropping the aside first, then
/// narrowing the list. These pin that so an embedded/narrow pane can't starve
/// the detail area.
void main() {
  const listKey = Key('pane-list');
  const detailKey = Key('pane-detail');
  const asideKey = Key('pane-aside');

  Future<void> pump(
    WidgetTester tester, {
    required Size window,
    double? paneWidth,
    bool withAside = false,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget split = ResponsiveSplit(
      list: Container(key: listKey, color: const Color(0xFF001122)),
      detail: Container(key: detailKey, color: const Color(0xFF112233)),
      aside: withAside
          ? Container(key: asideKey, color: const Color(0xFF223344))
          : null,
    );
    // An embedded pane: constrain the split to a bounded box narrower than the
    // window, so its own LayoutBuilder constraints (not the window) govern.
    if (paneWidth != null) {
      split = Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: paneWidth, height: 640, child: split),
      );
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: split)));
    await tester.pump();
  }

  testWidgets('wide pane shows all three panes with a usable detail',
      (tester) async {
    await pump(tester, window: const Size(1300, 900), withAside: true);
    expect(tester.takeException(), isNull);
    // List is capped (fixed 340 < 1300*0.42), aside is shown, and the detail
    // pane (Expanded) gets the generous remainder.
    expect(tester.getSize(find.byKey(listKey)).width, 340);
    expect(find.byKey(asideKey), findsOneWidget);
    expect(tester.getSize(find.byKey(detailKey)).width, greaterThan(360));
  });

  testWidgets(
      'narrow embedded pane drops the aside and keeps the detail >= min',
      (tester) async {
    // Window is desktop-class (so the aside is *eligible*), but the split is
    // embedded in a 700px pane — its own constraints, not the window, govern.
    await pump(tester,
        window: const Size(1400, 900), paneWidth: 700, withAside: true);
    expect(tester.takeException(), isNull);
    // Aside dropped because it would starve the detail...
    expect(find.byKey(asideKey), findsNothing);
    // ...list capped at 700 * 0.42, detail keeps at least the 360 minimum.
    expect(tester.getSize(find.byKey(listKey)).width, closeTo(294, 0.5));
    expect(tester.getSize(find.byKey(detailKey)).width,
        greaterThanOrEqualTo(360));
  });

  testWidgets('list never exceeds maxListWidthFraction of the pane',
      (tester) async {
    // 760px pane: 760 * 0.42 = 319.2, which is below the fixed 340 request, so
    // the fraction wins and the list is capped.
    await pump(tester, window: const Size(1400, 900), paneWidth: 760);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(listKey)).width, closeTo(319.2, 0.5));
  });

  testWidgets('phone width collapses to the detail pane only', (tester) async {
    await pump(tester, window: const Size(420, 900));
    expect(tester.takeException(), isNull);
    expect(find.byKey(detailKey), findsOneWidget);
    expect(find.byKey(listKey), findsNothing);
  });
}
