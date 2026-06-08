import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cloud_adapter.dart';
import 'mutation_record.dart';

/// Filesystem-backed [CloudAdapter] (ADR-047): a reference, genuinely
/// peer-to-peer adapter that uses a shared directory as the "cloud".
///
/// Useful for:
/// - iCloud Drive / Dropbox / OneDrive / SMB shares as the transport,
/// - LAN sync via a shared volume,
/// - tests where two adapters point at the same temp directory to simulate
///   two devices.
///
/// There is no central server. Each device writes its own mutations into its
/// own subdirectory (`<root>/<deviceId>/<seq>.json`) and pulls peer
/// subdirectories on each [pull]. Cross-peer ordering is by a per-peer
/// monotonic sequence; the adapter mints a synthetic, monotonic global
/// sequence which it hands back as each mutation's [MutationRecord.syncVersion]
/// so the document store's `sync_version` and the engine's cursors keep working
/// unchanged.
///
/// Uses `dart:io`, so it runs on desktop and mobile but not the web. Construct
/// via [create], which provisions directories and loads persisted state.
class FileSystemCloudAdapter implements CloudAdapter {
  final Directory _root;
  final String _localDeviceId;

  /// Local push counter — monotonic per device. The N-th mutation pushed from
  /// this device lands at `<root>/<localDeviceId>/<N>.json`.
  int _localPushSequence;

  /// Per-peer cursor: the max sequence already ingested from each peer device.
  /// Persists across process restarts.
  final Map<String, int> _peerCursors;

  /// Synthetic global counter handed back as [MutationRecord.syncVersion].
  int _globalReceiveSequence;

  /// Serialises [push]/[pull] so interleaved awaits can't corrupt shared state
  /// or the on-disk envelopes. (Dart is single-threaded, but async ops can
  /// still interleave at await points.)
  Future<void> _queue = Future<void>.value();

  static const String _stateFileName = '.adapter-state.json';

  FileSystemCloudAdapter._({
    required Directory root,
    required String localDeviceId,
    required int localPushSequence,
    required Map<String, int> peerCursors,
    required int globalReceiveSequence,
  })  : _root = root,
        _localDeviceId = localDeviceId,
        _localPushSequence = localPushSequence,
        _peerCursors = peerCursors,
        _globalReceiveSequence = globalReceiveSequence;

  /// Provision `<root>/<localDeviceId>/` and load any persisted adapter state.
  static Future<FileSystemCloudAdapter> create({
    required Directory root,
    required String localDeviceId,
  }) async {
    await root.create(recursive: true);
    final myDir = Directory(p.join(root.path, localDeviceId));
    await myDir.create(recursive: true);

    var localPushSequence = 0;
    var peerCursors = <String, int>{};
    var globalReceiveSequence = 0;

    final stateFile = File(p.join(myDir.path, _stateFileName));
    if (await stateFile.exists()) {
      try {
        final decoded =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        localPushSequence = (decoded['localPushSequence'] as num?)?.toInt() ?? 0;
        globalReceiveSequence =
            (decoded['globalReceiveSequence'] as num?)?.toInt() ?? 0;
        final cursors = decoded['peerCursors'];
        if (cursors is Map) {
          peerCursors = cursors.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()));
        }
      } catch (_) {
        // Corrupt or partial state file — start fresh rather than wedging sync.
      }
    }

    return FileSystemCloudAdapter._(
      root: root,
      localDeviceId: localDeviceId,
      localPushSequence: localPushSequence,
      peerCursors: peerCursors,
      globalReceiveSequence: globalReceiveSequence,
    );
  }

  // CloudAdapter

  @override
  Future<void> push(List<MutationRecord> mutations) =>
      _synchronized(() => _push(mutations));

  @override
  Future<List<MutationRecord>> pull(String? afterSyncVersion) =>
      _synchronized(() => _pull(afterSyncVersion));

  /// No-op: filesystem mutations are durable files; there is nothing to ack and
  /// peers still need to read them, so they are never deleted here.
  @override
  Future<void> acknowledge(List<String> mutationIds) async {}

  // Core (runs inside the serialisation queue)

  Future<void> _push(List<MutationRecord> mutations) async {
    final myDir = Directory(p.join(_root.path, _localDeviceId));
    await myDir.create(recursive: true);

    for (final mutation in mutations) {
      _localPushSequence += 1;
      final envelope = <String, dynamic>{
        'sourceDeviceId': _localDeviceId,
        'peerSequence': _localPushSequence,
        'record': mutation.toDbRow(),
      };
      // Local push order is also this device's authoritative version for the
      // pushed record.
      mutation.syncVersion = _localPushSequence.toString();
      await _writeAtomic(
        File(p.join(myDir.path, '$_localPushSequence.json')),
        jsonEncode(envelope),
      );
    }

    await _persistState();
  }

  Future<List<MutationRecord>> _pull(String? afterSyncVersion) async {
    final cutoff =
        afterSyncVersion == null ? 0 : int.tryParse(afterSyncVersion) ?? 0;
    final collected = <MutationRecord>[];

    final List<FileSystemEntity> entries;
    try {
      entries = await _root.list(followLinks: false).toList();
    } on FileSystemException {
      return const [];
    }

    // Deterministic peer order so the global sequence we mint is reproducible
    // across runs against the same shared root.
    final peerDirs = entries.whereType<Directory>().toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (final peerDir in peerDirs) {
      final peer = p.basename(peerDir.path);
      if (peer == _localDeviceId) continue;

      final peerCursor = _peerCursors[peer] ?? 0;

      // Each mutation file is `<peerSequence>.json`. Filter by cursor, sort by
      // sequence.
      final pending = <(int, File)>[];
      try {
        await for (final entry in peerDir.list(followLinks: false)) {
          if (entry is! File || p.extension(entry.path) != '.json') continue;
          final seq = int.tryParse(p.basenameWithoutExtension(entry.path));
          if (seq != null && seq > peerCursor) pending.add((seq, entry));
        }
      } on FileSystemException {
        continue;
      }
      pending.sort((a, b) => a.$1.compareTo(b.$1));

      for (final (peerSeq, file) in pending) {
        final Map<String, dynamic> envelope;
        try {
          envelope = jsonDecode(await file.readAsString())
              as Map<String, dynamic>;
        } catch (_) {
          continue; // Skip unreadable/partial files; retry on a later pull.
        }
        final record = envelope['record'];
        if (record is! Map) continue;

        _globalReceiveSequence += 1;
        if (_globalReceiveSequence > cutoff) {
          final mutation =
              MutationRecord.fromDbRow(Map<String, dynamic>.from(record));
          mutation.syncVersion = _globalReceiveSequence.toString();
          collected.add(mutation);
        }
        _peerCursors[peer] = peerSeq;
      }
    }

    await _persistState();
    return collected;
  }

  // Inspection

  int get localPushSequence => _localPushSequence;
  int peerCursor(String peerDeviceId) => _peerCursors[peerDeviceId] ?? 0;
  int get globalReceiveSequence => _globalReceiveSequence;

  // Persistence

  Future<void> _persistState() async {
    final myDir = Directory(p.join(_root.path, _localDeviceId));
    await myDir.create(recursive: true);
    final state = <String, dynamic>{
      'localPushSequence': _localPushSequence,
      'peerCursors': _peerCursors,
      'globalReceiveSequence': _globalReceiveSequence,
    };
    await _writeAtomic(
      File(p.join(myDir.path, _stateFileName)),
      const JsonEncoder.withIndent('  ').convert(state),
    );
  }

  /// Write via a temp file + rename so readers (peers) never observe a partial
  /// file.
  Future<void> _writeAtomic(File file, String contents) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
