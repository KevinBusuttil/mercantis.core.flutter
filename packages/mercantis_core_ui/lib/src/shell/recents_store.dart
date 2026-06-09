import 'package:sqflite/sqflite.dart';

/// A single "recently opened" entry — a record the user navigated to.
///
/// Mirrors the Swift shell's `RecentDestination.record` case, but persisted
/// (the Swift list was in-memory only) so it survives app restarts.
class RecentEntry {
  const RecentEntry({
    required this.docType,
    required this.docId,
    required this.title,
    this.subtitle,
    required this.openedAt,
  });

  final String docType;
  final String docId;
  final String title;
  final String? subtitle;
  final DateTime openedAt;

  /// Stable identity used for de-duplication (one row per record).
  String get key => '$docType::$docId';
}

/// Persists the most-recently-opened records in a dedicated table on the
/// shared database. The table is created lazily on first use so this stays a
/// self-contained UI-shell concern without bumping the engine's migrations.
class RecentsStore {
  RecentsStore(this._db);

  final Database _db;

  /// Most-recent-first cap, matching the Swift shell's `prefix(20)`.
  static const int maxEntries = 20;

  static const String _table = 'ui_recents';

  Future<void>? _ready;

  Future<void> _ensureTable() {
    return _ready ??= _db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        key TEXT PRIMARY KEY,
        doc_type TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        title TEXT NOT NULL,
        subtitle TEXT,
        opened_at INTEGER NOT NULL
      )
    ''');
  }

  /// Records (or refreshes) [entry] as the most recent, then trims the table
  /// back to [maxEntries]. Re-opening a record moves it to the top rather than
  /// adding a duplicate (upsert on the primary key).
  Future<void> record(RecentEntry entry) async {
    await _ensureTable();
    await _db.insert(
      _table,
      {
        'key': entry.key,
        'doc_type': entry.docType,
        'doc_id': entry.docId,
        'title': entry.title,
        'subtitle': entry.subtitle,
        'opened_at': entry.openedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _db.execute(
      'DELETE FROM $_table WHERE key NOT IN '
      '(SELECT key FROM $_table ORDER BY opened_at DESC LIMIT ?)',
      [maxEntries],
    );
  }

  /// The recent records, newest first.
  Future<List<RecentEntry>> list() async {
    await _ensureTable();
    final rows = await _db.query(
      _table,
      orderBy: 'opened_at DESC',
      limit: maxEntries,
    );
    return [
      for (final r in rows)
        RecentEntry(
          docType: r['doc_type'] as String,
          docId: r['doc_id'] as String,
          title: r['title'] as String,
          subtitle: r['subtitle'] as String?,
          openedAt:
              DateTime.fromMillisecondsSinceEpoch(r['opened_at'] as int),
        ),
    ];
  }

  /// Clears the whole list (the "Clear recents" action).
  Future<void> clear() async {
    await _ensureTable();
    await _db.delete(_table);
  }
}
