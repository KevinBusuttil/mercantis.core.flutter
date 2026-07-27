import 'dart:convert';
import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../metadata/doc_type.dart';
import '../metadata/field_definition.dart';
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
import '../identity/execution_context.dart';
import 'document.dart';
import 'document_engine_error.dart';
import 'document_version.dart';
import 'list_filter.dart';
import 'unit_of_work.dart';
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

  /// The effective per-operation identity. When a caller supplies a [context] it
  /// is the authority (its roles drive permission checks — an explicit context
  /// with no roles is denied, fail-closed); otherwise a legacy fallback carries
  /// the instance identity plus the call's [userRoles], preserving pre-C1
  /// behaviour exactly.
  ExecutionContext _resolve(ExecutionContext? context, Set<String> userRoles) =>
      context ??
      ExecutionContext.legacy(
          userId: userId, deviceId: deviceId, roles: userRoles);

  /// Authorises [op] under [ctx]: a system context bypasses gating; otherwise the
  /// permission engine is consulted with the context's roles.
  bool _authorized(DocumentOperation op, DocType docType, ExecutionContext ctx) =>
      ctx.isSystemOperation ||
      _permissionEngine.canPerform(
          operation: op, on: docType, userRoles: ctx.roles);

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

  Future<Document> save(Document doc, Set<String> userRoles,
      {ExecutionContext? context}) async {
    final ctx = _resolve(context, userRoles);
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

    if (!_authorized(op, docType, ctx)) {
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

    // Declarative field derivation (C8): coerce empty numerics to null, fetch
    // `fetchFrom` values from linked documents, and recompute formula fields —
    // on the header and every child row — so what validates and persists is the
    // derived document, not the raw input.
    await _deriveFields(doc, docType);

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
      final namingContext = NamingContext(
          database: _db, userId: ctx.operatorId, deviceId: ctx.deviceId);
      doc.id = await _namingService.resolve(docType, doc, namingContext);
      doc.createdAt = DateTime.now();
    }
    doc.modifiedAt = DateTime.now();
    doc.syncState = SyncState.local;

    // Run validation pipeline (incl. recursive child-row validation — C3)
    final result = await _pipeline.run(doc, docType, _db, op, ctx.roles,
        childDocTypeProvider: _registry.get);
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

    // Write audit log entry. Parent-field diffs plus child-row diffs (C3 / P0.6)
    // so a document's line-item edits are captured in version history too.
    final diffs = previousVersion != null
        ? <FieldDiff>[
            ...DocumentVersion.computeDiff(previousVersion.payload, doc.payload),
            ...DocumentVersion.computeChildDiffs(
                previousVersion.children, doc.children),
          ]
        : <FieldDiff>[];
    await _db.insert('audit_log', {
      'id': _uuid.v4(),
      'document_id': doc.id,
      'doctype': doc.docType,
      'action': previousVersion == null ? 'created' : 'updated',
      'user_id': ctx.operatorId,
      'device_id': ctx.deviceId,
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
      deviceId: ctx.deviceId,
      userId: ctx.operatorId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));

    _emitter.publish(DocumentSavedEvent(
        document: doc, docType: doc.docType, userId: ctx.operatorId));
    return doc;
  }

  // MARK: declarative field derivation (C8)

  /// Field types whose payload value is normalized to a number on save.
  static const Set<FieldType> _numericFieldTypes = {
    FieldType.integer,
    FieldType.float,
    FieldType.currency,
    FieldType.percent,
    FieldType.duration,
    FieldType.rating,
  };

  /// The numeric types stored as whole numbers (duration is seconds, rating
  /// is stars).
  static const Set<FieldType> _intFieldTypes = {
    FieldType.integer,
    FieldType.duration,
    FieldType.rating,
  };

  /// Runs the three derivation passes over the header and each child row, in
  /// order: scalar type normalization → fetchFrom → formula recompute (so a
  /// formula can consume a freshly fetched or normalized value).
  Future<void> _deriveFields(Document doc, DocType docType) async {
    Future<void> derive(Map<String, dynamic> payload, DocType dt) async {
      _normalizeScalars(payload, dt);
      await _applyFetchFrom(payload, dt);
      _applyFormulas(payload, dt);
    }

    await derive(doc.payload, docType);
    for (final entry in doc.children.entries) {
      final childType = await _childTypeForTableField(docType, entry.key);
      if (childType == null) continue;
      for (final row in entry.value) {
        await derive(row.payload, childType);
      }
    }
  }

  /// Normalizes scalar payload values to their field's canonical Dart type,
  /// so every consumer (forms, reports, expressions, exports, sync peers)
  /// reads one shape. Writers are inconsistent — the UI sends int/num,
  /// while seeders, interceptors, and imports send '1'/'0' and numeric
  /// strings — and before this pass whatever shape was written is what
  /// persisted.
  ///
  /// check → int 0/1 (from bool, num, '1'/'0'/'true'/'false'); numerics →
  /// num, whole-number types → int; an empty string in a numeric field
  /// becomes `null` (it would otherwise persist as `""` and break numeric
  /// parsing / SQL comparisons). Anything unrecognized is left untouched
  /// for validation to flag.
  void _normalizeScalars(Map<String, dynamic> payload, DocType dt) {
    for (final f in dt.fields) {
      final v = payload[f.key];
      if (v == null) continue;
      if (f.type == FieldType.check) {
        if (v is bool) {
          payload[f.key] = v ? 1 : 0;
        } else if (v is num) {
          payload[f.key] = v == 0 ? 0 : 1;
        } else if (v is String) {
          switch (v.trim().toLowerCase()) {
            case '1' || 'true':
              payload[f.key] = 1;
            case '0' || 'false' || '':
              payload[f.key] = 0;
          }
        }
        continue;
      }
      if (!_numericFieldTypes.contains(f.type)) continue;
      final wantsInt = _intFieldTypes.contains(f.type);
      if (v is String) {
        if (v.trim().isEmpty) {
          payload[f.key] = null;
          continue;
        }
        final parsed = num.tryParse(v.trim());
        if (parsed == null) continue;
        payload[f.key] =
            wantsInt && parsed % 1 == 0 ? parsed.toInt() : parsed;
      } else if (v is num && wantsInt && v is! int && v % 1 == 0) {
        payload[f.key] = v.toInt();
      }
    }
  }

  /// Populates every `fetchFrom` field from the linked document it references.
  Future<void> _applyFetchFrom(Map<String, dynamic> payload, DocType dt) async {
    for (final f in dt.fields) {
      final spec = f.fetchFrom;
      if (spec == null || spec.isEmpty) continue;
      final dot = spec.indexOf('.');
      if (dot <= 0 || dot >= spec.length - 1) continue;
      final linkKey = spec.substring(0, dot);
      final sourceKey = spec.substring(dot + 1);
      final linkValue = payload[linkKey];
      if (linkValue == null || linkValue == '') continue;
      final linkField = _fieldByKey(dt, linkKey);
      final targetDocType = linkField?.linkDocType;
      if (targetDocType == null) continue;
      final linked = await _fetchRaw(targetDocType, linkValue.toString());
      if (linked == null) continue;
      payload[f.key] = linked.payload[sourceKey];
    }
  }

  /// Recomputes every `formulaExpression` field against the (already coerced +
  /// fetched) payload. An expression that throws leaves the prior value intact.
  void _applyFormulas(Map<String, dynamic> payload, DocType dt) {
    for (final f in dt.fields) {
      final expr = f.formulaExpression;
      if (expr == null || expr.isEmpty) continue;
      try {
        final value = _expressionEvaluator.evaluateValue(
            expr, EvaluationContext(fields: payload));
        if (value != null) payload[f.key] = value;
      } catch (_) {
        // Leave the existing value when the formula can't be evaluated.
      }
    }
  }

  static FieldDefinition? _fieldByKey(DocType dt, String key) {
    for (final f in dt.fields) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// Resolves the child DocType backing a parent's table field (matched by the
  /// table field's `key`), or null if the field/child type isn't found.
  Future<DocType?> _childTypeForTableField(
      DocType parent, String tableFieldKey) async {
    final field = _fieldByKey(parent, tableFieldKey);
    final childName = field?.tableDocType;
    if (childName == null || childName.isEmpty) return null;
    return _registry.get(childName);
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
  Future<Document> applyOnSubmitUpdate(Document doc, Set<String> userRoles,
      {ExecutionContext? context}) async {
    final ctx = _resolve(context, userRoles);
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
    if (!_authorized(DocumentOperation.write, docType, ctx)) {
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
      'user_id': ctx.operatorId,
      'device_id': ctx.deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': jsonEncode({'diffs': diffs.map((d) => d.toJson()).toList()}),
    });
    await _syncEngine.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: MutationType.updateDocument,
      docType: doc.docType,
      documentId: doc.id,
      payload: doc.toDbRow(),
      deviceId: ctx.deviceId,
      userId: ctx.operatorId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
    _emitter.publish(DocumentSavedEvent(
        document: doc, docType: doc.docType, userId: ctx.operatorId));
    return doc;
  }

  Future<void> delete(String docType, String id, Set<String> userRoles,
      {ExecutionContext? context}) async {
    final ctx = _resolve(context, userRoles);
    final dt = await _registry.get(docType);
    if (dt == null) throw DocumentEngineError.docTypeNotFound(docType);
    if (!_authorized(DocumentOperation.delete, dt, ctx)) {
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
      deviceId: ctx.deviceId,
      userId: ctx.operatorId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
    await _auditLifecycle('deleted', docType, id, ctx);
    _emitter.publish(DocumentDeletedEvent(
        documentId: id, docType: docType, userId: ctx.operatorId));
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
    ExecutionContext? context,
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
      final opId = context?.operatorId ?? userId;
      final roles = context?.roles.toList() ?? userRoles?.toList() ?? const [];
      docs = docs.where((doc) {
        final ctx = EvaluationContext(
          fields: doc.payload,
          user: {'id': opId, 'roles': roles},
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

  /// Submits a document. When [inTransaction] is supplied, the status flip and
  /// the callback's writes (posting batches, ledger rows, audit) commit in the
  /// SAME transaction — together, or the whole submit rolls back. This is the
  /// seam that makes "submitted but unposted / partially posted" impossible
  /// (port of Swift's `UnitOfWork`). When omitted, behaviour is unchanged.

  /// One audit row per lifecycle transition. Save writes rich field diffs;
  /// these record THAT the official action happened, by whom, from which
  /// device — previously submit/cancel/amend/delete left no audit trace at
  /// all (only sync mutations and events).
  Future<void> _auditLifecycle(
    String action,
    String docType,
    String documentId,
    ExecutionContext ctx, {
    Map<String, dynamic> detail = const {},
  }) async {
    await _db.insert('audit_log', {
      'id': _uuid.v4(),
      'document_id': documentId,
      'doctype': docType,
      'action': action,
      'user_id': ctx.operatorId,
      'device_id': ctx.deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': jsonEncode({'diffs': [], ...detail}),
    });
  }

  Future<Document> submit(Document doc, Set<String> userRoles,
      {ExecutionContext? context,
      Future<void> Function(UnitOfWork uow)? inTransaction}) async {
    final ctx = _resolve(context, userRoles);
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
    if (!_authorized(DocumentOperation.submit, docType, ctx)) {
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

    final modified = DateTime.now();
    final values = {
      'docstatus': 1,
      'modified_at': modified.millisecondsSinceEpoch,
    };
    if (inTransaction != null) {
      await _db.transaction((txn) async {
        await txn.update('documents', values,
            where: 'id = ?', whereArgs: [doc.id]);
        await inTransaction(UnitOfWork(db: txn, context: ctx));
      });
    } else {
      await _db.update('documents', values, where: 'id = ?', whereArgs: [doc.id]);
    }
    // Mutate the in-memory doc only after the write/transaction commits, so a
    // rolled-back submit leaves the document Draft in memory too.
    doc.docStatus = 1;
    doc.modifiedAt = modified;

    await _syncEngine.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: MutationType.submitDocument,
      docType: doc.docType,
      documentId: doc.id,
      payload: {'id': doc.id, 'doctype': doc.docType},
      deviceId: ctx.deviceId,
      userId: ctx.operatorId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
    await _auditLifecycle('submitted', doc.docType, doc.id, ctx);
    _emitter.publish(DocumentSubmittedEvent(
        document: doc, docType: doc.docType, userId: ctx.operatorId));
    return doc;
  }

  Future<Document> cancel(Document doc, Set<String> userRoles,
      {ExecutionContext? context}) async {
    final ctx = _resolve(context, userRoles);
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
    if (!_authorized(DocumentOperation.cancel, docType, ctx)) {
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
      deviceId: ctx.deviceId,
      userId: ctx.operatorId,
      localTimestamp: DateTime.now(),
      status: MutationStatus.pending,
    ));
    await _auditLifecycle('cancelled', doc.docType, doc.id, ctx);
    _emitter.publish(DocumentCancelledEvent(
        document: doc, docType: doc.docType, userId: ctx.operatorId));
    return doc;
  }

  Future<Document> amend(Document original, Set<String> userRoles,
      {ExecutionContext? context}) async {
    final ctx = _resolve(context, userRoles);
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
    if (!_authorized(DocumentOperation.amend, docType, ctx)) {
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
    final saved = await save(amended, userRoles, context: context);
    await _auditLifecycle('amended', original.docType, original.id, ctx,
        detail: {'amended_to': saved.id});
    return saved;
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
