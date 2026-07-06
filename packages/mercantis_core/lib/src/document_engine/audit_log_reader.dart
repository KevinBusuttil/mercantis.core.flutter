import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import 'document_version.dart';

/// One row of the change history the engine writes on every save/submit/
/// cancel: who did what to which document, when, and — for updates — the
/// field-level diffs.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.documentId,
    required this.docType,
    required this.action,
    required this.userId,
    required this.deviceId,
    required this.timestamp,
    required this.diffs,
  });

  final String id;
  final String documentId;
  final String docType;
  final String action; // created / updated / submitted / cancelled / …
  final String userId;
  final String deviceId;
  final DateTime timestamp;
  final List<FieldDiff> diffs;

  factory AuditLogEntry.fromRow(Map<String, dynamic> row) {
    var diffs = const <FieldDiff>[];
    final raw = row['payload'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        final list = decoded is Map ? decoded['diffs'] : null;
        if (list is List) {
          diffs = [
            for (final d in list)
              if (d is Map<String, dynamic>) FieldDiff.fromJson(d),
          ];
        }
      } catch (_) {
        // A malformed payload should never make history unreadable.
      }
    }
    return AuditLogEntry(
      id: row['id'] as String,
      documentId: row['document_id'] as String,
      docType: row['doctype'] as String,
      action: row['action'] as String,
      userId: row['user_id'] as String? ?? '',
      deviceId: row['device_id'] as String? ?? '',
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int? ?? 0),
      diffs: diffs,
    );
  }
}

/// Read access to the `audit_log` table the [DocumentEngine] has always
/// written but nothing could query — the audit found change tracking was
/// "captured but invisible". Newest first.
class AuditLogReader {
  const AuditLogReader(this._db);

  final DatabaseExecutor _db;

  /// Entries filtered by [docType] and/or [documentId], newest first.
  Future<List<AuditLogEntry>> entries({
    String? docType,
    String? documentId,
    int limit = 100,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (docType != null) {
      where.add('doctype = ?');
      args.add(docType);
    }
    if (documentId != null) {
      where.add('document_id = ?');
      args.add(documentId);
    }
    final rows = await _db.query(
      'audit_log',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC, id DESC',
      limit: limit,
    );
    return [for (final r in rows) AuditLogEntry.fromRow(r)];
  }
}
