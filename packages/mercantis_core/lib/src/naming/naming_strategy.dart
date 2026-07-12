import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../metadata/doc_type.dart';
import '../document_engine/document.dart';
import 'counter_block_allocator.dart';

class NamingContext {
  final Database database;
  final String userId;
  final String? companyAbbr;

  /// Identifies the saving device, so naming-series counter blocks (ADR-042)
  /// can be reserved per device and never collide across offline devices.
  final String deviceId;

  const NamingContext({
    required this.database,
    required this.userId,
    this.companyAbbr,
    this.deviceId = 'local',
  });
}

abstract class NamingStrategy {
  Future<String> resolve(
      DocType docType, Document document, NamingContext context);
}

class UuidV4Strategy implements NamingStrategy {
  static const _uuid = Uuid();
  const UuidV4Strategy();

  @override
  Future<String> resolve(
          DocType docType, Document document, NamingContext context) async =>
      _uuid.v4();
}

class NamingSeriesStrategy implements NamingStrategy {
  final String pattern;
  final CounterBlockAllocator allocator;

  const NamingSeriesStrategy(this.pattern,
      {this.allocator = const CounterBlockAllocator()});

  @override
  Future<String> resolve(
      DocType docType, Document document, NamingContext context) async {
    // Field tokens first (`.{field_key}.` -> the document's value), THEN the
    // hash placeholder via a per-device counter block (ADR-042). The counter
    // is keyed on the fully resolved prefix, so a field-parameterised series
    // (e.g. `POS-.{till_series}.-.####`) sequences independently per value --
    // two tills can never mint the same receipt id.
    final withFields = expandFields(pattern, document.payload);
    final series = expandSeries(withFields);
    if (series == null) return expandDates(withFields, DateTime.now());

    final n = await allocator.next(
      context.database,
      series.prefix,
      context.deviceId,
      seedFloor: (txn) => _maxExistingSuffix(txn, series.prefix),
    );
    return '${series.prefix}${n.toString().padLeft(series.width, '0')}';
  }

  /// Substitute `.{field_key}.` tokens with the document's value for that
  /// field, sanitised to id-safe characters. A missing/blank value collapses
  /// the token to a single `.` so the pattern stays well-formed (hosts that
  /// need a guaranteed value should gate the pattern behind a conditional
  /// naming rule instead).
  static String expandFields(String pattern, Map<String, dynamic> payload) {
    return pattern.replaceAllMapped(
      RegExp(r'\.\{([A-Za-z0-9_]+)\}\.'),
      (m) {
        final raw = '${payload[m.group(1)] ?? ''}'.trim();
        final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');
        return safe.isEmpty ? '.' : '.$safe.';
      },
    );
  }

  /// Substitute the date placeholders (`.YYYY.`, `.YY.`, `.MM.`, `.DD.`) in a
  /// naming pattern for [on].
  static String expandDates(String pattern, DateTime on) {
    var r = pattern;
    r = r.replaceAll('.YYYY.', '.${on.year}.');
    r = r.replaceAll('.YY.', '.${on.year.toString().substring(2)}.');
    r = r.replaceAll('.MM.', '.${on.month.toString().padLeft(2, '0')}.');
    r = r.replaceAll('.DD.', '.${on.day.toString().padLeft(2, '0')}.');
    return r;
  }

  /// Resolve [pattern] to its counter series for [now] (default: today): the
  /// prefix the counter is keyed on (e.g. `SINV-.YYYY.-.####` → `SINV-2026-`)
  /// and the zero-pad width. Returns null when the pattern has no `#` counter
  /// (a fixed or field-derived name). Lets callers inspect/manage a series
  /// without minting a number.
  static ({String prefix, int width})? expandSeries(String pattern,
      {DateTime? now}) {
    final result = expandDates(pattern, now ?? DateTime.now());
    final hashMatch = RegExp(r'\.#+\.?$').firstMatch(result);
    if (hashMatch == null) return null;
    final hashPart = hashMatch.group(0)!;
    final width = hashPart.replaceAll(RegExp('[^#]'), '').length;
    return (prefix: result.substring(0, hashMatch.start), width: width);
  }

  /// Highest numeric suffix already used by documents under [prefix], so a
  /// freshly-introduced counter (e.g. on upgrade from the old COUNT-based
  /// naming) starts above existing ids rather than colliding with them.
  Future<int> _maxExistingSuffix(DatabaseExecutor txn, String prefix) async {
    final rows = await txn.query('documents',
        columns: ['id'], where: 'id LIKE ?', whereArgs: ['$prefix%']);
    var maxN = 0;
    for (final r in rows) {
      final id = r['id'] as String;
      if (id.length <= prefix.length) continue;
      final n = int.tryParse(id.substring(prefix.length));
      if (n != null && n > maxN) maxN = n;
    }
    return maxN;
  }
}

class FieldDerivedStrategy implements NamingStrategy {
  final String fieldKey;
  const FieldDerivedStrategy(this.fieldKey);

  @override
  Future<String> resolve(
      DocType docType, Document document, NamingContext context) async {
    final value = document.payload[fieldKey]?.toString();
    if (value == null || value.isEmpty) {
      throw Exception('Field $fieldKey is empty — cannot derive document name');
    }
    return value;
  }
}

class FormatStrategy implements NamingStrategy {
  final String template;
  const FormatStrategy(this.template);

  @override
  Future<String> resolve(
      DocType docType, Document document, NamingContext context) async {
    var result = template;
    final matches = RegExp(r'\{(\w+)\}').allMatches(template);
    for (final m in matches) {
      final key = m.group(1)!;
      final value = document.payload[key]?.toString() ?? '';
      result = result.replaceAll('{$key}', value);
    }
    return result;
  }
}
