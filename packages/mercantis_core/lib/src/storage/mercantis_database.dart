import 'package:sqflite_common/sqflite.dart';
import 'migration_runner.dart';

class MercantisDatabase {
  final Database _db;

  MercantisDatabase._(this._db);

  static Future<MercantisDatabase> open({
    required DatabaseFactory factory,
    required String path,
  }) async {
    // `version: 1` keeps SQLite's user_version as older builds left it. The
    // real schema version lives in `schema_version`, and the migration runner
    // applies each step in its own transaction (sqflite's onCreate/onUpgrade
    // already run inside one, which cannot nest).
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1),
    );
    try {
      await MigrationRunner.migrate(db);
    } catch (_) {
      await db.close();
      rethrow;
    }
    return MercantisDatabase._(db);
  }

  /// SQLite's `PRAGMA quick_check`: true when the file's structure is sound.
  Future<bool> quickCheck() async {
    final rows = await _db.rawQuery('PRAGMA quick_check');
    return rows.length == 1 && rows.first.values.first == 'ok';
  }

  Database get db => _db;

  Future<T> read<T>(Future<T> Function(Database db) fn) => fn(_db);

  Future<T> write<T>(Future<T> Function(Transaction txn) fn) =>
      _db.transaction(fn);

  Future<void> close() => _db.close();
}
