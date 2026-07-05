import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The shared "documents changed" seam: [metadataDocsProvider] re-fetches when
/// documentRevisionProvider(<docType>) is bumped, so a mutation elsewhere (a
/// form's delete/save) no longer leaves the list stale.
///
/// Driven through a [ProviderContainer] rather than a widget: the provider's
/// list runs sqflite queries, and those futures settle in the real async zone a
/// plain `test()` runs in — not the fake-async zone `testWidgets` installs,
/// where they hang.
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

  ProviderContainer containerForDb() {
    final container = ProviderContainer(overrides: [
      mercantisDatabaseProvider.overrideWith((_) => Future.value(database)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('bumping the revision re-fetches the list', () async {
    final container = containerForDb();
    const args = MetadataListArgs('Widget', null);

    // Initial fetch holds the seeded record only.
    final first = await container.read(metadataDocsProvider(args).future);
    expect(first.map((d) => d.payload['title']), ['Alpha']);

    // A record appears in the store (as a form's write would leave it)...
    await _seed(database.db, 'DOC-2', 'Bravo');

    // ...but the cached provider hasn't noticed — same list on a fresh read.
    final cached = await container.read(metadataDocsProvider(args).future);
    expect(cached.map((d) => d.payload['title']), ['Alpha']);

    // Bumping the shared seam invalidates the list, so it re-fetches and shows
    // the new record.
    container.read(documentRevisionProvider('Widget').notifier).bump();
    final refetched = await container.read(metadataDocsProvider(args).future);
    expect(
      refetched.map((d) => d.payload['title']).toSet(),
      {'Alpha', 'Bravo'},
    );
  });

  test('a bump for another DocType leaves this list cached', () async {
    final container = containerForDb();
    const args = MetadataListArgs('Widget', null);

    await container.read(metadataDocsProvider(args).future);
    await _seed(database.db, 'DOC-2', 'Bravo');

    // Bumping an unrelated DocType must not invalidate the Widget list.
    container.read(documentRevisionProvider('Gadget').notifier).bump();
    final still = await container.read(metadataDocsProvider(args).future);
    expect(still.map((d) => d.payload['title']), ['Alpha']);
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
