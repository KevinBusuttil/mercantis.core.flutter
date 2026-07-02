import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A link field must read as the target's *name*, not its raw stored id.
/// Master data ids are opaque UUIDs (no naming series), so before this fix a
/// selected Customer showed e.g. `8d34dd51-…` instead of "ACME Corp".
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  const custId = '8d34dd51-2984-4510-a842-804b689305d8';

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
        FieldDefinition(
            key: 'customer_name', label: 'Customer Name', type: FieldType.data),
      ],
    ));
    await database.db.insert('documents', {
      'id': custId,
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

  Widget wrap(Widget child) => ProviderScope(
        overrides: [
          mercantisDatabaseProvider.overrideWith((_) => Future.value(database)),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('resolves a selected link to the record name, not its id',
      (tester) async {
    await tester.pumpWidget(wrap(LinkPickerField(
      label: 'Customer',
      targetDocType: 'Customer',
      value: custId,
      required: true,
      readOnly: false,
      onChanged: (_) {},
    )));
    await drain(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('ACME Corp'), findsOneWidget);
    expect(find.text(custId), findsNothing);
  });

  testWidgets('falls back to the raw id when the target record is missing',
      (tester) async {
    await tester.pumpWidget(wrap(LinkPickerField(
      label: 'Customer',
      targetDocType: 'Customer',
      value: 'GHOST-1',
      required: false,
      readOnly: false,
      onChanged: (_) {},
    )));
    await drain(tester);
    expect(tester.takeException(), isNull);
    // Unresolvable → the id stays visible rather than showing nothing.
    expect(find.text('GHOST-1'), findsOneWidget);
  });
}
