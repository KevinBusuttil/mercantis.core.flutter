import 'dart:io';

import 'package:sqflite_common/sqflite.dart';

/// Row and object counts copied by [DatabaseSnapshot.write].
class SnapshotStats {
  const SnapshotStats({required this.rowsByTable, required this.userVersion});

  /// Rows copied per table, in copy order.
  final Map<String, int> rowsByTable;

  /// SQLite `user_version` carried over from the source.
  final int userVersion;

  int get totalRows => rowsByTable.values.fold(0, (a, b) => a + b);
}

/// Thrown when a snapshot (or a database about to be restored) fails SQLite's
/// own structural check.
class DatabaseIntegrityException implements Exception {
  const DatabaseIntegrityException(this.detail);
  final String detail;

  @override
  String toString() => 'Database integrity check failed: $detail';
}

/// Writes a consistent copy of a live SQLite database to a new file.
///
/// Copying the bytes of an open database can capture a half-written page or
/// miss a write-ahead log. Instead, every object definition and every row is
/// read inside ONE transaction on the live connection (a single, consistent
/// read view: no write on this connection can interleave, and SQLite's shared
/// lock keeps other connections from changing the file underneath) and written
/// into a fresh database file, which is then checked with
/// `PRAGMA integrity_check`. This works the same with rollback-journal and WAL
/// modes and on every SQLite version Atlas ships against, unlike `VACUUM INTO`
/// (SQLite 3.27+, which older Android system libraries lack).
abstract final class DatabaseSnapshot {
  static const _pageSize = 500;

  /// Snapshot [source] into a new database at [targetPath] (overwritten if it
  /// exists), opened through [factory].
  static Future<SnapshotStats> write({
    required Database source,
    required DatabaseFactory factory,
    required String targetPath,
  }) async {
    final target = File(targetPath);
    if (target.existsSync()) target.deleteSync();
    for (final suffix in const ['-journal', '-wal', '-shm']) {
      final f = File('$targetPath$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    target.parent.createSync(recursive: true);

    final out = await factory.openDatabase(targetPath);
    final counts = <String, int>{};
    var userVersion = 0;
    try {
      await source.transaction((src) async {
        userVersion = _firstInt(await src.rawQuery('PRAGMA user_version'));
        final objects = await src
            .rawQuery("SELECT type, name, tbl_name, sql FROM sqlite_master "
                "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
                "ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name");
        final tables = [
          for (final o in objects)
            if (o['type'] == 'table') o,
        ];
        final others = [
          for (final o in objects)
            if (o['type'] != 'table') o,
        ];

        await out.transaction((dst) async {
          for (final t in tables) {
            await dst.execute(t['sql'] as String);
          }
          for (final t in tables) {
            final name = t['name'] as String;
            var copied = 0;
            while (true) {
              final rows = await src.rawQuery(
                  'SELECT * FROM ${_quote(name)} LIMIT $_pageSize OFFSET $copied');
              if (rows.isEmpty) break;
              final batch = dst.batch();
              for (final r in rows) {
                batch.insert(name, r);
              }
              await batch.commit(noResult: true);
              copied += rows.length;
              if (rows.length < _pageSize) break;
            }
            counts[name] = copied;
          }
          // Indexes, triggers and views after the data (faster, and a trigger
          // must not fire on the copy).
          for (final o in others) {
            await dst.execute(o['sql'] as String);
          }
        });
      });
      await out.execute('PRAGMA user_version = $userVersion');
      await verify(out);
    } finally {
      await out.close();
    }
    return SnapshotStats(rowsByTable: counts, userVersion: userVersion);
  }

  /// Runs `PRAGMA integrity_check` on [db]; throws
  /// [DatabaseIntegrityException] unless SQLite reports `ok`.
  static Future<void> verify(DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA integrity_check');
    final messages = [for (final r in rows) '${r.values.first}'];
    if (messages.length != 1 || messages.single != 'ok') {
      throw DatabaseIntegrityException(messages.take(5).join('; '));
    }
  }

  /// Row count per user table of [db] (sqlite_* tables excluded).
  static Future<Map<String, int>> tableCounts(DatabaseExecutor db) async {
    final tables =
        await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name");
    return {
      for (final t in tables)
        t['name'] as String: _firstInt(await db
            .rawQuery('SELECT COUNT(*) FROM ${_quote(t['name'] as String)}')),
    };
  }

  static int _firstInt(List<Map<String, Object?>> rows) =>
      rows.isEmpty ? 0 : (rows.first.values.first as int? ?? 0);

  static String _quote(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';
}
