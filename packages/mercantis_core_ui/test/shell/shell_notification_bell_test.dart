import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The shell bell (AdaptiveShell.notificationsLocation): a notifications button
/// shown only when the host threads a location, and routing there on tap. The
/// badge *count* is covered deterministically by the provider test in
/// notification_inbox_audience_test.dart — here we only assert immediately
/// rendered structure (presence / absence / navigation), which doesn't hang on
/// a sqflite future settling in the fake-async test zone.
const _workspaces = <WorkspaceDescriptor>[
  WorkspaceDescriptor(
    id: 'home',
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
];

void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => database.close());

  Widget harness({String? notificationsLocation}) => MediaQuery(
        data: const MediaQueryData(size: Size(1400, 900), devicePixelRatio: 1),
        child: ProviderScope(
          overrides: [
            mercantisDatabaseProvider
                .overrideWith((_) => Future.value(database)),
            workspaceRegistryProvider.overrideWith((_) {
              final r = WorkspaceRegistry();
              r.registerAll(_workspaces);
              return r;
            }),
            currentUserProvider.overrideWithValue(
                const CurrentUser(id: 'local-user', roles: {'System Manager'})),
          ],
          child: MaterialApp.router(
            theme: MercantisTheme.light(),
            routerConfig: GoRouter(
              initialLocation: '/w/home',
              routes: [
                ShellRoute(
                  builder: (c, s, child) => AdaptiveShell(
                    location: s.matchedLocation,
                    notificationsLocation: notificationsLocation,
                    child: child,
                  ),
                  routes: [
                    GoRoute(
                        path: '/w/:id',
                        builder: (c, s) =>
                            const Center(child: Text('CONTENT'))),
                    GoRoute(
                        path: '/notifications',
                        builder: (c, s) =>
                            const Center(child: Text('NOTIF PAGE'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  testWidgets('no bell when the host omits a notifications location',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_outlined), findsNothing);
  });

  testWidgets('sidebar shows a bell that routes to notifications',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(notificationsLocation: '/notifications'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget); // sidebar footer label

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(find.text('NOTIF PAGE'), findsOneWidget);
  });

  testWidgets('the rail (medium width) also carries the bell', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(notificationsLocation: '/notifications'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });
}
