/// File attachments (ADR-043). Metadata for one row in the `attachments`
/// table; the bytes themselves live on disk under the `AttachmentStore` root.
library;

/// A file attachment bound to a document (and optionally a specific field).
/// Use `AttachmentManager.read` to materialise the bytes.
class Attachment {
  final String id;
  final String documentId;
  final String docType;

  /// Bound field key. `null` for general document attachments not tied to a
  /// specific `FieldType.attach` field.
  final String? fieldKey;
  final String fileName;
  final String mimeType;
  final int byteSize;

  /// Path under the attachment store root (`<documentId>/<id>`).
  final String storagePath;
  final DateTime uploadedAt;
  final String uploadedBy;

  /// Lower-case hex SHA-256 of the file bytes — used for integrity
  /// verification and (future) content-addressable dedup.
  final String sha256;

  const Attachment({
    required this.id,
    required this.documentId,
    required this.docType,
    required this.fieldKey,
    required this.fileName,
    required this.mimeType,
    required this.byteSize,
    required this.storagePath,
    required this.uploadedAt,
    required this.uploadedBy,
    required this.sha256,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'docType': docType,
        'fieldKey': fieldKey,
        'fileName': fileName,
        'mimeType': mimeType,
        'byteSize': byteSize,
        'storagePath': storagePath,
        'uploadedAt': uploadedAt.toIso8601String(),
        'uploadedBy': uploadedBy,
        'sha256': sha256,
      };
}

/// Errors raised by the attachment subsystem.
class AttachmentException implements Exception {
  final String message;
  const AttachmentException(this.message);

  factory AttachmentException.notFound(String id) =>
      AttachmentException('Attachment "$id" not found.');

  factory AttachmentException.integrityFailure(String id) =>
      AttachmentException(
          'Attachment "$id" failed its SHA-256 integrity check.');

  factory AttachmentException.ioFailure(String reason) =>
      AttachmentException('Attachment I/O failure: $reason');

  @override
  String toString() => 'AttachmentException: $message';
}
