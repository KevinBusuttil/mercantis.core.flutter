import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// R7: a full disk must never show SQLite's text (or the SQL and values it
/// echoes) to the operator.
void main() {
  setUpAll(sqfliteFfiInit);

  test('a real SQLITE_FULL from a capped database gets plain words', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE t (v TEXT)');
    await db.execute('PRAGMA max_page_count = 2');
    Object? error;
    try {
      for (var i = 0; i < 200; i++) {
        await db.insert('t', {'v': 'Blue Fig Ltd invoice ${'x' * 500}'});
      }
    } catch (e) {
      error = e;
    }
    await db.close();
    expect(error, isA<DatabaseException>());
    final text = operatorErrorText(error!);
    expect(text, contains('out of storage space'));
    expect(text, isNot(contains('SQLITE')));
    expect(text, isNot(contains('Blue Fig')));
    expect(text, isNot(contains('INSERT')));
  });

  test('a full file system is described the same way', () {
    expect(
        storageErrorText(const FileSystemException(
            'write failed', '/x', OSError('No space left on device', 28))),
        contains('out of storage space'));
  });

  test('engine errors keep their own explanation; others pass through', () {
    expect(operatorErrorText(const DocumentEngineError.malformedRow('A')),
        isNot(contains('DocumentEngineError')));
    expect(storageErrorText(StateError('x')), isNull);
    expect(operatorErrorText(StateError('x')), contains('x'));
  });

  test('no storage message promises that nothing was saved', () {
    // Review fix: a caller can fail part-way through a multi-step action,
    // so the operator is told to check, never that nothing was stored.
    final errors = <Object>[
      const FileSystemException(
          'write failed', '/x', OSError('No space left on device', 28)),
      const FileSystemException(
          'open failed', '/x', OSError('Read-only file system', 30)),
      const FileSystemException('write failed', '/x', OSError('Other', 5)),
    ];
    for (final error in errors) {
      final text = storageErrorText(error)!;
      expect(text.toLowerCase(), isNot(contains('nothing was saved')));
      expect(text.toLowerCase(), contains('check'));
    }
  });
}
