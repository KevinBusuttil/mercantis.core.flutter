import 'package:sqflite_common/sqflite.dart';
import 'migration_runner.dart';

class MercantisDatabase {
  final Database _db;

  MercantisDatabase._(this._db);

  static Future<MercantisDatabase> open({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async => MigrationRunner.migrate(db),
        onUpgrade: (db, oldVersion, newVersion) async =>
            MigrationRunner.migrate(db),
      ),
    );
    await MigrationRunner.migrate(db);
    return MercantisDatabase._(db);
  }

  Database get db => _db;

  Future<T> read<T>(Future<T> Function(Database db) fn) => fn(_db);

  Future<T> write<T>(Future<T> Function(Transaction txn) fn) =>
      _db.transaction(fn);

  Future<void> close() => _db.close();
}
