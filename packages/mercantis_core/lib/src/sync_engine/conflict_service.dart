import 'dart:convert';

import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../document_engine/document.dart';
import 'mutation_record.dart';
import 'sync_engine.dart';

/// A document stuck in `sync_state=conflict`: the local version and the
/// remote candidate that lost the version check, side by side (Phase 0.10,
/// gap analysis §8-C6).
class SyncConflict {
  const SyncConflict({
    required this.documentId,
    required this.docType,
    required this.remote,
    required this.detectedAt,
    this.local,
  });

  final String documentId;
  final String docType;

  /// The remote mutation the resolver refused to auto-apply.
  final MutationRecord remote;

  final DateTime detectedAt;

  /// The local document as it stands now; null if it was deleted since.
  final Document? local;

  DateTime? get localModifiedAt => local?.modifiedAt ?? local?.createdAt;
  DateTime get remoteModifiedAt => remote.localTimestamp;
}

/// Lists and resolves sync conflicts. Resolution is deliberately blunt —
/// whole-document keep-mine or take-theirs, chosen by the user; field-level
/// merge is out of scope. Server-posted state (official numbers, ledgers)
/// never conflicts here: posted documents replicate one way from the
/// posting authority.
class ConflictService {
  ConflictService({
    required Database database,
    required SyncEngine syncEngine,
    required this.deviceId,
    required this.userId,
  })  : _db = database,
        _syncEngine = syncEngine;

  final Database _db;
  final SyncEngine _syncEngine;
  final String deviceId;
  final String userId;

  static const _uuid = Uuid();

  Future<int> count() async {
    final rows =
        await _db.rawQuery('SELECT COUNT(*) AS c FROM sync_conflicts');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<List<SyncConflict>> listConflicts() async {
    final rows =
        await _db.query('sync_conflicts', orderBy: 'detected_at DESC');
    final conflicts = <SyncConflict>[];
    for (final row in rows) {
      final MutationRecord remote;
      try {
        remote = MutationRecord.fromWireJson(
            (jsonDecode(row['remote_mutation'] as String) as Map)
                .cast<String, dynamic>());
      } catch (_) {
        continue; // Unreadable candidate — nothing to offer for this row.
      }
      final localRows = await _db.query(
        'documents',
        where: 'id = ? AND doctype = ?',
        whereArgs: [row['document_id'], row['doctype']],
      );
      conflicts.add(SyncConflict(
        documentId: row['document_id'] as String,
        docType: row['doctype'] as String,
        remote: remote,
        detectedAt:
            DateTime.fromMillisecondsSinceEpoch(row['detected_at'] as int),
        local:
            localRows.isEmpty ? null : Document.fromDbRow(localRows.first),
      ));
    }
    return conflicts;
  }

  /// Keep the local version: clear the conflict and re-enqueue the local
  /// document (with a fresh timestamp, so last-write-wins on other devices
  /// favours it) as an ordinary update mutation.
  Future<void> keepMine(String docType, String documentId) async {
    final rows = await _db.query(
      'documents',
      where: 'id = ? AND doctype = ?',
      whereArgs: [documentId, docType],
    );
    if (rows.isEmpty) {
      await _deleteConflict(docType, documentId);
      return;
    }

    final now = DateTime.now();
    await _db.update(
      'documents',
      {
        'sync_state': SyncState.local.name,
        'modified_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ? AND doctype = ?',
      whereArgs: [documentId, docType],
    );

    // Same envelope the document engine ships on save: header row plus
    // children under __children, so peers rebuild the full document.
    final childRows = await _db.query(
      'document_children',
      where: 'parent_id = ?',
      whereArgs: [documentId],
      orderBy: 'row_index ASC',
    );
    final children = <String, List<Map<String, dynamic>>>{};
    for (final child in childRows) {
      children
          .putIfAbsent('${child['table_name']}', () => [])
          .add(Map<String, dynamic>.from(child));
    }
    await _syncEngine.appendMutation(MutationRecord(
      id: _uuid.v4(),
      type: MutationType.updateDocument,
      docType: docType,
      documentId: documentId,
      payload: {
        ...rows.first,
        'sync_state': SyncState.local.name,
        'modified_at': now.millisecondsSinceEpoch,
        '__children': children,
      },
      deviceId: deviceId,
      userId: userId,
      localTimestamp: now,
      status: MutationStatus.pending,
    ));

    await _deleteConflict(docType, documentId);
  }

  /// Take the remote version: abandon un-pushed local edits to the document
  /// and force-apply the stored remote candidate.
  Future<void> takeTheirs(String docType, String documentId) async {
    final rows = await _db.query(
      'sync_conflicts',
      where: 'document_id = ? AND doctype = ?',
      whereArgs: [documentId, docType],
    );
    if (rows.isEmpty) return;
    final remote = MutationRecord.fromWireJson(
        (jsonDecode(rows.first['remote_mutation'] as String) as Map)
            .cast<String, dynamic>());

    // Local edits that haven't shipped would resurrect "mine" on the next
    // push — the user just chose otherwise.
    await _db.delete(
      'sync_queue',
      where: 'document_id = ? AND doctype = ? AND status IN (?, ?)',
      whereArgs: [
        documentId,
        docType,
        MutationStatus.pending.name,
        MutationStatus.failed.name,
      ],
    );

    await _syncEngine.forceApplyRemoteMutation(remote);
    await _deleteConflict(docType, documentId);
  }

  Future<void> _deleteConflict(String docType, String documentId) =>
      _db.delete(
        'sync_conflicts',
        where: 'document_id = ? AND doctype = ?',
        whereArgs: [documentId, docType],
      );
}
