import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression coverage for the two issues introduced by Phase 1/2:
///   * Child-table fields rendered the "wire childDocTypeProvider"
///     fallback instead of the grid header.
///   * Link picker fell back to an empty result list because the form
///     never resolved the link target's DocType.
///
/// The fix moved both lookups into [GenericFormView] itself, defaulting
/// to a prefetch from `metadataRegistryProvider`. These tests pin that
/// behaviour without forcing callers to wire any overrides.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

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
        PermissionRule(
          role: 'System Manager',
          read: true,
          write: true,
          create: true,
        ),
      ],
      fields: [
        FieldDefinition(
          key: 'customer_name',
          label: 'Customer Name',
          type: FieldType.data,
        ),
      ],
    ));
    await registry.register(const DocType(
      id: 'Demo Item',
      name: 'Demo Item',
      module: 'Catalog',
      permissions: [
        PermissionRule(
          role: 'System Manager',
          read: true,
          write: true,
          create: true,
        ),
      ],
      fields: [
        FieldDefinition(
          key: 'item_code',
          label: 'Item Code',
          type: FieldType.data,
        ),
        FieldDefinition(
          key: 'qty',
          label: 'Qty',
          type: FieldType.integer,
        ),
      ],
    ));
    await registry.register(const DocType(
      id: 'Demo Order',
      name: 'Demo Order',
      module: 'Sales',
      permissions: [
        PermissionRule(
          role: 'System Manager',
          read: true,
          write: true,
          create: true,
        ),
      ],
      fields: [
        FieldDefinition(
          key: 'customer',
          label: 'Customer',
          type: FieldType.link,
          linkDocType: 'Customer',
        ),
        FieldDefinition(
          key: 'items',
          label: 'Items',
          type: FieldType.table,
          tableDocType: 'Demo Item',
        ),
      ],
    ));

    await _seedCustomer(database.db, 'CUST-0001', 'ACME Corp');
    await _seedCustomer(database.db, 'CUST-0002', 'Globex');
  });

  tearDown(() async {
    await database.close();
  });

  Widget wrap(Widget child) => ProviderScope(
        overrides: [
          mercantisDatabaseProvider.overrideWith((_) => Future.value(database)),
        ],
        child: MaterialApp(home: child),
      );

  testWidgets(
      'child-table renders header (not the "wire childDocTypeProvider" warning) '
      'without an explicit override', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const GenericFormView(
      docTypeName: 'Demo Order',
      documentName: null,
    )));
    await _drain(tester);

    expect(
      find.textContaining('Wire `childDocTypeProvider`'),
      findsNothing,
      reason: 'fallback warning means the registry-backed resolver failed',
    );
    expect(find.text('Item Code'), findsOneWidget);
    expect(find.text('Qty'), findsOneWidget);
  });

  testWidgets('child-table renders existing rows from document_children',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Line item lives in the document_children table (Document.children),
    // not the parent payload. Before the fix the form read payload['items']
    // and showed an empty grid.
    await _seedOrderWithItem(database.db);

    await tester.pumpWidget(wrap(const GenericFormView(
      docTypeName: 'Demo Order',
      documentName: 'ORD-0001',
    )));
    await _drain(tester);

    expect(find.text('WIDGET-1'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('link picker fallback lists seeded records by their title',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const GenericFormView(
      docTypeName: 'Demo Order',
      documentName: null,
    )));
    await _drain(tester);

    await tester.tap(find.text('Link to Customer'));
    await _drain(tester);

    expect(find.text('Select Customer'), findsOneWidget);
    // The prefetched Customer DocType lets the picker resolve titles
    // from the registry's first string field — without it the picker
    // would still fall back to the candidate-key heuristic, but only
    // the registry path is robust to non-canonical title keys.
    expect(find.text('ACME Corp'), findsOneWidget);
    expect(find.text('Globex'), findsOneWidget);
  });
}

/// `WidgetTester.pumpAndSettle` never settles here — the form's many
/// `TextField`s keep cursor-blink animations alive forever. `pump` alone
/// also misses sqflite_ffi's work, which runs outside the fake test
/// clock; [runAsync] hands control back to the real scheduler so async
/// DB calls can complete.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }
}

Future<void> _seedOrderWithItem(Database db) async {
  await db.insert('documents', {
    'id': 'ORD-0001',
    'doctype': 'Demo Order',
    'company': null,
    'docstatus': 0,
    'payload': jsonEncode({'customer': 'CUST-0001'}),
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'modified_at': DateTime.now().millisecondsSinceEpoch,
    'sync_version': null,
    'sync_state': 'local',
    'amended_from': null,
  });
  await db.insert('document_children', {
    'id': 'ORD-0001-row0',
    'parent_id': 'ORD-0001',
    'parent_doctype': 'Demo Order',
    'table_name': 'items',
    'row_index': 0,
    'payload': jsonEncode({'item_code': 'WIDGET-1', 'qty': 5}),
  });
}

Future<void> _seedCustomer(Database db, String id, String name) async {
  await db.insert('documents', {
    'id': id,
    'doctype': 'Customer',
    'company': null,
    'docstatus': 0,
    'payload': jsonEncode({'customer_name': name}),
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'modified_at': DateTime.now().millisecondsSinceEpoch,
    'sync_version': null,
    'sync_state': 'local',
    'amended_from': null,
  });
}
