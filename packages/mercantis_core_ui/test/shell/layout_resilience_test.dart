import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Layout fixes found by rendering the shell at real sizes: the rail's brand,
/// figures on narrow cards, and the phone bar and card grids at large text.
const _workspaces = <WorkspaceDescriptor>[
  WorkspaceDescriptor(
      id: 'home', label: 'Today',
      icon: Icons.today_outlined, selectedIcon: Icons.today),
  WorkspaceDescriptor(
      id: 'finance', label: 'Money',
      icon: Icons.payments_outlined, selectedIcon: Icons.payments),
];

Widget _shell() => ProviderScope(
      overrides: [
        workspaceRegistryProvider.overrideWith(
            (_) => WorkspaceRegistry()..registerAll(_workspaces)),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/w/home',
          routes: [
            ShellRoute(
              builder: (c, s, child) => AdaptiveShell(
                  location: s.uri.toString(),
                  brandLabel: 'Neuradix Atlas',
                  child: child),
              routes: [
                GoRoute(
                    path: '/w/:id',
                    builder: (c, s) => Text('ws ${s.pathParameters['id']}')),
              ],
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('the rail carries the brand above search, not beside it',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell());
    await tester.pumpAndSettle();
    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    expect(find.descendant(of: rail, matching: find.text('Neuradix Atlas')),
        findsOneWidget);
    // Content starts right after the rail: no separate brand column.
    final railRight = tester.getTopRight(rail).dx;
    expect(tester.getTopLeft(find.text('ws home')).dx - railRight,
        lessThan(MercantisSpacing.xl * 2));
  });

  testWidgets('a KPI figure stays on one line on a narrow card',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SizedBox(
          width: 120,
          child: KpiCard(title: 'Cash position', value: '€10,213.60'),
        ),
      ),
    ));
    final text = tester.widget<Text>(find.text('€10,213.60'));
    expect(text.maxLines, 1);
    expect(find.ancestor(of: find.text('€10,213.60'), matching: find.byType(FittedBox)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom bar labels scale only a little at large text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AtlasBottomNavigation(
          selectedIndex: 0,
          onSelected: (_) {},
          destinations: const [
            AtlasNavDestination(
                icon: Icons.today_outlined,
                selectedIcon: Icons.today,
                label: 'Today'),
            AtlasNavDestination(
                icon: Icons.people_outline,
                selectedIcon: Icons.people,
                label: 'Customers'),
          ],
        ),
      ),
    ));
    final scaler = MediaQuery.textScalerOf(tester.element(find.text('Customers')));
    expect(scaler.scale(10), lessThanOrEqualTo(11));
  });

  testWidgets('card grids use fewer columns at large text', (tester) async {
    late int normal, large;
    await tester.pumpWidget(Builder(builder: (c) {
      normal = columnsForTextScale(c, 2);
      return const SizedBox();
    }));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Builder(builder: (c) {
        large = columnsForTextScale(c, 2);
        return const SizedBox();
      }),
    ));
    expect(normal, 2);
    expect(large, 1);
  });
}
