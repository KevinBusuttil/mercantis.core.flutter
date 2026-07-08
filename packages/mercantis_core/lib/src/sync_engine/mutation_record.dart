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

  /// The camelCase wire shape the Atlas Team backend speaks (its Rust
  /// `MutationRecord` mirrors these names verbatim). Unlike [toDbRow], the
  /// payload rides as a JSON object, not a re-encoded string.
  Map<String, dynamic> toWireJson() => {
        'id': id,
        'type': type.name,
        'docType': docType,
        'documentId': documentId,
        'payload': payload,
        'deviceId': deviceId,
        'userId': userId,
        'localTimestamp': localTimestamp.millisecondsSinceEpoch,
        if (syncVersion != null) 'syncVersion': syncVersion,
        'status': status.name,
      };

  factory MutationRecord.fromWireJson(Map<String, dynamic> json) =>
      MutationRecord(
        id: json['id'] as String,
        type: MutationType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => MutationType.updateDocument,
        ),
        docType: json['docType'] as String,
        documentId: json['documentId'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        deviceId: json['deviceId'] as String,
        userId: json['userId'] as String,
        localTimestamp: DateTime.fromMillisecondsSinceEpoch(
            (json['localTimestamp'] as num).toInt()),
        syncVersion: json['syncVersion'] as String?,
        status: MutationStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => MutationStatus.pending,
        ),
      );
}
