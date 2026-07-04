import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 4d-2: the master-detail selection is sourced from the route's
/// `?selected=` query parameter (tablet/desktop), so it survives refresh and is
/// deep-linkable — and a row tap syncs the selection back into the URL.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final registry = MetadataRegistry(database.db);
    await registry.register(const DocType(
      id: 'Widget',
      name: 'Widget',
      module: 'Catalog',
      permissions: [
        PermissionRule(
            role: 'System Manager', read: true, write: true, create: true),
      ],
      fields: [
        FieldDefinition(key: 'title', label: 'Title', type: FieldType.data),
      ],
    ));
    await _seed(database.db, 'DOC-1', 'Alpha');
    await _seed(database.db, 'DOC-2', 'Bravo');
  });

  tearDown(() async => database.close());

  Widget wrapRouter(GoRouter router) => ProviderScope(
        overrides: [
          mercantisDatabaseProvider.overrideWith((_) => Future.value(database)),
        ],
        child: MaterialApp.router(routerConfig: router),
      );

  GoRouter listRouter() => GoRouter(
        initialLocation: '/list/Widget',
        routes: [
          GoRoute(
            path: '/list/:docType',
            builder: (context, state) => MetadataListView(
              docTypeName: state.pathParameters['docType']!,
              selectedId: state.uri.queryParameters['selected'],
            ),
          ),
          GoRoute(
            path: '/form/:docType/:name',
            builder: (context, state) => const Scaffold(body: Text('FORM')),
          ),
        ],
      );

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  testWidgets('deep-linked ?selected= drives the detail pane', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = listRouter();
    await tester.pumpWidget(wrapRouter(router));
    // Land directly on a deep link selecting the second record.
    router.go('/list/Widget?selected=DOC-2');
    await drain(tester);

    final detail =
        tester.widget<GenericFormView>(find.byType(GenericFormView));
    expect(detail.documentName, 'DOC-2');
  });

  testWidgets('no ?selected= falls back to a default record (not empty)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = listRouter();
    await tester.pumpWidget(wrapRouter(router));
    await drain(tester);

    // Without a selection in the URL the detail pane still shows a record
    // (the first as the engine lists them), never an empty pane. The exact id
    // depends on the engine's list ordering, so assert on membership.
    final detail =
        tester.widget<GenericFormView>(find.byType(GenericFormView));
    expect(detail.documentName, isNotNull);
    expect(const ['DOC-1', 'DOC-2'], contains(detail.documentName));
  });

  testWidgets('tapping a row syncs the selection into the route',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = listRouter();
    await tester.pumpWidget(wrapRouter(router));
    await drain(tester);

    // Tap the second record's row (its title is rendered in the list pane).
    await tester.tap(find.text('Bravo').first);
    await drain(tester);

    expect(router.routeInformationProvider.value.uri.toString(),
        '/list/Widget?selected=DOC-2');
    final detail =
        tester.widget<GenericFormView>(find.byType(GenericFormView));
    expect(detail.documentName, 'DOC-2');
  });
}

Future<void> _seed(Database db, String id, String title) async {
  await db.insert('documents', {
    'id': id,
    'doctype': 'Widget',
    'company': null,
    'docstatus': 0,
    'payload': jsonEncode({'title': title}),
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'modified_at': DateTime.now().millisecondsSinceEpoch,
    'sync_version': null,
    'sync_state': 'local',
    'amended_from': null,
  });
}
