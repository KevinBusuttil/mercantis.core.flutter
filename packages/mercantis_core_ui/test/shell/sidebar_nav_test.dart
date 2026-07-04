import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

// Workspaces with nested sections/items, to exercise the HU5 sidebar
// multi-expand + filter behaviour.
const _workspaces = <WorkspaceDescriptor>[
  WorkspaceDescriptor(
    id: 'sales',
    label: 'Sales',
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale,
    sections: [
      WorkspaceSection(
        label: 'Orders',
        items: [
          DocTypeWorkspaceItem(docType: 'Sales Order', label: 'Sales Orders'),
          DocTypeWorkspaceItem(docType: 'Quotation', label: 'Quotations'),
        ],
      ),
    ],
  ),
  WorkspaceDescriptor(
    id: 'inventory',
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    sections: [
      WorkspaceSection(
        label: 'Stock',
        items: [DocTypeWorkspaceItem(docType: 'Item', label: 'Items')],
      ),
    ],
  ),
];

Widget _harness(Size size) {
  return MediaQuery(
    data: MediaQueryData(size: size, devicePixelRatio: 1),
    child: ProviderScope(
      overrides: [
        workspaceRegistryProvider.overrideWith((_) {
          final r = WorkspaceRegistry();
          r.registerAll(_workspaces);
          return r;
        }),
      ],
      child: MaterialApp.router(
        theme: MercantisTheme.light(),
        routerConfig: GoRouter(
          initialLocation: '/w/sales',
          routes: [
            ShellRoute(
              builder: (context, state, child) =>
                  AdaptiveShell(location: state.matchedLocation, child: child),
              routes: [
                GoRoute(
                  path: '/w/:workspaceId',
                  builder: (c, s) =>
                      Center(child: Text('ws:${s.pathParameters['workspaceId']}')),
                ),
                GoRoute(
                  path: '/list/:docType',
                  builder: (c, s) =>
                      Center(child: Text('list:${s.pathParameters['docType']}')),
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
  const expanded = Size(1400, 900);

  group('HU5 sidebar', () {
    testWidgets('workspace sections are collapsed until expanded',
        (tester) async {
      tester.view.physicalSize = expanded;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(expanded));
      await tester.pumpAndSettle();

      // Both workspace headers show; their items do not (collapsed).
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Inventory'), findsOneWidget);
      expect(find.text('Sales Orders'), findsNothing);
      expect(find.text('Quotations'), findsNothing);

      // Expand the first workspace (Sales).
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();

      expect(find.text('Sales Orders'), findsOneWidget);
      expect(find.text('Quotations'), findsOneWidget);
      // Multi-expand: expanding Sales must not reveal Inventory's items.
      expect(find.text('Items'), findsNothing);
    });

    testWidgets('filter narrows to matching item and auto-expands',
        (tester) async {
      tester.view.physicalSize = expanded;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(expanded));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'quot');
      await tester.pumpAndSettle();

      // Only the workspace with a matching item survives, auto-expanded, and
      // only the matching item is shown.
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Quotations'), findsOneWidget);
      expect(find.text('Sales Orders'), findsNothing);
      expect(find.text('Inventory'), findsNothing);
      expect(find.text('Items'), findsNothing);
    });

    testWidgets('workspace-label match reveals all of its items',
        (tester) async {
      tester.view.physicalSize = expanded;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(expanded));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'invent');
      await tester.pumpAndSettle();

      expect(find.text('Inventory'), findsOneWidget);
      expect(find.text('Items'), findsOneWidget);
      expect(find.text('Sales'), findsNothing);
    });

    testWidgets('no matches shows an empty message', (tester) async {
      tester.view.physicalSize = expanded;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(expanded));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz-nothing');
      await tester.pumpAndSettle();

      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('Sales'), findsNothing);
      expect(find.text('Inventory'), findsNothing);
    });

    testWidgets('tapping an expanded item navigates to its list route',
        (tester) async {
      tester.view.physicalSize = expanded;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(expanded));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quotations'));
      await tester.pumpAndSettle();

      expect(find.text('list:Quotation'), findsOneWidget);
    });
  });
}
