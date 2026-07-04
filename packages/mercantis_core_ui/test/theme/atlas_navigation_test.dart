import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Phase 4c: the shell navigation primitives. AtlasBottomNavigation and
/// AtlasNavigationRail wrap Material's NavigationBar/NavigationRail and tint the
/// selection indicator with the active workspace's accent, so a module keeps
/// its colour as the layout shifts between phone bar and rail.
void main() {
  const destinations = [
    AtlasNavDestination(
        icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
    AtlasNavDestination(
        icon: Icons.sell_outlined, selectedIcon: Icons.sell, label: 'Sales'),
    AtlasNavDestination(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        label: 'Stock'),
  ];

  const accent = Color(0xFF7A5AF8);

  testWidgets('AtlasBottomNavigation tints the pill and reports taps',
      (tester) async {
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AtlasBottomNavigation(
          destinations: destinations,
          selectedIndex: 0,
          accentColor: accent,
          onSelected: (i) => tapped = i,
        ),
      ),
    ));

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
    expect(bar.indicatorColor, accent.withValues(alpha: 0.16));

    await tester.tap(find.text('Stock'));
    expect(tapped, 2);
  });

  testWidgets('AtlasNavigationRail tints the indicator and reports taps',
      (tester) async {
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            AtlasNavigationRail(
              destinations: destinations,
              selectedIndex: 1,
              accentColor: accent,
              onSelected: (i) => tapped = i,
            ),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    ));

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, 1);
    expect(rail.indicatorColor, accent.withValues(alpha: 0.14));
    expect(rail.selectedIconTheme?.color, accent);

    await tester.tap(find.text('Home'));
    expect(tapped, 0);
  });

  testWidgets('falls back to the theme primary when no accent is given',
      (tester) async {
    late ColorScheme scheme;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        scheme = Theme.of(context).colorScheme;
        return Scaffold(
          bottomNavigationBar: AtlasBottomNavigation(
            destinations: destinations,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        );
      }),
    ));
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.indicatorColor, scheme.primary.withValues(alpha: 0.16));
  });
}
