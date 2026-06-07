import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers [AppInstaller.syncMetadata]: an app whose bundled manifest gained
/// DocTypes after first install (e.g. child-table DocTypes) must pick them up
/// on the next boot, instead of being frozen at the first-install schema.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late MetadataRegistry registry;
  late AppInstaller installer;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    registry = MetadataRegistry(database.db);
    installer = AppInstaller(database: database.db, registry: registry);
  });

  tearDown(() => database.close());

  AppManifest manifest(List<DocType> docTypes) => AppManifest(
        id: 'app.test',
        version: '1.0.0',
        name: 'Test',
        docTypes: docTypes,
      );

  const alpha = DocType(id: 'Alpha', name: 'Alpha', fields: [
    FieldDefinition(key: 'x', label: 'X', type: FieldType.data),
  ]);
  const beta = DocType(id: 'Beta', name: 'Beta', fields: [
    FieldDefinition(key: 'y', label: 'Y', type: FieldType.data),
  ]);

  test('syncMetadata registers DocTypes added after first install', () async {
    await installer.install(manifest([alpha]));
    expect(await registry.get('Alpha'), isNotNull);
    expect(await registry.get('Beta'), isNull);

    // App later bundles a new DocType; boot calls syncMetadata.
    await installer.syncMetadata(manifest([alpha, beta]));
    expect(await registry.get('Beta'), isNotNull);
  });

  test('syncMetadata leaves the app installed without re-emitting install',
      () async {
    await installer.install(manifest([alpha]));
    expect(await installer.isInstalled('app.test'), isTrue);

    await installer.syncMetadata(manifest([alpha, beta]));
    expect(await installer.isInstalled('app.test'), isTrue);
  });
}
