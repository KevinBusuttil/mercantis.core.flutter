import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'attachment.dart';
import 'attachment_store.dart';

/// High-level attachment API (ADR-043) for Hub and other host apps.
///
/// Owns a [Database] (metadata + audit) and an [AttachmentStore] (bytes).
/// `DocumentEngine` can hold a reference for cascade-on-delete; standalone
/// callers construct one directly when they need to attach / read files.
class AttachmentManager {
  final Database _db;
  final AttachmentStore _store;

  /// When true (default), attach/detach operations append an `audit_log` row.
  final bool writeAudit;

  AttachmentManager(this._db, this._store, {this.writeAudit = true});

  /// Persist [data] as an attachment on `(documentId, docType)`, optionally
  /// bound to [fieldKey]. Writes the bytes, then the metadata row and an audit
  /// entry in one transaction; the on-disk write is rolled back if metadata
  /// persistence fails.
  Future<Attachment> attach({
    required String documentId,
    required String docType,
    String? fieldKey,
    required String fileName,
    String mimeType = 'application/octet-stream',
    required List<int> data,
    required String userId,
  }) async {
    final attachmentId = const Uuid().v4();
    final storagePath = _store.write(documentId, attachmentId, data);
    final now = DateTime.now();
    final attachment = Attachment(
      id: attachmentId,
      documentId: documentId,
      docType: docType,
      fieldKey: fieldKey,
      fileName: fileName,
      mimeType: mimeType,
      byteSize: data.length,
      storagePath: storagePath,
      uploadedAt: now,
      uploadedBy: userId,
      sha256: AttachmentStore.sha256Hex(data),
    );

    try {
      await _db.transaction((txn) async {
        await txn.insert('attachments', _toRow(attachment));
        if (writeAudit) {
          await _appendAudit(
              txn, documentId, docType, userId, 'attach', _summary(attachment));
        }
      });
    } catch (e) {
      // Roll back the on-disk write if metadata persistence fails.
      _store.delete(storagePath);
      throw AttachmentException.ioFailure(e.toString());
    }
    return attachment;
  }

  /// Read an attachment's bytes, verifying the stored SHA-256.
  Future<Uint8List> read(Attachment attachment) async {
    final data = _store.read(attachment.storagePath);
    if (AttachmentStore.sha256Hex(data) != attachment.sha256) {
      throw AttachmentException.integrityFailure(attachment.id);
    }
    return data;
  }

  /// Read by id. Throws [AttachmentException.notFound] when unknown.
  Future<Uint8List> readById(String id) async {
    final attachment = await metadata(id);
    if (attachment == null) throw AttachmentException.notFound(id);
    return read(attachment);
  }

  /// All attachments on [documentId], oldest first.
  Future<List<Attachment>> attachmentsForDocument(String documentId) async {
    final rows = await _db.query(
      'attachments',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'uploaded_at ASC, id ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Attachments bound to [fieldKey] on [documentId], oldest first.
  Future<List<Attachment>> attachmentsForField(
      String fieldKey, String documentId) async {
    final rows = await _db.query(
      'attachments',
      where: 'document_id = ? AND field_key = ?',
      whereArgs: [documentId, fieldKey],
      orderBy: 'uploaded_at ASC, id ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<Attachment?> metadata(String id) async {
    final rows =
        await _db.query('attachments', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Remove a single attachment by id. Tolerates a missing on-disk file.
  Future<void> delete(String id, String userId) async {
    final existing = await metadata(id);
    if (existing == null) throw AttachmentException.notFound(id);
    await _db.transaction((txn) async {
      await txn.delete('attachments', where: 'id = ?', whereArgs: [id]);
      if (writeAudit) {
        await _appendAudit(txn, existing.documentId, existing.docType, userId,
            'detach', _summary(existing));
      }
    });
    _store.delete(existing.storagePath);
  }

  /// Cascade: remove every attachment for [documentId]. Called by
  /// `DocumentEngine.delete(...)` when a manager is wired into the engine.
  Future<void> deleteAll(String documentId, String userId) async {
    final existing = await attachmentsForDocument(documentId);
    if (existing.isEmpty) return;
    await _db.transaction((txn) async {
      await txn
          .delete('attachments', where: 'document_id = ?', whereArgs: [documentId]);
      if (writeAudit) {
        await _appendAudit(txn, documentId, existing.first.docType, userId,
            'detachAll', jsonEncode({'count': existing.length}));
      }
    });
    _store.deleteAll(documentId);
  }

  // Internals

  Map<String, Object?> _toRow(Attachment a) => {
        'id': a.id,
        'document_id': a.documentId,
        'doc_type': a.docType,
        'field_key': a.fieldKey,
        'file_name': a.fileName,
        'mime_type': a.mimeType,
        'byte_size': a.byteSize,
        'storage_path': a.storagePath,
        'uploaded_at': a.uploadedAt.millisecondsSinceEpoch,
        'uploaded_by': a.uploadedBy,
        'sha256': a.sha256,
      };

  Attachment _fromRow(Map<String, Object?> r) => Attachment(
        id: r['id'] as String,
        documentId: r['document_id'] as String,
        docType: r['doc_type'] as String,
        fieldKey: r['field_key'] as String?,
        fileName: r['file_name'] as String,
        mimeType: (r['mime_type'] as String?) ?? 'application/octet-stream',
        byteSize: (r['byte_size'] as int?) ?? 0,
        storagePath: r['storage_path'] as String,
        uploadedAt:
            DateTime.fromMillisecondsSinceEpoch(r['uploaded_at'] as int),
        uploadedBy: r['uploaded_by'] as String,
        sha256: r['sha256'] as String,
      );

  Future<void> _appendAudit(
    DatabaseExecutor txn,
    String documentId,
    String docType,
    String userId,
    String action,
    String payloadJson,
  ) async {
    await txn.insert('audit_log', {
      'id': const Uuid().v4(),
      'document_id': documentId,
      'doctype': docType,
      'action': action,
      'user_id': userId,
      'device_id': '',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': payloadJson,
    });
  }

  String _summary(Attachment a) => jsonEncode({
        'attachmentId': a.id,
        'fileName': a.fileName,
        'byteSize': a.byteSize,
        'sha256': a.sha256,
      });
}
