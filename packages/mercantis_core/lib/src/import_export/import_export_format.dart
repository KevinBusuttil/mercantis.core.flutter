/// Common shapes for the bulk import / export subsystem (ADR-046).

/// Wire format for bulk transfer.
enum ImportExportFormat { csv, json }

/// What to do when an imported row's `id` matches an existing document.
enum ImportConflictPolicy {
  /// Default — overwrite the existing document with the imported fields.
  overwrite,

  /// Keep the existing document; record the row as `skipped`.
  skipExisting,

  /// Treat the conflict as a per-row failure.
  fail,
}

/// The kind of outcome a single imported row produced.
enum ImportRowStatus { inserted, updated, skipped, failed }

/// Per-row outcome from an import run. Aggregated into [ImportReport].
class ImportRowOutcome {
  final ImportRowStatus status;

  /// The affected document id for inserted/updated/skipped rows.
  final String? documentId;

  /// The source row index for failed rows.
  final int? rowIndex;

  /// Human-readable reason for skipped/failed rows.
  final String? reason;

  const ImportRowOutcome._(
    this.status, {
    this.documentId,
    this.rowIndex,
    this.reason,
  });

  factory ImportRowOutcome.inserted(String documentId) =>
      ImportRowOutcome._(ImportRowStatus.inserted, documentId: documentId);

  factory ImportRowOutcome.updated(String documentId) =>
      ImportRowOutcome._(ImportRowStatus.updated, documentId: documentId);

  factory ImportRowOutcome.skipped(String documentId, String reason) =>
      ImportRowOutcome._(ImportRowStatus.skipped,
          documentId: documentId, reason: reason);

  factory ImportRowOutcome.failed(int rowIndex, String reason) =>
      ImportRowOutcome._(ImportRowStatus.failed,
          rowIndex: rowIndex, reason: reason);

  @override
  bool operator ==(Object other) =>
      other is ImportRowOutcome &&
      other.status == status &&
      other.documentId == documentId &&
      other.rowIndex == rowIndex &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(status, documentId, rowIndex, reason);

  @override
  String toString() =>
      'ImportRowOutcome(${status.name}, documentId: $documentId, '
      'rowIndex: $rowIndex, reason: $reason)';
}

/// Aggregated outcome of an `import(...)` call. Imports never partially abort:
/// every row is attempted, and per-row failures are recorded without rolling
/// back successful rows.
class ImportReport {
  final String docType;
  final int rowsRead;
  final List<ImportRowOutcome> outcomes;

  const ImportReport({
    required this.docType,
    required this.rowsRead,
    required this.outcomes,
  });

  int _count(ImportRowStatus s) =>
      outcomes.where((o) => o.status == s).length;

  int get insertedCount => _count(ImportRowStatus.inserted);
  int get updatedCount => _count(ImportRowStatus.updated);
  int get skippedCount => _count(ImportRowStatus.skipped);
  int get failedCount => _count(ImportRowStatus.failed);
}

/// Errors raised by the import/export subsystem.
class ImportExportException implements Exception {
  final String message;

  /// 1-based line for CSV parse errors, when known.
  final int? line;

  const ImportExportException(this.message, {this.line});

  factory ImportExportException.malformedCsv(int line, String reason) =>
      ImportExportException('Malformed CSV at line $line: $reason', line: line);

  factory ImportExportException.malformedJson(String reason) =>
      ImportExportException('Malformed JSON: $reason');

  factory ImportExportException.docTypeNotRegistered(String docType) =>
      ImportExportException('DocType "$docType" is not registered.');

  @override
  String toString() => 'ImportExportException: $message';
}
