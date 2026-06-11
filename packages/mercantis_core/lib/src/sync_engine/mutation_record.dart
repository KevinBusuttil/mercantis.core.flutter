import 'dart:convert';

enum MutationType {
  createDocument,
  updateDocument,
  deleteDocument,
  submitDocument,
  cancelDocument,
  amendDocument,
  installApp,
  uninstallApp,
  createAttachment,
  deleteAttachment,
}

enum MutationStatus { pending, pushing, pushed, failed }

class MutationRecord {
  final String id;
  final MutationType type;
  final String docType;
  final String documentId;
  final Map<String, dynamic> payload;
  final String deviceId;
  final String userId;
  final DateTime localTimestamp;
  String? syncVersion;
  MutationStatus status;

  MutationRecord({
    required this.id,
    required this.type,
    required this.docType,
    required this.documentId,
    required this.payload,
    required this.deviceId,
    required this.userId,
    required this.localTimestamp,
    this.syncVersion,
    this.status = MutationStatus.pending,
  });

  factory MutationRecord.fromDbRow(Map<String, dynamic> row) => MutationRecord(
        id: row['id'] as String,
        type: MutationType.values.firstWhere(
          (t) => t.name == row['type'],
          orElse: () => MutationType.updateDocument,
        ),
        docType: row['doctype'] as String,
        documentId: row['document_id'] as String,
        payload:
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        deviceId: row['device_id'] as String,
        userId: row['user_id'] as String,
        localTimestamp: DateTime.fromMillisecondsSinceEpoch(
            row['local_timestamp'] as int),
        syncVersion: row['sync_version'] as String?,
        status: MutationStatus.values.firstWhere(
          (s) => s.name == row['status'],
          orElse: () => MutationStatus.pending,
        ),
      );

  Map<String, dynamic> toDbRow() => {
        'id': id,
        'type': type.name,
        'doctype': docType,
        'document_id': documentId,
        'payload': jsonEncode(payload),
        'device_id': deviceId,
        'user_id': userId,
        'local_timestamp': localTimestamp.millisecondsSinceEpoch,
        'sync_version': syncVersion,
        'status': status.name,
      };
}
