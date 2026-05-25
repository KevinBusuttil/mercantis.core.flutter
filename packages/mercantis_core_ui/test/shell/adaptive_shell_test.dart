import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const _testWorkspaces = <WorkspaceDescriptor>[
  WorkspaceDescriptor(
    id: 'home', label: 'Home',
    icon: Icons.home_outlined, selectedIcon: Icons.home,
  ),
  WorkspaceDescriptor(
    id: 'sales', label: 'Sales',
    icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale,
  ),
  WorkspaceDescriptor(
    id: 'inventory', label: 'Inventory',
    icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2,
  ),
];

Widget _harness({required Size size}) {
  return MediaQuery(
    data: MediaQueryData(size: size, devicePixelRatio: 1),
    child: ProviderScope(
      overrides: [
        workspaceRegistryProvider.overrideWith((_) {
          final r = WorkspaceRegistry();
          r.registerAll(_testWorkspaces);
          return r;
        }),
      ],
      child: MaterialApp.router(
        theme: MercantisTheme.light(),
        routerConfig: GoRouter(
          initialLocation: '/w/home',
          routes: [
            ShellRoute(
              builder: (context, state, child) => AdaptiveShell(
                location: state.matchedLocation,
                child: child,
              ),
              routes: [
                GoRoute(
                  path: '/w/:workspaceId',
                  builder: (c, s) => Center(
                    child: Text('content:${s.pathParameters['workspaceId']}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('AdaptiveShell', () {
    testWidgets('phone width renders NavigationBar', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(size: const Size(360, 720)));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('content:home'), findsOneWidget);
    });

    testWidgets('compact width renders compact NavigationRail',
        (tester) async {
      tester.view.physicalSize = const Size(720, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(size: const Size(720, 900)));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('medium width renders extended rail', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(size: const Size(1000, 800)));
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
    });

    testWidgets('expanded width renders persistent sidebar', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(size: const Size(1400, 900)));
      await tester.pumpAndSettle();

      // Sidebar shell uses a Row with a 248-wide Container holding tiles;
      // it does not use NavigationRail at this breakpoint.
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      // Workspace labels should all be visible in the sidebar.
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Inventory'), findsOneWidget);
    });
  });
}
