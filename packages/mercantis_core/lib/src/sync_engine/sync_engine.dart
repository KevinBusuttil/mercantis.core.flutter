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

      // A document awaiting manual conflict resolution must not ship its
      // local edits — the user may yet pick "theirs", and pushing "mine"
      // first would spread the very version they might discard. Held rows
      // stay pending; resolution clears the conflict and the next cycle
      // ships (keep-mine) or has nothing to ship (take-theirs).
      final conflictRows = await _db.query('sync_conflicts',
          columns: ['doctype', 'document_id']);
      final held = {
        for (final r in conflictRows) '${r['doctype']}|${r['document_id']}',
      };
      final mutations = rows
          .map(MutationRecord.fromDbRow)
          .where((m) => !held.contains('${m.docType}|${m.documentId}'))
          .toList();
      if (mutations.isEmpty) {
        _stateController.add(SyncEngineState.idle);
        return;
      }
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
      await _markDocumentsSynced(mutations);
      _stateController.add(SyncEngineState.idle);
    } catch (e) {
      _stateController.add(SyncEngineState.error);
      rethrow;
    }
  }

  /// A successful push means the local edits are on the server — flip the
  /// affected documents from `local` to `synced`. Without this a document
  /// authored on this device stays `local` forever (its own echoes are
  /// filtered on pull), which would make it indistinguishable from
  /// "edited since last sync" — the signal conflict detection keys on.
  Future<void> _markDocumentsSynced(List<MutationRecord> mutations) async {
    for (final m in mutations) {
      if (m.documentId.isEmpty) continue;
      await _db.update(
        'documents',
        {'sync_state': SyncState.synced.name},
        where: 'id = ? AND doctype = ? AND sync_state = ?',
        whereArgs: [m.documentId, m.docType, SyncState.local.name],
      );
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

  /// Applies [mutation] bypassing conflict resolution — the take-theirs arm
  /// of a manual resolution (Phase 0.10). Only ConflictService should call
  /// this, with a candidate the user explicitly chose.
  Future<void> forceApplyRemoteMutation(MutationRecord mutation) =>
      _applyMutation(mutation, force: true);

  Future<void> _applyMutation(MutationRecord mutation,
      {bool force = false}) async {
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

    if (policy != null && !force) {
      final outcome = _resolver.resolve(mutation, local, policy);
      if (outcome == ConflictOutcome.rejectRemote) return;
      if (outcome == ConflictOutcome.requiresManualResolution) {
        // Both sides "edited" but to the same content — routine for
        // deterministic seed records (every device lays down the same EUR /
        // Main Store / chart of accounts) and harmless everywhere else.
        // Apply as a fast-forward instead of raising ~70 bogus conflicts
        // at a device's first join.
        final equivalent =
            local != null && await _contentEquivalent(mutation, local);
        if (!equivalent) {
          // Mark the local document conflicted AND keep the losing remote
          // candidate (Phase 0.10): without it there is nothing to offer
          // the user as "theirs" — the mutation is gone once the cursor
          // advances.
          if (local != null) {
            await _db.update(
              'documents',
              {'sync_state': SyncState.conflict.name},
              where: 'id = ?',
              whereArgs: [local.id],
            );
            await _db.insert(
              'sync_conflicts',
              {
                'document_id': mutation.documentId,
                'doctype': mutation.docType,
                'remote_mutation': jsonEncode(mutation.toWireJson()),
                'detected_at': DateTime.now().millisecondsSinceEpoch,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          return;
        }
        // Equivalent content falls through to the ordinary apply, which
        // also flips the document to `synced`.
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
        await _applyLifecycleTransition(mutation, docstatus: 1);
      case MutationType.cancelDocument:
        await _applyLifecycleTransition(mutation, docstatus: 2);
      default:
        break;
    }
  }

  /// True when the remote candidate would not change what the user sees:
  /// same business payload, docstatus, and company, and — when the mutation
  /// carries child rows — the same children. Sync bookkeeping (timestamps,
  /// sync_state, sync_version) is ignored, and scalars compare by string
  /// form so a legacy stringly flag equals its normalized int.
  Future<bool> _contentEquivalent(
      MutationRecord mutation, Document local) async {
    if (mutation.type != MutationType.createDocument &&
        mutation.type != MutationType.updateDocument) {
      return false;
    }
    final remotePayload = _decodePayloadMap(mutation.payload['payload']);
    if (remotePayload == null) return false;
    if (!_looselyEqualMaps(remotePayload, local.payload)) return false;
    if ('${mutation.payload['docstatus'] ?? 0}' != '${local.docStatus}') {
      return false;
    }
    if ('${mutation.payload['company'] ?? ''}' != (local.company ?? '')) {
      return false;
    }

    final children = mutation.payload['__children'];
    if (children is! Map) return true;
    final remoteTables = <String, List<Map<String, dynamic>>>{};
    for (final entry in children.entries) {
      final rows = entry.value;
      if (rows is! List) continue;
      final list = <Map<String, dynamic>>[];
      for (final row in rows) {
        if (row is! Map) return false;
        list.add(_decodePayloadMap(row['payload']) ?? const {});
      }
      if (list.isNotEmpty) remoteTables['${entry.key}'] = list;
    }
    final localRows = await _db.query(
      'document_children',
      where: 'parent_id = ?',
      whereArgs: [local.id],
      orderBy: 'row_index ASC',
    );
    final localTables = <String, List<Map<String, dynamic>>>{};
    for (final row in localRows) {
      localTables
          .putIfAbsent('${row['table_name']}', () => [])
          .add(_decodePayloadMap(row['payload']) ?? const {});
    }
    if (remoteTables.length != localTables.length) return false;
    for (final entry in remoteTables.entries) {
      final localList = localTables[entry.key];
      if (localList == null || localList.length != entry.value.length) {
        return false;
      }
      for (var i = 0; i < localList.length; i++) {
        if (!_looselyEqualMaps(entry.value[i], localList[i])) return false;
      }
    }
    return true;
  }

  static Map<String, dynamic>? _decodePayloadMap(dynamic raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  /// Loose equality: null and absent are the same, scalars compare by
  /// string form, nested maps/lists recurse.
  static bool _looselyEqualMaps(
      Map<String, dynamic> a, Map<String, dynamic> b) {
    for (final k in {...a.keys, ...b.keys}) {
      if (!_looselyEqualValues(a[k], b[k])) return false;
    }
    return true;
  }

  static bool _looselyEqualValues(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      return _looselyEqualMaps(
          a.cast<String, dynamic>(), b.cast<String, dynamic>());
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_looselyEqualValues(a[i], b[i])) return false;
      }
      return true;
    }
    return '${a ?? ''}' == '${b ?? ''}';
  }

  /// Applies a remote submit/cancel. Beyond the docstatus flip, the
  /// mutation's envelope may carry an updated payload — notably the
  /// server-allocated `official_number` a Team posting authority stamps at
  /// submit — which must land locally or the legal document number exists
  /// only server-side. The envelope payload (when present) replaces the
  /// stored one: at submit the document is immutable, so it is by
  /// definition the same payload the client last pushed plus the fields the
  /// authority added.
  Future<void> _applyLifecycleTransition(MutationRecord mutation,
      {required int docstatus}) async {
    final values = <String, Object?>{
      'docstatus': docstatus,
      'sync_state': SyncState.synced.name,
    };
    final envelopePayload = mutation.payload['payload'];
    if (envelopePayload is String && envelopePayload.isNotEmpty) {
      values['payload'] = envelopePayload;
    }
    final modified = mutation.payload['modified_at'];
    if (modified is num) values['modified_at'] = modified.toInt();
    await _db.update(
      'documents',
      values,
      where: 'id = ?',
      whereArgs: [mutation.documentId],
    );
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
        await _markDocumentsSynced([mutation]);
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
