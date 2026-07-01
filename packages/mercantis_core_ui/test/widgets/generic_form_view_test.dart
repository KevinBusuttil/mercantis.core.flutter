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
        FieldDefinition(key: 'reference', label: 'Reference', type: FieldType.data),
        FieldDefinition(key: 'remarks', label: 'Remarks', type: FieldType.data),
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

    await tester.tap(find.text('Select Customer'));
    await _drain(tester);

    expect(find.text('Search Customer'), findsOneWidget);
    // The prefetched Customer DocType lets the picker resolve titles
    // from the registry's first string field — without it the picker
    // would still fall back to the candidate-key heuristic, but only
    // the registry path is robust to non-canonical title keys.
    expect(find.text('ACME Corp'), findsOneWidget);
    expect(find.text('Globex'), findsOneWidget);
  });

  testWidgets('link picker offers inline create and opens a create sheet',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const GenericFormView(
      docTypeName: 'Demo Order',
      documentName: null,
    )));
    await _drain(tester);

    await tester.tap(find.text('Select Customer'));
    await _drain(tester);
    expect(find.text('Search Customer'), findsOneWidget);

    // The footer surfaces a "New Customer" action (inline create).
    expect(find.text('New Customer'), findsOneWidget);
    await tester.tap(find.text('New Customer'));
    await _drain(tester);

    // The inline create sheet opens (its Create action) and renders an editable
    // field for the target DocType. The field's label is drawn via RichText, so
    // assert on the editor widget rather than label text.
    expect(find.text('Create Customer'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(Dialog), matching: find.byType(TextField)),
      findsWidgets,
    );
  });

  testWidgets(
      'form renders without overflow at desktop and phone widths '
      '(responsive two-column vs single-column)', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in const [Size(1400, 1000), Size(480, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(wrap(const GenericFormView(
        docTypeName: 'Demo Order',
        documentName: null,
      )));
      await _drain(tester);
      // A layout/overflow error would surface as a caught exception.
      expect(tester.takeException(), isNull,
          reason: 'layout error at $size');
      // Header (link placeholder) + child grid both render at every width.
      expect(find.text('Select Customer'), findsOneWidget);
      expect(find.text('Item Code'), findsOneWidget);
    }
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
