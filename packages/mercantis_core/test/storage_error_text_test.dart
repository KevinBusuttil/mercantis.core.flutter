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
}
