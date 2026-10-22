import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Host-shaped phone navigation: at most four task destinations plus "More",
/// with every other visible workspace still one tap away in the More sheet.
const _workspaces = <WorkspaceDescriptor>[
  WorkspaceDescriptor(
      id: 'home', label: 'Today',
      icon: Icons.today_outlined, selectedIcon: Icons.today),
  WorkspaceDescriptor(
      id: 'sales', label: 'Sales',
      subtitle: 'Quotes and invoices',
      icon: Icons.sell_outlined, selectedIcon: Icons.sell),
  WorkspaceDescriptor(
      id: 'finance', label: 'Money',
      icon: Icons.payments_outlined, selectedIcon: Icons.payments),
  WorkspaceDescriptor(
      id: 'buying', label: 'Buying',
      icon: Icons.shopping_basket_outlined,
      selectedIcon: Icons.shopping_basket),
  WorkspaceDescriptor(
      id: 'reports', label: 'Reports',
      icon: Icons.insights_outlined, selectedIcon: Icons.insights),
  WorkspaceDescriptor(
      id: 'setup', label: 'Settings',
      icon: Icons.settings_outlined, selectedIcon: Icons.settings),
];

const _destinations = <ShellDestination>[
  ShellDestination(
      id: 'today', label: 'Today', location: '/w/home',
      icon: Icons.today_outlined, selectedIcon: Icons.today),
  ShellDestination(
      id: 'customers', label: 'Customers', location: '/list/Customer',
      matchPrefixes: ['/form/Customer/'],
      icon: Icons.people_outline, selectedIcon: Icons.people),
  ShellDestination(
      id: 'invoices', label: 'Invoices', location: '/list/Sales Invoice',
      matchPrefixes: ['/form/Sales Invoice/'],
      icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long),
  ShellDestination(
      id: 'money', label: 'Money', location: '/w/finance',
      icon: Icons.payments_outlined, selectedIcon: Icons.payments),
  // A fifth host destination must not displace "More".
  ShellDestination(
      id: 'extra', label: 'Extra', location: '/w/reports',
      icon: Icons.star_outline, selectedIcon: Icons.star),
];

Widget _app({String initial = '/w/home', List<ShellDestination>? dests}) {
  return ProviderScope(
    overrides: [
      workspaceRegistryProvider.overrideWith((_) =>
          WorkspaceRegistry()..registerAll(_workspaces)),
      phoneDestinationsProvider.overrideWithValue(dests ?? _destinations),
    ],
    child: MaterialApp.router(
      theme: MercantisTheme.light(),
      routerConfig: GoRouter(
        initialLocation: initial,
        routes: [
          ShellRoute(
            builder: (c, s, child) =>
                AdaptiveShell(location: s.matchedLocation, child: child),
            routes: [
              GoRoute(
                path: '/w/:id',
                builder: (c, s) => Text('ws:${s.pathParameters['id']}'),
              ),
              GoRoute(
                path: '/list/:docType',
                builder: (c, s) => Text('list:${s.pathParameters['docType']}'),
              ),
              GoRoute(
                path: '/form/:docType/:id',
                builder: (c, s) => Text('form:${s.pathParameters['id']}'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

void _phone(WidgetTester tester, {double width = 360}) {
  tester.view.physicalSize = Size(width, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

int _selected(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  testWidgets('bar shows four host destinations plus More — never more',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(5));
    for (final label in ['Today', 'Customers', 'Invoices', 'Money', 'More']) {
      expect(
          find.descendant(
              of: find.byType(NavigationBar), matching: find.text(label)),
          findsOneWidget,
          reason: label);
    }
    expect(find.text('Extra'), findsNothing);
  });

  testWidgets('tapping a destination navigates to its location',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle();
    expect(find.text('list:Sales Invoice'), findsOneWidget);
    expect(_selected(tester), 2);
  });

  testWidgets('drilling into a record keeps its destination selected',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(initial: '/form/Customer/CUST-1'));
    await tester.pumpAndSettle();
    expect(_selected(tester), 1);
  });

  testWidgets('a location outside the bar selects More', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(initial: '/w/buying'));
    await tester.pumpAndSettle();
    expect(_selected(tester), 4);
  });

  testWidgets('More lists every other visible workspace and navigates',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    // Workspaces already on the bar (Today=/w/home, Money=/w/finance) are not
    // repeated; everything else is reachable.
    for (final label in ['Sales', 'Buying', 'Reports', 'Settings']) {
      expect(find.descendant(of: sheet, matching: find.text(label)),
          findsOneWidget,
          reason: label);
    }
    expect(find.descendant(of: sheet, matching: find.text('Money')),
        findsNothing);

    await tester.tap(find.descendant(of: sheet, matching: find.text('Buying')));
    await tester.pumpAndSettle();
    expect(find.text('ws:buying'), findsOneWidget);
  });

  testWidgets('no overflow at 320dp with 2x text', (tester) async {
    _phone(tester, width: 320);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 740), textScaler: TextScaler.linear(2)),
      child: _app(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('null destinations keep the legacy first-workspaces bar',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workspaceRegistryProvider.overrideWith((_) =>
            WorkspaceRegistry()..registerAll(_workspaces)),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/w/home', routes: [
          ShellRoute(
            builder: (c, s, child) =>
                AdaptiveShell(location: s.matchedLocation, child: child),
            routes: [
              GoRoute(path: '/w/:id', builder: (c, s) => const SizedBox()),
            ],
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(5)); // 4 workspaces + More
    expect(find.text('Sales'), findsOneWidget);
  });

  test('matches respects path boundaries', () {
    const d = ShellDestination(
        id: 'c', label: 'C', location: '/list/Customer',
        matchPrefixes: ['/form/Customer/'],
        icon: Icons.abc, selectedIcon: Icons.abc);
    expect(d.matches('/list/Customer'), isTrue);
    expect(d.matches('/list/Customer?selected=X'), isTrue);
    expect(d.matches('/form/Customer/X'), isTrue);
    expect(d.matches('/list/Customer Group'), isFalse);
    expect(d.matches('/form/Customer Group/X'), isFalse);
  });
}
