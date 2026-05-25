import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../metadata/doc_type.dart';
import '../metadata/metadata_registry.dart';
import '../metadata/meta_composer.dart';
import '../permissions/permission_engine.dart';
import '../workflow/workflow_engine.dart';
import '../expression_engine/expression_evaluator.dart';
import '../naming/naming_service.dart';
import '../sync_engine/sync_engine.dart';
import '../sync_engine/mutation_record.dart';
import '../notifications/event_emitter.dart';
import 'document.dart';
import 'document_version.dart';
import 'validation_pipeline.dart';

class ConcurrencyConflictError implements Exception {
  final String message;
  const ConcurrencyConflictError(this.message);
  @override
  String toString() => 'ConcurrencyConflictError: $message';
}

class ValidationException implements Exception {
  final List<ValidationError> errors;
  const ValidationException(this.errors);
  @override
  String toString() => 'ValidationException: ${errors.map((e) => e.toString()).join(', ')}';
}

class DocumentEngine {
  final Database _db;
  final MetadataRegistry _registry;
  final MetaComposer _metaComposer;
  final PermissionEngine _permissionEngine;
  final WorkflowEngine _workflowEngine;
  final ExpressionEvaluator _expressionEvaluator;
  final NamingService _namingService;
  final SyncEngine _syncEngine;
  final EventEmitter _emitter;
  final String deviceId;
  final String userId;
  final ValidationPipeline _pipeline = ValidationPipeline();

  static const _uuid = Uuid();

  DocumentEngine({
    required Database database,
    required MetadataRegistry registry,
    required MetaComposer metaComposer,
    required PermissionEngine permissionEngine,
    required WorkflowEngine workflowEngine,
    required ExpressionEvaluator expressionEvaluator,
    required NamingService namingService,
    required SyncEngine syncEngine,
    required EventEmitter emitter,
    required this.deviceId,
    required this.userId,
  })  : _db = database,
        _registry = registry,
        _metaComposer = metaComposer,
        _permissionEngine = permissionEngine,
        _workflowEngine = workflowEngine,
        _expressionEvaluator = expressionEvaluator,
        _namingService = namingService,
        _syncEngine = syncEngine,
        _emitter = emitter;

  Future<Document> save(Document doc, Set<String> userRoles) async {
    final docType = await _registry.get(doc.docType);
    if (docType == null) throw Exception('DocType not found: ${doc.docType}');

    // Enforce submit immutability
    if (doc.docStatus == 1) {
      // Only allowOnSubmit fields can be changed. Handled by caller.
      throw Exception('Cannot edit a Submitted document directly. Use amend().');
    }

    final op =
        doc.id.isEmpty ? DocumentOperation.create : DocumentOperation.write;

    if (!_permissionEngine.canPerform(
        operation: op, on: docType, userRoles: userRoles)) {
      throw Exception('Permission denied: $op on ${doc.docType}');
    }

    // Optimistic concurrency check
    if (doc.id.isNotEmpty) {
      final existing = await _fetchRaw(doc.docType, doc.id);
      if (existing != null &&
          existing.modifiedAt != null &&
          doc.modifiedAt != null) {
        if (existing.modifiedAt!.isAfter(doc.modifiedAt!)) {
          throw const ConcurrencyConflictError(
              'Document was modified by another operation. Reload and try again.');
        }
      }
    }

    // Assign ID if new
    if (doc.id.isEmpty) {
      final context = NamingContext(database: _db, userId: userId);
      doc.id = await _namingService.resolve(docType, doc, context);
      doc.createdAt = DateTime.now();
    }
    doc.modifiedAt = DateTime.now();
    doc.syncState = SyncState.local;

    // Run validation pipeline
    final result = await _pipeline.run(doc, docType, _db, op, userRoles);
    if (!result.isValid) throw ValidationException(result.errors);

    // Compute diff for versioning (store in audit_log)
    Document? previousVersion;
    if (doc.id.isNotEmpty) {
      previousVersion = await _fetchRaw(doc.docType, doc.id);
    }

    // Persist document
    await _db.insert(
      'documents',
      doc.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Save children
    await _db.delete('document_children',
        where: 'parent_id = ?', whereArgs: [doc.id]);
    for (final entry in doc.children.entries) {
      int idx = 0;
      for (final child in entry.value) {
        final childId = child.id.isEmpty ? _uuid.v4() : child.id;
        child.id = childId;
        child.rowIndex = idx++;
        await _db.insert(
          'document_children',
          {
            'id': childId,
            'parent_id': doc.id,
            'parent_doctype': doc.docType,
            'table_name': entry.key,
            'row_index': child.rowIndex,
            'payload': jsonEncode(child.payload),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    // Write audit log entry
    final diffs = previousVersion != null
        ? DocumentVersion.computeDiff(previousVersion.payload, doc.payload)
        : <FieldDiff>[];
    await _db.insert('audit_log', {
      'id': _uuid.v4(),
      'document_id': doc.id,
      'doctype': doc.docType,
      'action': previousVersion == null ? 'created' : 'updated',
      'user_id': userId,
      'device_id': deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': jsonEncode({
        'diffs': diffs.map((d) => d.toJson()).toList(),
      }),
    });

    // Append mutation record
    await _syncEngine.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: previousVersion == null
          ? MutationType.createDocument
          : MutationType.updateDocument,
      docType: doc.docType,
      documentId: doc.id,
      payload: doc.toDbRow(),
      deviceId: deviceId,
      userId: userId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));

    _emitter.publish(
        DocumentSavedEvent(document: doc, docType: doc.docType, userId: userId));
    return doc;
  }

  Future<void> delete(
      String docType, String id, Set<String> userRoles) async {
    final dt = await _registry.get(docType);
    if (dt == null) throw Exception('DocType not found: $docType');
    if (!_permissionEngine.canPerform(
        operation: DocumentOperation.delete, on: dt, userRoles: userRoles)) {
      throw Exception('Permission denied: delete on $docType');
    }
    await _db.delete('documents',
        where: 'id = ? AND doctype = ?', whereArgs: [id, docType]);
    await _db.delete('document_children',
        where: 'parent_id = ?', whereArgs: [id]);
    await _syncEngine.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: MutationType.deleteDocument,
      docType: docType,
      documentId: id,
      payload: {'id': id, 'doctype': docType},
      deviceId: deviceId,
      userId: userId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
    _emitter.publish(
        DocumentDeletedEvent(documentId: id, docType: docType, userId: userId));
  }

  Future<Document?> fetch(String docType, String id) =>
      _fetchRaw(docType, id);

  Future<Document?> _fetchRaw(String docType, String id) async {
    final rows = await _db.query(
      'documents',
      where: 'id = ? AND doctype = ?',
      whereArgs: [id, docType],
    );
    if (rows.isEmpty) return null;
    final childRows = await _db.query(
      'document_children',
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    return Document.fromDbRow(
      rows.first,
      childRows: childRows.map(ChildRow.fromDbRow).toList(),
    );
  }

  Future<List<Document>> list(
    String docType, {
    Map<String, dynamic>? filters,
    String? whereExpression,
    List<({String field, bool ascending})>? sortBy,
    int? limit,
    int? offset,
    Set<String>? userRoles,
  }) async {
    var query = 'SELECT * FROM documents WHERE doctype = ?';
    final args = <dynamic>[docType];

    if (filters != null) {
      for (final entry in filters.entries) {
        query +=
            " AND json_extract(payload, '\$.${entry.key}') = ?";
        args.add(entry.value);
      }
    }

    if (sortBy != null && sortBy.isNotEmpty) {
      final orderParts = sortBy
          .map((s) =>
              "json_extract(payload, '\$.${s.field}') ${s.ascending ? 'ASC' : 'DESC'}")
          .join(', ');
      query += ' ORDER BY $orderParts';
    } else {
      query += ' ORDER BY created_at DESC';
    }

    if (limit != null) {
      query += ' LIMIT $limit';
      if (offset != null) query += ' OFFSET $offset';
    }

    final rows = await _db.rawQuery(query, args);
    var docs = rows.map((r) => Document.fromDbRow(r)).toList();

    if (whereExpression != null && whereExpression.isNotEmpty) {
      docs = docs.where((doc) {
        try {
          final ctx = EvaluationContext(
            fields: doc.payload,
            user: {'id': userId},
          );
          return _expressionEvaluator.evaluateBool(whereExpression, ctx);
        } catch (_) {
          return false;
        }
      }).toList();
    }

    return docs;
  }

  Future<Document> submit(Document doc, Set<String> userRoles) async {
    final docType = await _registry.get(doc.docType);
    if (docType == null) throw Exception('DocType not found: ${doc.docType}');
    if (!docType.isSubmittable) {
      throw Exception('DocType ${doc.docType} is not submittable');
    }
    if (doc.docStatus != 0) {
      throw Exception('Only Draft (docStatus=0) documents can be submitted');
    }
    if (!_permissionEngine.canPerform(
        operation: DocumentOperation.submit, on: docType, userRoles: userRoles)) {
      throw Exception('Permission denied: submit on ${doc.docType}');
    }

    doc.docStatus = 1;
    doc.modifiedAt = DateTime.now();
    await _db.update(
      'documents',
      {
        'docstatus': 1,
        'modified_at': doc.modifiedAt!.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [doc.id],
    );
    await _syncEngine.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: MutationType.submitDocument,
      docType: doc.docType,
      documentId: doc.id,
      payload: {'id': doc.id, 'doctype': doc.docType},
      deviceId: deviceId,
      userId: userId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
    _emitter.publish(DocumentSubmittedEvent(
        document: doc, docType: doc.docType, userId: userId));
    return doc;
  }

  Future<Document> cancel(Document doc, Set<String> userRoles) async {
    final docType = await _registry.get(doc.docType);
    if (docType == null) throw Exception('DocType not found: ${doc.docType}');
    if (doc.docStatus != 1) {
      throw Exception(
          'Only Submitted (docStatus=1) documents can be cancelled');
    }
    if (!_permissionEngine.canPerform(
        operation: DocumentOperation.delete, on: docType, userRoles: userRoles)) {
      throw Exception('Permission denied: cancel on ${doc.docType}');
    }

    doc.docStatus = 2;
    doc.modifiedAt = DateTime.now();
    await _db.update(
      'documents',
      {
        'docstatus': 2,
        'modified_at': doc.modifiedAt!.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [doc.id],
    );
    await _syncEngine.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: MutationType.cancelDocument,
      docType: doc.docType,
      documentId: doc.id,
      payload: {'id': doc.id, 'doctype': doc.docType},
      deviceId: deviceId,
      userId: userId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
    _emitter.publish(DocumentCancelledEvent(
        document: doc, docType: doc.docType, userId: userId));
    return doc;
  }

  Future<Document> amend(Document original, Set<String> userRoles) async {
    final docType = await _registry.get(original.docType);
    if (docType == null)
      throw Exception('DocType not found: ${original.docType}');
    if (original.docStatus != 2) {
      throw Exception(
          'Only Cancelled (docStatus=2) documents can be amended');
    }
    if (!_permissionEngine.canPerform(
        operation: DocumentOperation.amend,
        on: docType,
        userRoles: userRoles)) {
      throw Exception('Permission denied: amend on ${original.docType}');
    }

    final amended = Document(
      id: '',
      docType: original.docType,
      company: original.company,
      docStatus: 0,
      payload: Map.from(original.payload),
      amendedFrom: original.id,
    );
    return save(amended, userRoles);
  }
}
