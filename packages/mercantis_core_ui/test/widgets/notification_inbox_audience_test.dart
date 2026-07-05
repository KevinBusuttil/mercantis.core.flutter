import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// NotificationInboxView.forCurrentUser and the audience providers show the
/// operator their global feed plus anything addressed to their id/email/roles.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final log = SqliteNotificationLog(database.db);
    await log.write(_entry(recipient: null, subject: 'Broadcast'));
    await log.write(_entry(recipient: 'alice', subject: 'Hi Alice'));
    await log.write(_entry(recipient: 'Manager', subject: 'For managers'));
    await log.write(_entry(recipient: 'bob', subject: 'Hi Bob'));
  });

  tearDown(() => database.close());

  List<Override> overrides(CurrentUser user) => [
        mercantisDatabaseProvider.overrideWith((_) => Future.value(database)),
        currentUserProvider.overrideWithValue(user),
      ];

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  testWidgets('forCurrentUser shows global + addressed to the operator',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides:
          overrides(const CurrentUser(id: 'alice', roles: {'Manager'})),
      child: const MaterialApp(
        home: Scaffold(body: NotificationInboxView.forCurrentUser()),
      ),
    ));
    await drain(tester);

    expect(find.text('Broadcast'), findsOneWidget); // global
    expect(find.text('Hi Alice'), findsOneWidget); // addressed by id
    expect(find.text('For managers'), findsOneWidget); // addressed by role
    expect(find.text('Hi Bob'), findsNothing); // someone else
  });

  test('notificationUnreadForCurrentUserProvider badges addressed-only',
      () async {
    final container = ProviderContainer(
        overrides:
            overrides(const CurrentUser(id: 'alice', roles: {'Manager'})));
    addTearDown(container.dispose);

    // The bell badge counts what "Mark all read" can clear: Hi Alice + For
    // managers = 2. The shared Broadcast is shown in the list but excluded
    // here — its read state is global, so it never contributes a badge an
    // operator can't clear.
    expect(
        await container.read(notificationUnreadForCurrentUserProvider.future),
        2);
  });
}

NotificationLogEntry _entry({String? recipient, required String subject}) =>
    NotificationLogEntry(
      appId: 'erp',
      docType: 'Sales Invoice',
      documentId: 'SINV-1',
      recipient: recipient,
      subject: subject,
      body: 'Body',
    );
