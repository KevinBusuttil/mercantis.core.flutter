import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// CU3: the Data Browser screen — schema sidebar + read-only query runner.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;

  setUp(() async {
    // DataBrowserView persists saved queries via shared_preferences; register
    // the in-memory mock so its initState load doesn't throw MissingPlugin.
    SharedPreferences.setMockInitialValues({});
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await database.db.insert('documents', {
      'id': 'DOC-1',
      'doctype': 'Demo',
      'company': null,
      'docstatus': 0,
      'payload': '{}',
      'created_at': 0,
      'modified_at': 0,
      'sync_version': null,
      'sync_state': 'local',
      'amended_from': null,
    });
  });

  tearDown(() => database.close());

  Widget wrap(Widget child) => ProviderScope(
        overrides: [
          mercantisDatabaseProvider.overrideWith((_) => Future.value(database)),
        ],
        child: MaterialApp(home: child),
      );

  testWidgets('lists schema tables and runs a query', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const DataBrowserView()));
    await _drain(tester);

    // The schema sidebar lists the migrated `documents` table.
    expect(find.text('documents'), findsWidgets);

    // Running the default query (table list) succeeds and reports a row count.
    await tester.tap(find.text('Run'));
    await _drain(tester);
    expect(find.textContaining('row'), findsWidgets);
    // No error surfaced.
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('a write statement surfaces a read-only error', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const DataBrowserView()));
    await _drain(tester);

    await tester.enterText(
        find.byType(TextField).first, 'DELETE FROM documents');
    await tester.tap(find.text('Run'));
    await _drain(tester);

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
  });
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }
}
