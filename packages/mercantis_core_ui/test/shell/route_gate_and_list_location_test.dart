import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The workspace route gate lets a host replace a workspace or custom route
/// (e.g. "this optional feature is off") without the route 404ing; list
/// locations carry a workspace item's relabel and pre-filter.
void main() {
  group('listLocation', () {
    test('plain list stays a plain path', () {
      expect(listLocation('Customer'), '/list/Customer');
    });

    test('title and filter travel as query parameters', () {
      final loc = listLocation('Payment Entry',
          title: 'Customer payments', filter: {'payment_type': 'Receive'});
      expect(loc.split('?').first, '/list/Payment Entry');
      final uri = Uri.parse(Uri.encodeFull(loc));
      expect(uri.queryParameters['title'], 'Customer payments');
      expect(uri.queryParameters['f.payment_type'], 'Receive');
    });

    test('a DocType item carries its label and filter', () {
      const item = DocTypeWorkspaceItem(
        docType: 'Expense',
        label: 'Billable expenses',
        listFilter: {'billable': 1},
      );
      final uri = Uri.parse(docTypeItemLocation(item));
      expect(uri.queryParameters['title'], 'Billable expenses');
      expect(uri.queryParameters['f.billable'], '1');
    });

    test('numeric filter text compares as a number', () {
      expect(listFilterValue('1'), 1);
      expect(listFilterValue('Receive'), 'Receive');
    });
  });

  group('workspace route gate', () {
    Widget app(String initial, {WorkspaceRouteGate? gate}) {
      final registry = WorkspaceRegistry()
        ..registerAll(const [
          WorkspaceDescriptor(
              id: 'home', label: 'Home',
              icon: Icons.home_outlined, selectedIcon: Icons.home),
        ])
        ..registerRoute('rentals', (c, s) => const Text('rentals screen'))
        ..registerRoute('till', (c, s) => const Text('till screen'));
      return ProviderScope(
        overrides: [
          workspaceRegistryProvider.overrideWithValue(registry),
          workspaceRouteGateProvider.overrideWithValue(gate),
        ],
        child: Consumer(builder: (context, ref, _) {
          return MaterialApp.router(
            routerConfig: ref
                .watch(appNavigationRegistryProvider)
                .buildRouter(initialLocation: initial),
          );
        }),
      );
    }

    Widget offGate(BuildContext context,
        {required String workspaceId,
        required String? routeName,
        required WidgetBuilder child}) {
      if (routeName == 'rentals' || workspaceId == 'property') {
        return Text('off:$workspaceId/${routeName ?? ''}');
      }
      return child(context);
    }

    testWidgets('no gate renders the route as before', (tester) async {
      await tester.pumpWidget(app('/w/home/rentals'));
      await tester.pumpAndSettle();
      expect(find.text('rentals screen'), findsOneWidget);
    });

    testWidgets('gate replaces a blocked custom route', (tester) async {
      await tester.pumpWidget(app('/w/home/rentals', gate: offGate));
      await tester.pumpAndSettle();
      expect(find.text('off:home/rentals'), findsOneWidget);
      expect(find.text('rentals screen'), findsNothing);
    });

    testWidgets('gate passes an allowed route through', (tester) async {
      await tester.pumpWidget(app('/w/home/till', gate: offGate));
      await tester.pumpAndSettle();
      expect(find.text('till screen'), findsOneWidget);
    });

    testWidgets('gate sees unregistered (hidden) workspace ids',
        (tester) async {
      await tester.pumpWidget(app('/w/property', gate: offGate));
      await tester.pumpAndSettle();
      expect(find.text('off:property/'), findsOneWidget);
    });
  });

  test('replaceWorkspaces swaps descriptors and keeps routes', () {
    final r = WorkspaceRegistry()
      ..registerAll(const [
        WorkspaceDescriptor(
            id: 'a', label: 'A', icon: Icons.abc, selectedIcon: Icons.abc),
      ])
      ..registerRoute('x', (c, s) => const SizedBox());
    r.replaceWorkspaces(const [
      WorkspaceDescriptor(
          id: 'b', label: 'B', icon: Icons.abc, selectedIcon: Icons.abc),
    ]);
    expect(r.all.map((w) => w.id), ['b']);
    expect(r.routeFor('x'), isNotNull);
  });
}
