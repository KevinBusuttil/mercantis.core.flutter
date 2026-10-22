import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/ledger_fixture.dart';

/// Schema upgrades (M1.5 "upgrade with pending local work", "unsupported
/// upgrade"): an old database upgrades in place without losing rows, a
/// database half-migrated by an older non-transactional build heals, and a
/// database from a NEWER build is refused untouched.
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mc_migrate_');
    path = p.join(dir.path, 'm.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Builds a database as schema v1 left it, holding real work: a saved
  /// invoice and a pending sync mutation.
  Future<void> makeV1Database({bool halfAppliedV2 = false}) async {
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: path);
    final engine = await buildTestEngine(db);
    await engine.save(invoice('LEGACY-1', lineCount: 4), testRoles);
    // Roll the schema back to v1: drop what v3..v8 added, and v2's column
    // unless we are simulating a crash that applied it without recording it.
    for (final t in const [
      'naming_block_allocations',
      'naming_counter_blocks',
      'notification_log',
      'attachments',
      'posting_batches',
      'notification_broadcast_receipt',
      'sync_conflicts',
    ]) {
      await db.db.execute('DROP TABLE IF EXISTS $t');
    }
    if (!halfAppliedV2) {
      await db.db.execute('ALTER TABLE custom_fields DROP COLUMN insert_after');
    }
    await db.db.update('schema_version', {'version': 1});
    await db.close();
  }

  test('v1 database upgrades to the latest schema with its data intact',
      () async {
    await makeV1Database();
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: path);
    expect(await MigrationRunner.schemaVersion(db.db),
        MigrationRunner.latestVersion);
    final engine = await buildTestEngine(db);
    final doc = await engine.fetch('Inv', 'LEGACY-1');
    expect(doc!.children['lines'], hasLength(4));
    final pending = await db.db
        .query('sync_queue', where: 'document_id = ?', whereArgs: ['LEGACY-1']);
    expect(pending, isNotEmpty, reason: 'pending local work survives');
    // The upgraded schema is usable: submit writes the new tables.
    await engine.submit(doc, testRoles);
    expect(await db.quickCheck(), isTrue);
    await db.close();
  });

  test('a v2 step half-applied by an older build heals on open', () async {
    await makeV1Database(halfAppliedV2: true);
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: path);
    expect(await MigrationRunner.schemaVersion(db.db),
        MigrationRunner.latestVersion);
    await db.close();
  });

  test('reopening at the latest version is a no-op', () async {
    for (var i = 0; i < 3; i++) {
      final db = await MercantisDatabase.open(
          factory: databaseFactoryFfi, path: path);
      final rows = await db.db.query('schema_version');
      expect(rows, hasLength(1));
      expect(rows.single['version'], MigrationRunner.latestVersion);
      await db.close();
    }
  });

  test('a database from a newer build is refused and left untouched',
      () async {
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: path);
    await db.db.update('schema_version', {'version': 99});
    await db.close();
    final before = File(path).readAsBytesSync();

    await expectLater(
        MercantisDatabase.open(factory: databaseFactoryFfi, path: path),
        throwsA(isA<UnsupportedSchemaVersionException>()
            .having((e) => e.found, 'found', 99)));
    expect(File(path).readAsBytesSync(), before);
  });
}
