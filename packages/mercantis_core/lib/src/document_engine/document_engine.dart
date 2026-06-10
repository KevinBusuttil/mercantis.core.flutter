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
import '../naming/naming_strategy.dart';
import '../sync_engine/sync_engine.dart';
import '../sync_engine/mutation_record.dart';
import '../notifications/event_emitter.dart';
import 'document.dart';
import 'document_engine_error.dart';
import 'document_version.dart';
import 'list_filter.dart';
import 'validation_pipeline.dart';

export 'document_engine_error.dart';

/// Back-compat alias preserved for call sites that caught the old typed
/// concurrency exception by name; new code should match on
/// [DocumentEngineError] instead.
typedef ConcurrencyConflictError = DocumentEngineError;

/// Back-compat alias for the legacy validation throw shape. See
/// [DocumentEngineError.validationFailed] for the structured form.
typedef ValidationException = DocumentEngineError;

class DocumentEngine {
  final Database _db;
  final MetadataRegistry _registry;
  final PermissionEngine _permissionEngine;
  final ExpressionEvaluator _expressionEvaluator;
  final NamingService _namingService;
  final SyncEngine _syncEngine;
  final EventEmitter _emitter;
  final String deviceId;
  final String userId;
  final List<DocumentInterceptor> _interceptors;
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
    List<DocumentInterceptor> interceptors = const [],
  })  : _db = database,
        _registry = registry,
        _permissionEngine = permissionEngine,
        _expressionEvaluator = expressionEvaluator,
        _namingService = namingService,
        _syncEngine = syncEngine,
        _emitter = emitter,
        _interceptors = interceptors;

  Future<Document> save(Document doc, Set<String> userRoles) async {
    final docType = await _registry.get(doc.docType);
    if (docType == null) {
      throw DocumentEngineError.docTypeNotFound(doc.docType);
    }

    // Enforce submit immutability
    if (doc.docStatus == 1) {
      // Only allowOnSubmit fields can be changed. Handled by caller.
      throw DocumentEngineError.invalidDocStatusTransition(
        from: 1,
        to: 1,
        id: doc.id.isEmpty ? '<new>' : doc.id,
      );
    }

    final op =
        doc.id.isEmpty ? DocumentOperation.create : DocumentOperation.write;

    if (!_permissionEngine.canPerform(
        operation: op, on: docType, userRoles: userRoles)) {
      throw DocumentEngineError.permissionDenied(
        operation: op.name,
        docType: doc.docType,
      );
    }

    // Pre-save hooks: apply defaults / enforce rules before validation. Run
    // before id assignment so defaults can satisfy required fields. May mutate
    // doc or throw to abort.
    final isNew = doc.id.isEmpty;
    for (final interceptor in _interceptors) {
      await interceptor.beforeSave(this, doc, docType, isNew: isNew);
    }

    // Optimistic concurrency check
    if (doc.id.isNotEmpty) {
      final existing = await _fetchRaw(doc.docType, doc.id);
      if (existing != null &&
          existing.modifiedAt != null &&
          doc.modifiedAt != null) {
        if (existing.modifiedAt!.isAfter(doc.modifiedAt!)) {
          throw DocumentEngineError.concurrencyConflict(doc.id);
        }
      }
    }

    // Assign ID if new
    if (doc.id.isEmpty) {
      final context =
          NamingContext(database: _db, userId: userId, deviceId: deviceId);
      doc.id = await _namingService.resolve(docType, doc, context);
      doc.createdAt = DateTime.now();
    }
    doc.modifiedAt = DateTime.now();
    doc.syncState = SyncState.local;

    // Run validation pipeline
    final result = await _pipeline.run(doc, docType, _db, op, userRoles);
    if (!result.isValid) {
      throw DocumentEngineError.validationFailed(result.errors);
    }

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

    // Append mutation record. Children travel under a reserved `__children`
    // key (each in document_children row shape) so a peer rebuilds the full
    // document — header + line items — on apply, not just the header.
    await _syncEngine.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: previousVersion == null
          ? MutationType.createDocument
          : MutationType.updateDocument,
      docType: doc.docType,
      documentId: doc.id,
      payload: {
        ...doc.toDbRow(),
        '__children': {
          for (final entry in doc.children.entries)
            entry.key: [
              // Build from the saved doc.id, not child.toDbRow(): a child added
              // to a brand-new document still carries the pre-save empty
              // parentId, and the peer would otherwise insert orphaned rows that
              // fetch(doc.id) can't load.
              for (final child in entry.value)
                {
                  'id': child.id,
                  'parent_id': doc.id,
                  'parent_doctype': doc.docType,
                  'table_name': entry.key,
                  'row_index': child.rowIndex,
                  'payload': jsonEncode(child.payload),
                },
            ],
        },
      },
      deviceId: deviceId,
      userId: userId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));

    _emitter.publish(DocumentSavedEvent(
        document: doc, docType: doc.docType, userId: userId));
    return doc;
  }

  /// Applies field changes to an already-submitted (docStatus == 1) document,
  /// permitting ONLY fields declared `allowOnSubmit: true`. This is the
  /// sanctioned escape hatch from submit immutability — used by the ledger
  /// spine to keep an invoice's `outstanding_amount` current as payments settle
  /// it, which [save] forbids (it rejects any write to a submitted doc).
  ///
  /// Any attempt to change a field that is not `allowOnSubmit` throws
  /// [DocumentEngineError.fieldImmutableAfterSubmit]. Emits a
  /// [DocumentSavedEvent] (not Submitted/Cancelled), so it never re-triggers
  /// derivation.
  Future<Document> applyOnSubmitUpdate(
      Document doc, Set<String> userRoles) async {
    final docType = await _registry.get(doc.docType);
    if (docType == null) {
      throw DocumentEngineError.docTypeNotFound(doc.docType);
    }
    if (doc.docStatus != 1) {
      throw DocumentEngineError.invalidDocStatusTransition(
        from: doc.docStatus,
        to: 1,
        id: doc.id.isEmpty ? '<new>' : doc.id,
      );
    }
    if (!_permissionEngine.canPerform(
        operation: DocumentOperation.write,
        on: docType,
        userRoles: userRoles)) {
      throw DocumentEngineError.permissionDenied(
        operation: 'write',
        docType: doc.docType,
      );
    }

    final existing = await _fetchRaw(doc.docType, doc.id);
    if (existing == null) {
      // The row vanished (or was never submitted) between read and write.
      throw DocumentEngineError.concurrencyConflict(doc.id);
    }

    // Permit only allowOnSubmit fields to differ from the stored row.
    final byKey = {for (final f in docType.fields) f.key: f};
    final keys = {...existing.payload.keys, ...doc.payload.keys};
    for (final key in keys) {
      if (jsonEncode(existing.payload[key]) == jsonEncode(doc.payload[key])) {
        continue;
      }
      final field = byKey[key];
      if (field == null || !field.allowOnSubmit) {
        throw DocumentEngineError.fieldImmutableAfterSubmit(
          fieldKey: key,
          docType: doc.docType,
        );
      }
    }

    // Optimistic concurrency.
    if (existing.modifiedAt != null &&
        doc.modifiedAt != null &&
        existing.modifiedAt!.isAfter(doc.modifiedAt!)) {
      throw DocumentEngineError.concurrencyConflict(doc.id);
    }

    doc.docStatus = 1;
    doc.modifiedAt = DateTime.now();
    doc.syncState = SyncState.local;
    await _db.update(
      'documents',
      {
        'payload': jsonEncode(doc.payload),
        'modified_at': doc.modifiedAt!.millisecondsSinceEpoch,
        'sync_state': doc.syncState.name,
      },
      where: 'id = ?',
      whereArgs: [doc.id],
    );

    final diffs = DocumentVersion.computeDiff(existing.payload, doc.payload);
    await _db.insert('audit_log', {
      'id': _uuid.v4(),
      'document_id': doc.id,
      'doctype': doc.docType,
      'action': 'updated',
      'user_id': userId,
      'device_id': deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': jsonEncode({'diffs': diffs.map((d) => d.toJson()).toList()}),
    });
    await _syncEngine.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: MutationType.updateDocument,
      docType: doc.docType,
      documentId: doc.id,
      payload: doc.toDbRow(),
      deviceId: deviceId,
      userId: userId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
    _emitter.publish(DocumentSavedEvent(
        document: doc, docType: doc.docType, userId: userId));
    return doc;
  }

  Future<void> delete(String docType, String id, Set<String> userRoles) async {
    final dt = await _registry.get(docType);
    if (dt == null) throw DocumentEngineError.docTypeNotFound(docType);
    if (!_permissionEngine.canPerform(
        operation: DocumentOperation.delete, on: dt, userRoles: userRoles)) {
      throw DocumentEngineError.permissionDenied(
        operation: 'delete',
        docType: docType,
      );
    }
    // Mirror Swift: a Submitted document can't be deleted directly — the
    // caller must cancel first. We probe the existing row so the error
    // carries the right id for the human message.
    final existing = await _fetchRaw(docType, id);
    if (existing != null && existing.docStatus == 1) {
      throw DocumentEngineError.cannotDeleteSubmitted(id);
    }
    await _db.delete('documents',
        where: 'id = ? AND doctype = ?', whereArgs: [id, docType]);
    await _db
        .delete('document_children', where: 'parent_id = ?', whereArgs: [id]);
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

  Future<Document?> fetch(String docType, String id) => _fetchRaw(docType, id);

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
    List<ListFilter>? predicates,
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
        query += " AND json_extract(payload, '\$.${entry.key}') = ?";
        args.add(entry.value);
      }
    }

    // Typed predicates pushed down to SQL (ADR-036).
    if (predicates != null) {
      for (final p in predicates) {
        final (clause, clauseArgs) = p.toSql();
        query += ' AND $clause';
        args.addAll(clauseArgs);
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

    // Expression-based filtering: the DocType's auto-applied row-access
    // expression (ADR-037) plus any caller whereExpression. Both evaluate per
    // document with the row fields and user (id + roles) in context.
    final docTypeMeta = await _registry.get(docType);
    final rowAccess = docTypeMeta?.rowAccessExpression;
    final expressions = <String>[
      if (rowAccess != null && rowAccess.isNotEmpty) rowAccess,
      if (whereExpression != null && whereExpression.isNotEmpty) whereExpression,
    ];
    if (expressions.isNotEmpty) {
      docs = docs.where((doc) {
        final ctx = EvaluationContext(
          fields: doc.payload,
          user: {'id': userId, 'roles': userRoles?.toList() ?? const []},
        );
        for (final expr in expressions) {
          try {
            if (!_expressionEvaluator.evaluateBool(expr, ctx)) return false;
          } catch (_) {
            return false;
          }
        }
        return true;
      }).toList();
    }

    return docs;
  }

  Future<Document> submit(Document doc, Set<String> userRoles) async {
    final docType = await _registry.get(doc.docType);
    if (docType == null) {
      throw DocumentEngineError.docTypeNotFound(doc.docType);
    }
    if (!docType.isSubmittable) {
      throw DocumentEngineError.notSubmittable(doc.docType);
    }
    if (doc.docStatus != 0) {
      throw DocumentEngineError.invalidDocStatusTransition(
        from: doc.docStatus,
        to: 1,
        id: doc.id,
      );
    }
    if (!_permissionEngine.canPerform(
        operation: DocumentOperation.submit,
        on: docType,
        userRoles: userRoles)) {
      throw DocumentEngineError.permissionDenied(
        operation: 'submit',
        docType: doc.docType,
      );
    }

    // Pre-submit hooks: enforce posting-time rules (e.g. open fiscal year).
    // May throw a DocumentEngineError to block the submission.
    for (final interceptor in _interceptors) {
      await interceptor.beforeSubmit(this, doc, docType);
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
    if (docType == null) {
      throw DocumentEngineError.docTypeNotFound(doc.docType);
    }
    if (doc.docStatus != 1) {
      throw DocumentEngineError.invalidDocStatusTransition(
        from: doc.docStatus,
        to: 2,
        id: doc.id,
      );
    }
    if (!_permissionEngine.canPerform(
        operation: DocumentOperation.delete,
        on: docType,
        userRoles: userRoles)) {
      throw DocumentEngineError.permissionDenied(
        operation: 'cancel',
        docType: doc.docType,
      );
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
    if (docType == null) {
      throw DocumentEngineError.docTypeNotFound(original.docType);
    }
    if (original.docStatus != 2) {
      throw DocumentEngineError.invalidDocStatusTransition(
        from: original.docStatus,
        to: 0,
        id: original.id,
      );
    }
    if (!_permissionEngine.canPerform(
        operation: DocumentOperation.amend,
        on: docType,
        userRoles: userRoles)) {
      throw DocumentEngineError.permissionDenied(
        operation: 'amend',
        docType: original.docType,
      );
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

/// A hook into the document lifecycle, run by [DocumentEngine] before a write is
/// committed. Apps register interceptors (via the `interceptors:` constructor
/// argument) to apply field defaults or enforce cross-document posting rules
/// without forking the engine — the seam the Swift app had as explicit save
/// stages.
///
/// [beforeSave] runs inside [DocumentEngine.save], before id assignment and
/// validation, so an implementation may fill defaults that then satisfy
/// required-field checks. [beforeSubmit] runs inside [DocumentEngine.submit],
/// just before the status flips to 1. Either method may throw a
/// [DocumentEngineError] to abort the operation.
///
/// The owning [engine] is passed so a hook can read other documents (e.g. the
/// Company or the open Fiscal Year). Do not call back into save/submit for the
/// document being processed — that re-enters the same lifecycle.
abstract class DocumentInterceptor {
  const DocumentInterceptor();

  /// Invoked before a draft is persisted. [isNew] is true on create (no id yet).
  /// Mutating [doc] here (e.g. filling blank defaults) is the intended use.
  Future<void> beforeSave(
    DocumentEngine engine,
    Document doc,
    DocType docType, {
    required bool isNew,
  }) async {}

  /// Invoked before a document transitions to submitted (docStatus 1). Intended
  /// for posting-time validation; throw to block the submission.
  Future<void> beforeSubmit(
    DocumentEngine engine,
    Document doc,
    DocType docType,
  ) async {}
}
