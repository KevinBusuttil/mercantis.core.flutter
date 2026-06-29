import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// C6: the guarded, read-only SQL runner behind the Data Browser.
void main() {
  setUpAll(sqfliteFfiInit);

  group('ReadOnlyQueryGuard', () {
    test('accepts read-only leading keywords (any case, trailing ;)', () {
      const ok = [
        'SELECT 1',
        'select * from documents',
        'WITH x AS (SELECT 1) SELECT * FROM x',
        'EXPLAIN SELECT 1',
        'pragma table_info("documents")',
        'SELECT 1;',
        '  SELECT 1  ;  ',
      ];
      for (final sql in ok) {
        expect(() => ReadOnlyQueryGuard.validate(sql), returnsNormally,
            reason: sql);
      }
    });

    test('rejects empty, multi-statement, and writes', () {
      const bad = [
        '',
        '   ',
        'DELETE FROM documents',
        'UPDATE documents SET id = 1',
        'INSERT INTO documents (id) VALUES (1)',
        'DROP TABLE documents',
        'SELECT 1; SELECT 2',
      ];
      for (final sql in bad) {
        expect(() => ReadOnlyQueryGuard.validate(sql),
            throwsA(isA<ReadOnlyQueryException>()),
            reason: sql);
      }
    });
  });

  group('runReadOnlyQuery', () {
    late MercantisDatabase database;

    setUp(() async {
      database = await MercantisDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      for (final id in ['A-1', 'A-2', 'A-3']) {
        await database.db.insert('documents', {
          'id': id,
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
      }
    });

    tearDown(() => database.close());

    test('returns ordered columns and rendered rows', () async {
      final r = await database
          .runReadOnlyQuery('SELECT id, doctype FROM documents ORDER BY id');
      expect(r.columns, ['id', 'doctype']);
      expect(r.rows.map((row) => row.first).toList(), ['A-1', 'A-2', 'A-3']);
      expect(r.rows.first, ['A-1', 'Demo']);
      expect(r.truncated, isFalse);
    });

    test('rowLimit caps rows and flags truncation', () async {
      final r = await database
          .runReadOnlyQuery('SELECT id FROM documents ORDER BY id', rowLimit: 2);
      expect(r.rows.length, 2);
      expect(r.truncated, isTrue);
    });

    test('PRAGMA table_info is permitted and returns column metadata', () async {
      final r = await database.runReadOnlyQuery('PRAGMA table_info("documents")');
      expect(r.columns, contains('name'));
      expect(r.rows.any((row) => row.contains('id')), isTrue);
    });

    test('write statements are rejected before touching the database', () async {
      await expectLater(
        database.runReadOnlyQuery('DELETE FROM documents'),
        throwsA(isA<ReadOnlyQueryException>()),
      );
      // The guard ran before any execution — data is intact.
      final r = await database.runReadOnlyQuery('SELECT COUNT(*) AS n FROM documents');
      expect(r.rows.first.first, '3');
    });
  });
}
