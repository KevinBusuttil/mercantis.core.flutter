import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common/sqflite.dart';
import '../document_engine/document.dart';
import '../metadata/metadata_registry.dart';
import 'cloud_adapter.dart';
import 'conflict_resolver.dart';
import 'mutation_record.dart';

enum SyncEngineState { idle, pushing, pulling, error }

class SyncEngine {
  final Database _db;
  final MetadataRegistry _registry;
  final CloudAdapter _cloudAdapter;
  final ConflictResolver _resolver;

  final _stateController = StreamController<SyncEngineState>.broadcast();
  Stream<SyncEngineState> get state => _stateController.stream;

  SyncEngine({
    required Database database,
    required MetadataRegistry registry,
    CloudAdapter? cloudAdapter,
    ConflictResolver? resolver,
  })  : _db = database,
        _registry = registry,
        _cloudAdapter = cloudAdapter ?? const NoOpCloudAdapter(),
        _resolver = resolver ?? ConflictResolver();

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
      await _markStatus(mutations.map((m) => m.id).toList(),
          MutationStatus.pushing);

      await _cloudAdapter.push(mutations);
      await _markStatus(
          mutations.map((m) => m.id).toList(), MutationStatus.pushed);
      _stateController.add(SyncEngineState.idle);
    } catch (e) {
      _stateController.add(SyncEngineState.error);
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

  Future<int> pendingCount() async {
    final result = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue WHERE status = ?',
        [MutationStatus.pending.name]);
    return (result.first['count'] as int?) ?? 0;
  }

  void dispose() => _stateController.close();
}
