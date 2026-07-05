import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The hub list route (MetadataListView) now offers the List/Tree toggle for
/// hierarchical (isTree) DocTypes — reusing RecordTreeView, previously wired
/// only into the studio's GenericListView / RecordCollectionView.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final registry = MetadataRegistry(database.db);
    // A hierarchical DocType (chart-of-accounts shape).
    await registry.register(const DocType(
      id: 'Account',
      name: 'Account',
      module: 'Ledger',
      isTree: true,
      parentField: 'parent_account',
      permissions: [
        PermissionRule(
            role: 'System Manager', read: true, write: true, create: true),
      ],
      fields: [
        FieldDefinition(
            key: 'account_name', label: 'Name', type: FieldType.data),
        FieldDefinition(
            key: 'parent_account',
            label: 'Parent',
            type: FieldType.link,
            linkDocType: 'Account'),
      ],
    ));
    // A flat DocType (no hierarchy → no toggle).
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

    await _seed(database.db, 'A-1', 'Account', {'account_name': 'Assets'});
    await _seed(database.db, 'A-2', 'Account',
        {'account_name': 'Cash', 'parent_account': 'A-1'});
    await _seed(database.db, 'W-1', 'Widget', {'title': 'Gadget'});
  });

  tearDown(() async => database.close());

  Widget wrap(GoRouter router) => ProviderScope(
        overrides: [
          mercantisDatabaseProvider.overrideWith((_) => Future.value(database)),
        ],
        child: MaterialApp.router(routerConfig: router),
      );

  GoRouter routerFor(String docType) => GoRouter(
        initialLocation: '/list/$docType',
        routes: [
          GoRoute(
            path: '/list/:docType',
            builder: (context, state) =>
                MetadataListView(docTypeName: state.pathParameters['docType']!),
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

  testWidgets('tree DocType: toggle switches the list pane to a tree',
      (tester) async {
    tester.view.physicalSize = const Size(380, 820); // phone → single column
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(routerFor('Account')));
    await drain(tester);

    // Defaults to the list pane, with the List/Tree toggle offered.
    expect(find.byType(DocumentListPane), findsOneWidget);
    expect(find.byType(RecordTreeView), findsNothing);
    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);

    // Switching to Tree replaces the pane with the hierarchy view.
    await tester.tap(find.text('Tree'));
    await drain(tester);

    expect(find.byType(RecordTreeView), findsOneWidget);
    expect(find.byType(DocumentListPane), findsNothing);
    expect(find.text('Assets'), findsOneWidget); // root account row
  });

  testWidgets('flat DocType: no tree toggle', (tester) async {
    tester.view.physicalSize = const Size(380, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(routerFor('Widget')));
    await drain(tester);

    expect(find.byType(DocumentListPane), findsOneWidget);
    expect(find.text('Tree'), findsNothing);
    expect(find.byType(RecordTreeView), findsNothing);
  });
}

Future<void> _seed(
    Database db, String id, String docType, Map<String, dynamic> payload) async {
  await db.insert('documents', {
    'id': id,
    'doctype': docType,
    'company': null,
    'docstatus': 0,
    'payload': jsonEncode(payload),
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'modified_at': DateTime.now().millisecondsSinceEpoch,
    'sync_version': null,
    'sync_state': 'local',
    'amended_from': null,
  });
}
