import 'dart:convert';

import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../identity/execution_context.dart';
import '../posting/posting_batch.dart';

/// A handle to an in-flight write transaction plus the [ExecutionContext]
/// driving it. Passed to `DocumentEngine.submit(..., inTransaction:)` so callers
/// (notably the Hub's posting handlers) can write additional rows — posting
/// batches, ledger entries, audit — that **commit atomically** with the
/// document's submit: together, or not at all. Port of Swift `UnitOfWork`.
///
/// The underlying [DatabaseExecutor] is the active transaction; do not capture
/// it beyond the enclosing call.
class UnitOfWork {
  UnitOfWork({required this.db, required this.context});

  /// The active write transaction (a sqflite `Transaction`).
  final DatabaseExecutor db;

  /// Who/what is performing the operation. Posting and audit rows written
  /// through this unit of work attribute to [ExecutionContext.operatorId].
  final ExecutionContext context;

  static const _uuid = Uuid();

  /// Record a posting batch in this transaction. Stamps `postedBy` with the
  /// operator when not already set — the idempotency guard is
  /// [postingBatchExists].
  Future<void> recordPostingBatch(PostingBatch batch) {
    final b =
        batch.postedBy.isEmpty ? batch.copyWith(postedBy: context.operatorId) : batch;
    return PostingBatchWriter.upsert(db, b);
  }

  /// Whether a posting batch with [id] already exists — the idempotency guard
  /// for re-fired / replayed posting in this transaction.
  Future<bool> postingBatchExists(String id) =>
      PostingBatchWriter.exists(db, id);

  /// Execute arbitrary SQL in this transaction (e.g. appending GL / stock /
  /// subledger rows atomically with the source document's submit).
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      db.execute(sql, arguments);

  /// Append an audit row in this transaction, attributed to the operator, so the
  /// trail can't be lost to a crash between the state change and the audit write.
  Future<void> audit({
    required String documentId,
    required String docType,
    required String action,
    String payloadJson = '{}',
  }) =>
      db.insert('audit_log', {
        'id': _uuid.v4(),
        'document_id': documentId,
        'doctype': docType,
        'action': action,
        'user_id': context.operatorId,
        'device_id': context.deviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'payload': payloadJson.isEmpty ? jsonEncode({}) : payloadJson,
      });
}
