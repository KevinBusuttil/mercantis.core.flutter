import 'package:sqflite_common/sqflite.dart';

/// Thrown when a DocType's counter-based numbering is on hold. Nothing is
/// minted and nothing is saved; the host shows [message] and points the
/// operator at the recovery decision.
class NamingHoldException implements Exception {
  const NamingHoldException(this.docType, this.message);

  final String docType;
  final String message;

  @override
  String toString() => message;
}

/// The numbering policy of one DocType (schema v9, `naming_series_policy`).
class NamingSeriesPolicy {
  const NamingSeriesPolicy({
    required this.docType,
    this.hold = false,
    this.holdReason,
    this.segment = '',
    this.updatedAt,
  });

  final String docType;

  /// No new counter-based number may be minted while true.
  final bool hold;
  final String? holdReason;

  /// Inserted after the resolved series prefix: `SINV-2026-` + `R1` gives
  /// `SINV-2026-R1-`. Empty for the normal series.
  final String segment;
  final DateTime? updatedAt;

  /// The counter prefix this policy turns [prefix] into.
  String apply(String prefix) => segment.isEmpty ? prefix : '$prefix$segment-';

  static final _segmentPattern = RegExp(r'^[A-Z0-9]{1,8}$');

  /// A recovery segment must be short, upper-case and id-safe.
  static bool isValidSegment(String s) =>
      s.isEmpty || _segmentPattern.hasMatch(s);
}

/// Reads and writes `naming_series_policy`. Every read tolerates a database
/// that predates v9 (no table) and returns "no policy".
abstract final class NamingSeriesPolicyStore {
  static const table = 'naming_series_policy';

  static Future<NamingSeriesPolicy?> read(
      DatabaseExecutor db, String docType) async {
    try {
      final rows =
          await db.query(table, where: 'doc_type = ?', whereArgs: [docType]);
      if (rows.isEmpty) return null;
      return _fromRow(rows.first);
    } on DatabaseException {
      return null;
    }
  }

  static Future<List<NamingSeriesPolicy>> all(DatabaseExecutor db) async {
    try {
      return [
        for (final r in await db.query(table, orderBy: 'doc_type')) _fromRow(r),
      ];
    } on DatabaseException {
      return const [];
    }
  }

  /// Insert or replace the policy for [policy.docType]. Throws
  /// [ArgumentError] for an invalid segment.
  static Future<void> write(
      DatabaseExecutor db, NamingSeriesPolicy policy) async {
    if (!NamingSeriesPolicy.isValidSegment(policy.segment)) {
      throw ArgumentError.value(
          policy.segment, 'segment', 'use 1-8 upper-case letters or digits');
    }
    await db.insert(
      table,
      {
        'doc_type': policy.docType,
        'hold': policy.hold ? 1 : 0,
        'hold_reason': policy.holdReason,
        'segment': policy.segment,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static NamingSeriesPolicy _fromRow(Map<String, Object?> r) =>
      NamingSeriesPolicy(
        docType: '${r['doc_type']}',
        hold: (r['hold'] as int? ?? 0) == 1,
        holdReason: r['hold_reason'] as String?,
        segment: (r['segment'] as String?) ?? '',
        updatedAt: r['updated_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int)
            : null,
      );
}
