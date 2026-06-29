import 'dart:typed_data';

import 'mercantis_database.dart';

/// A tabular result of a read-only query: column headers plus rows of
/// already-rendered string cells (null → "", blobs → "<N bytes>"). Port of
/// Swift `ReadOnlyQueryResult`.
class ReadOnlyQueryResult {
  const ReadOnlyQueryResult({
    required this.columns,
    required this.rows,
    required this.truncated,
  });

  final List<String> columns;
  final List<List<String>> rows;

  /// True when the runner stopped at `rowLimit`, so the UI can say the result
  /// was truncated rather than implying it's complete.
  final bool truncated;
}

/// Thrown when the up-front guard rejects a statement. The message is
/// user-facing (shown in the Data Browser).
class ReadOnlyQueryException implements Exception {
  const ReadOnlyQueryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Up-front syntactic guard for the Data Browser. sqflite has no separate
/// read-only connection, so unlike the Swift/GRDB version this guard *is* the
/// safety net: it permits only a single SELECT/WITH/EXPLAIN/PRAGMA statement and
/// rejects anything that could mutate or chain a second statement.
class ReadOnlyQueryGuard {
  const ReadOnlyQueryGuard._();

  static const _allowedLeadingKeywords = <String>{
    'select',
    'with',
    'explain',
    'pragma',
  };

  static void validate(String sql) {
    var trimmed = sql.trim();
    // Allow a single trailing semicolon; reject any interior one (a second
    // statement).
    while (trimmed.endsWith(';')) {
      trimmed = trimmed.substring(0, trimmed.length - 1).trim();
    }
    if (trimmed.isEmpty) {
      throw const ReadOnlyQueryException('Enter a query to run.');
    }
    if (trimmed.contains(';')) {
      throw const ReadOnlyQueryException(
          'Only a single statement can be run at a time. Remove the extra ";".');
    }
    final firstWord = _leadingWord(trimmed).toLowerCase();
    if (!_allowedLeadingKeywords.contains(firstWord)) {
      throw ReadOnlyQueryException(
          'Only read-only queries are allowed here (SELECT / WITH / EXPLAIN / '
          'PRAGMA). "${firstWord.toUpperCase()}" is not permitted.');
    }
  }

  static String _leadingWord(String s) {
    final b = StringBuffer();
    for (final unit in s.codeUnits) {
      final isLetter =
          (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
      if (isLetter) {
        b.writeCharCode(unit);
      } else {
        break;
      }
    }
    return b.toString();
  }
}

/// Renders a raw SQLite cell value as a display string, mirroring Swift's
/// `render`: null → "", blobs → "<N bytes>", everything else → its text form.
String _renderCell(Object? value) {
  if (value == null) return '';
  if (value is Uint8List) return '<${value.length} bytes>';
  if (value is List<int>) return '<${value.length} bytes>';
  return value.toString();
}

extension ReadOnlyQueryRunner on MercantisDatabase {
  /// Runs a single read-only statement and returns its rows. [rowLimit] caps how
  /// many rows are materialised for the UI; the result flags when it was hit.
  /// Throws [ReadOnlyQueryException] when the guard rejects the statement.
  Future<ReadOnlyQueryResult> runReadOnlyQuery(
    String sql, {
    int rowLimit = 5000,
  }) async {
    ReadOnlyQueryGuard.validate(sql);
    final raw = await db.rawQuery(sql);
    final truncated = raw.length > rowLimit;
    final capped = truncated ? raw.sublist(0, rowLimit) : raw;
    // sqflite preserves column order in each row map; an empty result yields no
    // columns (unlike GRDB's cursor metadata) — the UI handles that case.
    final columns = capped.isEmpty ? <String>[] : capped.first.keys.toList();
    final rows = <List<String>>[
      for (final row in capped) [for (final col in columns) _renderCell(row[col])],
    ];
    return ReadOnlyQueryResult(
        columns: columns, rows: rows, truncated: truncated);
  }
}
