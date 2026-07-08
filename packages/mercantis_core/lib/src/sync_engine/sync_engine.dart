import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common/sqflite.dart';
import '../document_engine/document.dart';
import '../files/attachment_store.dart';
import '../metadata/metadata_registry.dart';
import 'cloud_adapter.dart';
import 'conflict_resolver.dart';
import 'http_cloud_adapter.dart' show CloudHttpException;
import 'mutation_record.dart';

enum SyncEngineState { idle, pushing, pulling, error }

class SyncEngine {
  final Database _db;
  final MetadataRegistry _registry;
  final CloudAdapter _cloudAdapter;
  final ConflictResolver _resolver;

  /// Byte store for attachment sync (ADR-048). When present, attachment
  /// mutations carry their bytes through the cloud adapter's blob channel:
  /// pushed before the metadata mutation, fetched on apply, and backfilled by
  /// [reconcileBlobs]. When null the engine still replicates attachment
  /// metadata, but bytes stay device-local.
  final AttachmentStore? _attachmentStore;

  final _stateController = StreamController<SyncEngineState>.broadcast();
  Stream<SyncEngineState> get state => _stateController.stream;

  SyncEngine({
    required Database database,
    required MetadataRegistry registry,
    CloudAdapter? cloudAdapter,
    ConflictResolver? resolver,
    AttachmentStore? attachmentStore,
  })  : _db = database,
        _registry = registry,
        _cloudAdapter = cloudAdapter ?? const NoOpCloudAdapter(),
        _resolver = resolver ?? ConflictResolver(),
        _attachmentStore = attachmentStore;

  Future<void> appendMutation(MutationRecord record) async {
    await _db.insert(
      'sync_queue',
      record.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> pushPendingMutations() async {
    _stateController.add(SyncEngineState.pushing);
    try {
      final rows = await _db.query(
        'sync_queue',
        where: 'status = ?',
        whereArgs: [MutationStatus.pending.name],
        orderBy: 'local_timestamp ASC',
      );
      if (rows.isEmpty) {
        _stateController.add(SyncEngineState.idle);
        return;
      }

      final mutations = rows.map(MutationRecord.fromDbRow).toList();
      final ids = mutations.map((m) => m.id).toList();
      await _markStatus(ids, MutationStatus.pushing);

      try {
        // Ship attachment bytes ahead of the metadata mutations that reference
        // them, so a peer that pulls the mutation always finds the blob waiting.
        await _pushBlobsFor(mutations);
        await _cloudAdapter.push(mutations);
      } catch (e) {
        if (_isPermanentRejection(e)) {
          // The server refused the batch for a reason a retry can't change
          // (e.g. 409: a mutation touches an officially posted, immutable
          // document). Re-pending would fail identically every cycle
          // forever, so isolate the poison: push per mutation, quarantine
          // the rejected ones as `failed` for user action, ship the rest.
          await _quarantinePermanentRejections(mutations);
        } else {
          // Transient (network, 5xx): return the batch to `pending` so the
          // next cycle retries it (the retry query only selects pending —
          // rows stuck in `pushing` would never ship again).
          await _markStatus(ids, MutationStatus.pending);
        }
        rethrow;
      }
      await _markStatus(ids, MutationStatus.pushed);
      _stateController.add(SyncEngineState.idle);
    } catch (e) {
      _stateController.add(SyncEngineState.error);
      rethrow;
    }
  }

  Future<void> pullAndApplyRemoteMutations() async {
    _stateController.add(SyncEngineState.pulling);
    try {
      final remoteMutations = await _cloudAdapter.pull(null);
      await applyRemoteMutations(remoteMutations);
      _stateController.add(SyncEngineState.idle);
    } catch (_) {
      _stateController.add(SyncEngineState.error);
    }
  }

  Future<void> applyRemoteMutations(List<MutationRecord> mutations) async {
    for (final mutation in mutations) {
      await _applyMutation(mutation);
    }
  }

  Future<void> _applyMutation(MutationRecord mutation) async {
    // Attachments are not documents: route them before the document load /
    // conflict-resolution path, which keys on the `documents` table.
    if (mutation.type == MutationType.createAttachment) {
      await _applyCreateAttachment(mutation);
      return;
    }
    if (mutation.type == MutationType.deleteAttachment) {
      await _applyDeleteAttachment(mutation);
      return;
    }

    final docType = await _registry.get(mutation.docType);
    final policy = docType?.syncPolicy;

    // Load existing local document
    final rows = await _db.query(
      'documents',
      where: 'id = ? AND doctype = ?',
      whereArgs: [mutation.documentId, mutation.docType],
    );
    final local = rows.isEmpty ? null : Document.fromDbRow(rows.first);

    if (policy != null) {
      final outcome = _resolver.resolve(mutation, local, policy);
      if (outcome == ConflictOutcome.rejectRemote) return;
      if (outcome == ConflictOutcome.requiresManualResolution) {
        // Mark local document as conflict state
        if (local != null) {
          await _db.update(
            'documents',
            {'sync_state': SyncState.conflict.name},
            where: 'id = ?',
            whereArgs: [local.id],
          );
        }
        return;
      }
    }

    // Apply mutation
    switch (mutation.type) {
      case MutationType.createDocument:
      case MutationType.updateDocument:
        final payload = Map<String, dynamic>.from(mutation.payload);
        // Children ride under a reserved key; strip it before writing the
        // header, then rebuild the child rows (only when present, so a header-
        // only update such as an outstanding-amount change leaves them intact).
        final children = payload.remove('__children');
        await _db.insert(
          'documents',
          {
            ...payload,
            'sync_state': SyncState.synced.name,
            'sync_version': mutation.syncVersion,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (children is Map) {
          await _db.delete('document_children',
              where: 'parent_id = ?', whereArgs: [mutation.documentId]);
          for (final entry in children.entries) {
            final rows = entry.value;
            if (rows is! List) continue;
            for (final row in rows) {
              if (row is! Map) continue;
              final childPayload = row['payload'];
              await _db.insert(
                'document_children',
                {
                  'id': row['id'],
                  // Fall back to the parent's id for null OR empty — a stale
                  // empty parentId from a pre-save child would orphan the row.
                  'parent_id': (row['parent_id'] is String &&
                          (row['parent_id'] as String).isNotEmpty)
                      ? row['parent_id']
                      : mutation.documentId,
                  'parent_doctype': row['parent_doctype'] ?? mutation.docType,
                  'table_name': row['table_name'] ?? entry.key,
                  'row_index': row['row_index'] ?? 0,
                  'payload': childPayload is String
                      ? childPayload
                      : jsonEncode(childPayload),
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
      case MutationType.deleteDocument:
        await _db.delete(
          'documents',
          where: 'id = ? AND doctype = ?',
          whereArgs: [mutation.documentId, mutation.docType],
        );
      case MutationType.submitDocument:
        await _db.update(
          'documents',
          {'docstatus': 1, 'sync_state': SyncState.synced.name},
          where: 'id = ?',
          whereArgs: [mutation.documentId],
        );
      case MutationType.cancelDocument:
        await _db.update(
          'documents',
          {'docstatus': 2, 'sync_state': SyncState.synced.name},
          where: 'id = ?',
          whereArgs: [mutation.documentId],
        );
      default:
        break;
    }
  }

  // Attachment sync (ADR-048)

  /// Push the bytes for every `createAttachment` mutation in [mutations] to the
  /// blob channel. Read from the local store by storage path; a missing local
  /// file (shouldn't happen for our own creates) is skipped rather than fatal.
  Future<void> _pushBlobsFor(List<MutationRecord> mutations) async {
    final store = _attachmentStore;
    if (store == null) return;
    for (final mutation in mutations) {
      if (mutation.type != MutationType.createAttachment) continue;
      final sha = mutation.payload['sha256'];
      final storagePath = mutation.payload['storage_path'];
      if (sha is! String || storagePath is! String) continue;
      if (!store.exists(storagePath)) continue;
      await _cloudAdapter.pushBlob(sha, store.read(storagePath));
    }
  }

  Future<void> _applyCreateAttachment(MutationRecord mutation) async {
    await _db.insert(
      'attachments',
      Map<String, Object?>.from(mutation.payload),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _ensureBlobPresent(mutation.payload);
  }

  Future<void> _applyDeleteAttachment(MutationRecord mutation) async {
    await _db.delete('attachments',
        where: 'id = ?', whereArgs: [mutation.documentId]);
    // Bytes under `_blobs/<sha>` are content-addressed and may be shared by
    // other attachments, so they are left in place; only the local store copy
    // (keyed by document/attachment id) is removed.
    final store = _attachmentStore;
    final storagePath = mutation.payload['storage_path'];
    if (store != null && storagePath is String) store.delete(storagePath);
  }

  /// Materialise an attachment's bytes locally if they aren't already present,
  /// fetching from the blob channel and verifying the SHA-256. A blob that
  /// hasn't propagated yet is left for [reconcileBlobs] to backfill.
  Future<void> _ensureBlobPresent(Map<String, dynamic> row) async {
    final store = _attachmentStore;
    if (store == null) return;
    final storagePath = row['storage_path'];
    final sha = row['sha256'];
    final documentId = row['document_id'];
    final attachmentId = row['id'];
    if (storagePath is! String ||
        sha is! String ||
        documentId is! String ||
        attachmentId is! String) {
      return;
    }
    if (store.exists(storagePath)) return;
    final bytes = await _cloudAdapter.pullBlob(sha);
    if (bytes == null) return;
    if (AttachmentStore.sha256Hex(bytes) != sha) return; // integrity guard
    store.write(documentId, attachmentId, bytes);
  }

  /// Backfill any attachment whose metadata has synced but whose bytes are
  /// still missing locally (e.g. the blob hadn't propagated when the mutation
  /// was applied). Safe to call after every pull; a no-op without a store.
  Future<void> reconcileBlobs() async {
    if (_attachmentStore == null) return;
    final rows = await _db.query('attachments');
    for (final row in rows) {
      await _ensureBlobPresent(row);
    }
  }

  Future<void> _markStatus(List<String> ids, MutationStatus status) async {
    for (final id in ids) {
      await _db.update(
        'sync_queue',
        {'status': status.name},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// A 4xx the server will answer identically on every retry. 408 (timeout)
  /// and 429 (rate limit) stay transient by definition.
  static bool _isPermanentRejection(Object e) =>
      e is CloudHttpException &&
      e.statusCode >= 400 &&
      e.statusCode < 500 &&
      e.statusCode != 408 &&
      e.statusCode != 429;

  /// Fallback path after a batch-level permanent rejection: the server
  /// refuses whole batches, so it can't say WHICH mutation poisoned this
  /// one. Re-push one by one — accepted mutations mark `pushed`, permanent
  /// rejections mark `failed` (quarantined until [requeueFailed]), and a
  /// transient error mid-way re-pends the not-yet-attempted remainder.
  Future<void> _quarantinePermanentRejections(
      List<MutationRecord> mutations) async {
    for (var i = 0; i < mutations.length; i++) {
      final mutation = mutations[i];
      try {
        await _cloudAdapter.push([mutation]);
        await _markStatus([mutation.id], MutationStatus.pushed);
      } catch (e) {
        if (_isPermanentRejection(e)) {
          await _markStatus([mutation.id], MutationStatus.failed);
        } else {
          // Transport dropped mid-quarantine: everything not yet attempted
          // (including this one) retries next cycle.
          await _markStatus(
            [for (final m in mutations.skip(i)) m.id],
            MutationStatus.pending,
          );
          return;
        }
      }
    }
  }

  Future<int> pendingCount() async {
    final result = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue WHERE status = ?',
        [MutationStatus.pending.name]);
    return (result.first['count'] as int?) ?? 0;
  }

  /// Mutations quarantined by a permanent server rejection — visible so the
  /// UI can surface them for user action instead of hiding a silent stall.
  Future<int> failedCount() async {
    final result = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue WHERE status = ?',
        [MutationStatus.failed.name]);
    return (result.first['count'] as int?) ?? 0;
  }

  /// Returns quarantined mutations to `pending` so the next push retries
  /// them — the explicit user action after fixing what the server rejected.
  Future<int> requeueFailed() async {
    return _db.update(
      'sync_queue',
      {'status': MutationStatus.pending.name},
      where: 'status = ?',
      whereArgs: [MutationStatus.failed.name],
    );
  }

  void dispose() => _stateController.close();
}
