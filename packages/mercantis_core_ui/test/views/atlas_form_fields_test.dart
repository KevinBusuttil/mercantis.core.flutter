import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// On a form (not a dense child-table cell), link / date / select fields now
/// render as Atlas selector rows that open a picker on tap.
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
      id: 'Customer',
      name: 'Customer',
      module: 'CRM',
      permissions: [
        PermissionRule(role: 'System Manager', read: true, write: true, create: true),
      ],
      fields: [
        FieldDefinition(key: 'customer_name', label: 'Customer Name', type: FieldType.data),
      ],
    ));
    await registry.register(const DocType(
      id: 'Atlas Demo',
      name: 'Atlas Demo',
      module: 'Sales',
      permissions: [
        PermissionRule(role: 'System Manager', read: true, write: true, create: true),
      ],
      fields: [
        FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', required: true),
        FieldDefinition(key: 'order_date', label: 'Order Date', type: FieldType.date),
        FieldDefinition(key: 'priority', label: 'Priority', type: FieldType.select, options: 'Low\nHigh'),
      ],
    ));
    await database.db.insert('documents', {
      'id': 'CUST-1',
      'doctype': 'Customer',
      'company': null,
      'docstatus': 0,
      'payload': jsonEncode({'customer_name': 'ACME Corp'}),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'modified_at': DateTime.now().millisecondsSinceEpoch,
      'sync_version': null,
      'sync_state': 'local',
      'amended_from': null,
    });
  });

  tearDown(() async => database.close());

  Widget wrap() => ProviderScope(
        overrides: [
          mercantisDatabaseProvider.overrideWith((_) => Future.value(database)),
        ],
        child: const MaterialApp(
          home: GenericFormView(docTypeName: 'Atlas Demo', documentName: null),
        ),
      );

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
    }
  }

  testWidgets('link/date/select render as Atlas rows with selector placeholders',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await drain(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(AtlasFieldRow), findsWidgets);
    expect(find.text('Choose Customer'), findsOneWidget); // link
    expect(find.text('Choose Order Date'), findsOneWidget); // date
    expect(find.text('Select Priority'), findsOneWidget); // select
  });

  testWidgets('tapping a select row opens an option sheet and picks a value',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await drain(tester);

    await tester.tap(find.text('Select Priority'));
    await tester.pumpAndSettle();
    // Both options appear in the sheet.
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);

    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    // The chosen value replaces the placeholder on the row.
    expect(find.text('Select Priority'), findsNothing);
    expect(find.text('High'), findsOneWidget);
  });
}
