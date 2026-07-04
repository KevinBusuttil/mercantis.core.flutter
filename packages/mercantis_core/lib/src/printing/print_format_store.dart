import 'print_format.dart';
import 'print_service.dart';

/// Persistence port for print formats + letter heads (HU2). Backends decide how
/// the JSON maps are stored — as `Print Format` documents through the
/// `DocumentEngine`, an app-settings blob, or a file — while [PrintFormatStore]
/// layers validation, id-keyed upsert and `PrintService` hydration on top.
///
/// Each entry is the format/letter-head [PrintFormat.toJson] / [LetterHead.toJson]
/// map, keyed by its `id`; saving an existing id replaces it.
abstract class PrintFormatRepository {
  Future<List<Map<String, dynamic>>> loadFormats();
  Future<void> writeFormat(Map<String, dynamic> json);
  Future<void> removeFormat(String id);

  Future<List<Map<String, dynamic>>> loadLetterHeads();
  Future<void> writeLetterHead(Map<String, dynamic> json);
  Future<void> removeLetterHead(String id);
}

/// In-memory [PrintFormatRepository] — the default backend for tests and
/// ephemeral use. A durable backend (document-engine / settings) implements the
/// same port for real persistence.
class InMemoryPrintFormatRepository implements PrintFormatRepository {
  final Map<String, Map<String, dynamic>> _formats = {};
  final Map<String, Map<String, dynamic>> _letterHeads = {};

  @override
  Future<List<Map<String, dynamic>>> loadFormats() async =>
      _formats.values.map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  Future<void> writeFormat(Map<String, dynamic> json) async {
    _formats[json['id'] as String] = Map<String, dynamic>.from(json);
  }

  @override
  Future<void> removeFormat(String id) async => _formats.remove(id);

  @override
  Future<List<Map<String, dynamic>>> loadLetterHeads() async =>
      _letterHeads.values.map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  Future<void> writeLetterHead(Map<String, dynamic> json) async {
    _letterHeads[json['id'] as String] = Map<String, dynamic>.from(json);
  }

  @override
  Future<void> removeLetterHead(String id) async => _letterHeads.remove(id);
}

/// Persists and loads [PrintFormat]s / [LetterHead]s as data, validating on the
/// way in and hydrating a [PrintService] on the way out (HU2). The concrete
/// storage lives behind a [PrintFormatRepository].
class PrintFormatStore {
  PrintFormatStore(this._repo);

  final PrintFormatRepository _repo;

  Future<List<PrintFormat>> formats() async => [
        for (final j in await _repo.loadFormats()) PrintFormat.fromJson(j),
      ];

  Future<List<PrintFormat>> formatsForDocType(String docType) async => [
        for (final f in await formats())
          if (f.docType == docType) f,
      ];

  Future<List<LetterHead>> letterHeads() async => [
        for (final j in await _repo.loadLetterHeads()) LetterHead.fromJson(j),
      ];

  /// Validate then persist [format] (upsert by id). Throws
  /// [PrintFormatValidationException] when the format is structurally invalid,
  /// so a half-built designer format never reaches storage.
  Future<void> saveFormat(PrintFormat format) async {
    final errors = PrintFormatValidator.validate(format);
    if (errors.isNotEmpty) throw PrintFormatValidationException(errors);
    await _repo.writeFormat(format.toJson());
  }

  Future<void> deleteFormat(String id) => _repo.removeFormat(id);

  Future<void> saveLetterHead(LetterHead letterHead) =>
      _repo.writeLetterHead(letterHead.toJson());

  Future<void> deleteLetterHead(String id) => _repo.removeLetterHead(id);

  /// Register every persisted letter head and format into [service] (replacing
  /// any already registered under the same id), so saved designs render through
  /// the normal [PrintService.render] path.
  Future<void> hydrate(PrintService service) async {
    for (final lh in await letterHeads()) {
      service.registerLetterHead(lh);
    }
    for (final f in await formats()) {
      service.registerFormat(f);
    }
  }
}

/// Structural validation for a [PrintFormat] before it is persisted. Returns a
/// human-readable error per problem (empty list = valid). Kept pure so both the
/// store and a future designer UI can share it.
class PrintFormatValidator {
  const PrintFormatValidator._();

  static List<String> validate(PrintFormat format) {
    final errors = <String>[];
    if (format.id.trim().isEmpty) errors.add('Format id is required.');
    if (format.name.trim().isEmpty) errors.add('Format name is required.');
    if (format.docType.trim().isEmpty) {
      errors.add('Format must target a DocType.');
    }
    if (format.sections.isEmpty) {
      errors.add('A format needs at least one section.');
    }
    for (var i = 0; i < format.sections.length; i++) {
      final n = i + 1;
      switch (format.sections[i]) {
        case HeadingSection(:final text):
          if (text.trim().isEmpty) errors.add('Heading section $n is empty.');
        case ParagraphSection(:final text):
          if (text.trim().isEmpty) errors.add('Paragraph section $n is empty.');
        case FieldsSection(:final keys):
          if (keys.isEmpty) {
            errors.add('Fields section $n needs at least one field.');
          }
        case TableSection(:final tableKey):
          if (tableKey.trim().isEmpty) {
            errors.add('Table section $n needs a table key.');
          }
        case KeyValueSection(:final label):
          if (label.trim().isEmpty) {
            errors.add('Key/value section $n needs a label.');
          }
      }
    }
    return errors;
  }
}

class PrintFormatValidationException implements Exception {
  final List<String> errors;
  const PrintFormatValidationException(this.errors);

  @override
  String toString() =>
      'PrintFormatValidationException: ${errors.join('; ')}';
}
