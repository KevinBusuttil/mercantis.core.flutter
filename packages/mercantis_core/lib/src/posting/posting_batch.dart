import 'package:sqflite_common/sqflite.dart';

import '../storage/mercantis_database.dart';

/// Lifecycle of a posting attempt. Port of Swift `PostingStatus`.
enum PostingStatus {
  /// Reserved but not yet completed (rare in the atomic path; used by recovery).
  pending,

  /// Ledger rows written and committed.
  posted,

  /// Posting failed; the batch records the error for recovery / diagnostics.
  failed,

  /// A later reversal batch has reversed this one.
  reversed;

  static PostingStatus fromName(String? name) {
    for (final s in PostingStatus.values) {
      if (s.name == name) return s;
    }
    return PostingStatus.pending;
  }
}

/// One posting attempt for a source document. Core owns this primitive
/// (identity, status, idempotency, reversal linkage); Hub owns the accounting
/// rules that decide *what* ledger rows a batch contains. Port of Swift
/// `PostingBatch`.
class PostingBatch {
  const PostingBatch({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    this.status = PostingStatus.pending,
    this.version = 1,
    this.errorCode,
    this.errorMessage,
    this.postedAt,
    this.postedBy = '',
    this.reversalOfBatch,
  });

  final String id;
  final String sourceType;
  final String sourceId;
  final PostingStatus status;
  final int version;
  final String? errorCode;
  final String? errorMessage;
  final DateTime? postedAt;
  final String postedBy;

  /// When this batch reverses another, the id of the batch it reverses.
  final String? reversalOfBatch;

  /// Deterministic batch id so retries are idempotent: `POST-<sourceId>-v<version>`.
  static String makeId(String sourceId, {int version = 1}) =>
      'POST-$sourceId-v$version';

  PostingBatch copyWith({
    PostingStatus? status,
    int? version,
    String? errorCode,
    String? errorMessage,
    DateTime? postedAt,
    String? postedBy,
    String? reversalOfBatch,
  }) =>
      PostingBatch(
        id: id,
        sourceType: sourceType,
        sourceId: sourceId,
        status: status ?? this.status,
        version: version ?? this.version,
        errorCode: errorCode ?? this.errorCode,
        errorMessage: errorMessage ?? this.errorMessage,
        postedAt: postedAt ?? this.postedAt,
        postedBy: postedBy ?? this.postedBy,
        reversalOfBatch: reversalOfBatch ?? this.reversalOfBatch,
      );

  Map<String, Object?> toDbRow() => {
        'id': id,
        'source_type': sourceType,
        'source_id': sourceId,
        'status': status.name,
        'version': version,
        'error_code': errorCode,
        'error_message': errorMessage,
        'posted_at': postedAt?.millisecondsSinceEpoch,
        'posted_by': postedBy,
        'reversal_of_batch': reversalOfBatch,
      };

  factory PostingBatch.fromDbRow(Map<String, Object?> row) => PostingBatch(
        id: row['id'] as String? ?? '',
        sourceType: row['source_type'] as String? ?? '',
        sourceId: row['source_id'] as String? ?? '',
        status: PostingStatus.fromName(row['status'] as String?),
        version: (row['version'] as int?) ?? 1,
        errorCode: row['error_code'] as String?,
        errorMessage: row['error_message'] as String?,
        postedAt: row['posted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['posted_at'] as int),
        postedBy: row['posted_by'] as String? ?? '',
        reversalOfBatch: row['reversal_of_batch'] as String?,
      );
}

/// Low-level writer usable inside an existing transaction (the future
/// `UnitOfWork` atomic-with-submit path) or against the database directly.
/// Operates on a [DatabaseExecutor], which both `Database` and `Transaction`
/// implement — so the same idempotency guard + upsert work in either context.
/// Port of Swift `PostingBatchWriter`.
class PostingBatchWriter {
  const PostingBatchWriter._();

  /// Insert or replace a batch row.
  static Future<void> upsert(DatabaseExecutor db, PostingBatch batch) =>
      db.insert('posting_batches', batch.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  /// Whether a batch with [id] already exists — the idempotency guard.
  static Future<bool> exists(DatabaseExecutor db, String id) async {
    final rows = await db.query('posting_batches',
        columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }
}

/// Read/write API for posting batches: idempotency checks, recovery, and the
/// diagnostics queries (failed / pending batches; per-source history). Port of
/// Swift `PostingBatchStore`.
class PostingBatchStore {
  PostingBatchStore(this.database);

  final MercantisDatabase database;

  /// Record (insert or replace) a batch directly. The atomic-with-submit path
  /// (via `UnitOfWork`, pending C1) instead routes through [PostingBatchWriter]
  /// inside the document's write transaction.
  Future<void> upsert(PostingBatch batch) =>
      PostingBatchWriter.upsert(database.db, batch);

  Future<PostingBatch?> batch(String id) async {
    final rows = await database.db.query('posting_batches',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : PostingBatch.fromDbRow(rows.first);
  }

  Future<bool> exists(String id) =>
      PostingBatchWriter.exists(database.db, id);

  /// All batches for a source document, oldest first (by version).
  Future<List<PostingBatch>> batchesForSource(
      String sourceType, String sourceId) async {
    final rows = await database.db.query('posting_batches',
        where: 'source_type = ? AND source_id = ?',
        whereArgs: [sourceType, sourceId],
        orderBy: 'version ASC');
    return [for (final r in rows) PostingBatch.fromDbRow(r)];
  }

  /// Batches in a given status — backs the "failed postings" / "incomplete
  /// postings" diagnostics.
  Future<List<PostingBatch>> batchesWithStatus(PostingStatus status,
      {int limit = 100}) async {
    final rows = await database.db.query('posting_batches',
        where: 'status = ?',
        whereArgs: [status.name],
        orderBy: 'source_id ASC',
        limit: limit);
    return [for (final r in rows) PostingBatch.fromDbRow(r)];
  }

  /// The current (highest-version) batch for a source document, if any.
  Future<PostingBatch?> currentBatch(
      String sourceType, String sourceId) async {
    final all = await batchesForSource(sourceType, sourceId);
    return all.isEmpty ? null : all.last;
  }
}
