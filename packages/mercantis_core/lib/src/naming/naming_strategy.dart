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
    final now = DateTime.now();
    var result = pattern;
    result = result.replaceAll('.YYYY.', '.${now.year}.');
    result = result.replaceAll('.YY.', '.${now.year.toString().substring(2)}.');
    result = result.replaceAll('.MM.', '.${now.month.toString().padLeft(2, '0')}.');
    result = result.replaceAll('.DD.', '.${now.day.toString().padLeft(2, '0')}.');

    // Resolve hash placeholder via a per-device counter block (ADR-042),
    // keyed on the resolved prefix so each series (and year) sequences
    // independently and offline devices never collide.
    final hashMatch = RegExp(r'\.#+\.?$').firstMatch(result);
    if (hashMatch != null) {
      final hashPart = hashMatch.group(0)!;
      final digits = hashPart.replaceAll(RegExp('[^#]'), '').length;
      final prefix = result.substring(0, hashMatch.start);

      final n = await allocator.next(
        context.database,
        prefix,
        context.deviceId,
        seedFloor: (txn) => _maxExistingSuffix(txn, prefix),
      );
      result = '$prefix${n.toString().padLeft(digits, '0')}';
    }
    return result;
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
