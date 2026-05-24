import 'dart:convert';

enum SyncState { local, pushing, synced, conflict }

class ChildRow {
  String id;
  final String parentId;
  final String parentDocType;
  final String tableName;
  int rowIndex;
  Map<String, dynamic> payload;

  ChildRow({
    required this.id,
    required this.parentId,
    required this.parentDocType,
    required this.tableName,
    required this.rowIndex,
    required this.payload,
  });

  factory ChildRow.newRow({
    required String parentId,
    required String parentDocType,
    required String tableName,
    required int rowIndex,
  }) =>
      ChildRow(
        id: '',
        parentId: parentId,
        parentDocType: parentDocType,
        tableName: tableName,
        rowIndex: rowIndex,
        payload: {},
      );

  factory ChildRow.fromDbRow(Map<String, dynamic> row) => ChildRow(
        id: row['id'] as String,
        parentId: row['parent_id'] as String,
        parentDocType: row['parent_doctype'] as String,
        tableName: row['table_name'] as String,
        rowIndex: row['row_index'] as int,
        payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      );

  Map<String, dynamic> toDbRow() => {
        'id': id,
        'parent_id': parentId,
        'parent_doctype': parentDocType,
        'table_name': tableName,
        'row_index': rowIndex,
        'payload': jsonEncode(payload),
      };

  ChildRow copyWith({
    String? id,
    String? parentId,
    String? parentDocType,
    String? tableName,
    int? rowIndex,
    Map<String, dynamic>? payload,
  }) =>
      ChildRow(
        id: id ?? this.id,
        parentId: parentId ?? this.parentId,
        parentDocType: parentDocType ?? this.parentDocType,
        tableName: tableName ?? this.tableName,
        rowIndex: rowIndex ?? this.rowIndex,
        payload: payload ?? Map.from(this.payload),
      );
}

class Document {
  String id;
  final String docType;
  String? company;
  int docStatus;
  Map<String, dynamic> payload;
  DateTime createdAt;
  DateTime? modifiedAt;
  String? syncVersion;
  SyncState syncState;
  String? amendedFrom;
  Map<String, List<ChildRow>> children;

  Document({
    required this.id,
    required this.docType,
    this.company,
    this.docStatus = 0,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    this.modifiedAt,
    this.syncVersion,
    this.syncState = SyncState.local,
    this.amendedFrom,
    Map<String, List<ChildRow>>? children,
  })  : payload = payload ?? {},
        createdAt = createdAt ?? DateTime.now(),
        children = children ?? {};

  factory Document.create(String docType) => Document(
        id: '',
        docType: docType,
        createdAt: DateTime.now(),
      );

  dynamic operator [](String key) => payload[key];
  void operator []=(String key, dynamic value) => payload[key] = value;

  factory Document.fromDbRow(Map<String, dynamic> row, {List<ChildRow>? childRows}) {
    final doc = Document(
      id: row['id'] as String,
      docType: row['doctype'] as String,
      company: row['company'] as String?,
      docStatus: (row['docstatus'] as int?) ?? 0,
      payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      modifiedAt: row['modified_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['modified_at'] as int)
          : null,
      syncVersion: row['sync_version'] as String?,
      syncState: SyncState.values.firstWhere(
        (s) => s.name == (row['sync_state'] as String? ?? 'local'),
        orElse: () => SyncState.local,
      ),
      amendedFrom: row['amended_from'] as String?,
    );
    if (childRows != null) {
      for (final child in childRows) {
        doc.children.putIfAbsent(child.tableName, () => []).add(child);
      }
      for (final key in doc.children.keys) {
        doc.children[key]!.sort((a, b) => a.rowIndex.compareTo(b.rowIndex));
      }
    }
    return doc;
  }

  Map<String, dynamic> toDbRow() => {
        'id': id,
        'doctype': docType,
        'company': company,
        'docstatus': docStatus,
        'payload': jsonEncode(payload),
        'created_at': createdAt.millisecondsSinceEpoch,
        'modified_at': modifiedAt?.millisecondsSinceEpoch,
        'sync_version': syncVersion,
        'sync_state': syncState.name,
        'amended_from': amendedFrom,
      };

  bool get isDraft => docStatus == 0;
  bool get isSubmitted => docStatus == 1;
  bool get isCancelled => docStatus == 2;

  Document copyWith({
    String? id,
    String? docType,
    String? company,
    int? docStatus,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? syncVersion,
    SyncState? syncState,
    String? amendedFrom,
    Map<String, List<ChildRow>>? children,
  }) =>
      Document(
        id: id ?? this.id,
        docType: docType ?? this.docType,
        company: company ?? this.company,
        docStatus: docStatus ?? this.docStatus,
        payload: payload ?? Map.from(this.payload),
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        syncVersion: syncVersion ?? this.syncVersion,
        syncState: syncState ?? this.syncState,
        amendedFrom: amendedFrom ?? this.amendedFrom,
        children: children ?? Map.from(this.children),
      );
}
