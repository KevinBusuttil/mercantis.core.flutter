import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../metadata/doc_type.dart';
import '../document_engine/document.dart';

class NamingContext {
  final Database database;
  final String userId;
  final String? companyAbbr;

  const NamingContext({
    required this.database,
    required this.userId,
    this.companyAbbr,
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
  const NamingSeriesStrategy(this.pattern);

  @override
  Future<String> resolve(
      DocType docType, Document document, NamingContext context) async {
    final now = DateTime.now();
    var result = pattern;
    result = result.replaceAll('.YYYY.', '.${now.year}.');
    result = result.replaceAll('.YY.', '.${now.year.toString().substring(2)}.');
    result = result.replaceAll('.MM.', '.${now.month.toString().padLeft(2, '0')}.');
    result = result.replaceAll('.DD.', '.${now.day.toString().padLeft(2, '0')}.');

    // Resolve hash placeholder (sequential number)
    final hashMatch = RegExp(r'\.#+\.?$').firstMatch(result);
    if (hashMatch != null) {
      final hashPart = hashMatch.group(0)!;
      final digits = hashPart.replaceAll(RegExp('[^#]'), '').length;
      final prefix = result.substring(0, hashMatch.start);

      // Count existing documents with this prefix
      final rows = await context.database.rawQuery(
        "SELECT COUNT(*) as cnt FROM documents WHERE id LIKE ?",
        ['$prefix%'],
      );
      final count = ((rows.first['cnt'] as int?) ?? 0) + 1;
      result = '$prefix${count.toString().padLeft(digits, '0')}';
    }
    return result;
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
