import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The shared "documents changed" seam: MetadataListView's cached doc list
/// re-fetches when documentRevisionProvider(<docType>) is bumped, so a mutation
/// elsewhere (a form's delete/save) no longer leaves the list stale.
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
  });

  tearDown(() async => database.close());

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  testWidgets('bumping the revision re-fetches the list', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      mercantisDatabaseProvider.overrideWith((_) => Future.value(database)),
    ]);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/list/Widget',
      routes: [
        GoRoute(
          path: '/list/:docType',
          builder: (c, s) =>
              MetadataListView(docTypeName: s.pathParameters['docType']!),
        ),
        GoRoute(
          path: '/form/:docType/:name',
          builder: (c, s) => const Scaffold(body: Text('FORM')),
        ),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await drain(tester);

    // Initial list holds the seeded record only.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsNothing);

    // A record appears in the store (as a form's write would leave it)...
    await _seed(database.db, 'DOC-2', 'Bravo');
    await drain(tester);
    // ...but the cached list hasn't noticed yet.
    expect(find.text('Bravo'), findsNothing);

    // Bumping the shared seam makes the list re-fetch and show it.
    container.read(documentRevisionProvider('Widget').notifier).bump();
    await drain(tester);
    expect(find.text('Bravo'), findsOneWidget);
  });

  test('the revision counter is independent per DocType', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(documentRevisionProvider('A')), 0);
    container.read(documentRevisionProvider('A').notifier).bump();
    expect(container.read(documentRevisionProvider('A')), 1);
    // A different DocType is untouched.
    expect(container.read(documentRevisionProvider('B')), 0);
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
