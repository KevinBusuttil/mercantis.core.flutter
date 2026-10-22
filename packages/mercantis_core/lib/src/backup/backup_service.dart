import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

import '../storage/migration_runner.dart';
import 'backup_archive.dart';
import 'backup_crypto.dart';
import 'database_snapshot.dart';

/// Archive path of the database inside a backup.
const backupDatabaseEntry = 'database/mercantis.db';

/// Archive folder of attachment bytes inside a backup.
const backupAttachmentsPrefix = 'attachments/';

/// Archive folder of host configuration files inside a backup.
const backupConfigPrefix = 'config/';

/// What to put in a backup.
class BackupRequest {
  const BackupRequest({
    required this.database,
    required this.factory,
    required this.producer,
    required this.appVersion,
    this.attachmentsRoot,
    this.configFiles = const {},
    this.businessSummary = const {},
  });

  /// The LIVE database. It is never copied byte-for-byte; see
  /// [DatabaseSnapshot].
  final Database database;
  final DatabaseFactory factory;

  /// Product name written to the public header (for example "Neuradix Atlas").
  final String producer;

  /// Host build version, recorded in the manifest.
  final String appVersion;

  /// Root of the attachment byte store, or null when there is none.
  final String? attachmentsRoot;

  /// Non-secret host configuration, by file name (stored under `config/`).
  /// Never put credentials, tokens or the backup passphrase here.
  final Map<String, List<int>> configFiles;

  /// Host-computed business facts (company, document counts, ledger totals)
  /// recorded so a restore can prove it brought back the same books.
  final Map<String, Object?> businessSummary;
}

/// An attachment row whose bytes could not be included.
class MissingAttachment {
  const MissingAttachment(this.id, this.storagePath, this.reason);
  final String id;
  final String storagePath;
  final String reason;

  Map<String, Object?> toJson() =>
      {'id': id, 'storage_path': storagePath, 'reason': reason};
}

/// The result of a finished backup.
class BackupReport {
  const BackupReport({
    required this.path,
    required this.bytes,
    required this.manifest,
    required this.missingAttachments,
  });

  final String path;
  final int bytes;
  final Map<String, Object?> manifest;

  /// Attachments recorded in the books whose files were missing or damaged
  /// on this device when the backup ran. Shown to the user; never silent.
  final List<MissingAttachment> missingAttachments;
}

/// A backup decrypted and verified into a staging folder, not yet installed.
class StagedRestore {
  const StagedRestore({
    required this.header,
    required this.manifest,
    required this.stagingDirectory,
    required this.databasePath,
    required this.attachmentsDirectory,
    required this.configFiles,
    required this.schemaVersion,
    required this.tableCounts,
  });

  final BackupHeader header;
  final Map<String, Object?> manifest;
  final String stagingDirectory;
  final String databasePath;
  final String attachmentsDirectory;
  final Map<String, List<int>> configFiles;
  final int schemaVersion;
  final Map<String, int> tableCounts;

  Map<String, Object?> get businessSummary => Map<String, Object?>.from(
      (manifest['business_summary'] as Map?) ?? const {});

  List<MissingAttachment> get missingAttachments => [
        for (final m in (manifest['missing_attachments'] as List? ?? const []))
          if (m is Map)
            MissingAttachment(
                '${m['id']}', '${m['storage_path']}', '${m['reason']}'),
      ];

  /// Remove the staging folder (cancel before commit).
  void discard() {
    final d = Directory(stagingDirectory);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}

/// Where the live business data lives on this device.
class RestoreTarget {
  const RestoreTarget({
    required this.databasePath,
    required this.attachmentsRoot,
    required this.journalDirectory,
  });

  final String databasePath;
  final String attachmentsRoot;

  /// Holds the restore journal and the replaced data while a restore is in
  /// flight. Must be on the same volume as the data (renames must be atomic).
  final String journalDirectory;
}

/// Steps of [AtlasBackupService.commitRestore], in order. Tests inject a
/// failure at each one to prove an interrupted restore always recovers.
enum RestoreStep {
  journalWritten,
  previousMoved,
  stagedInstalled,
  verified,
  committed,
}

/// The result of a successful restore.
class RestoreOutcome {
  const RestoreOutcome({required this.safetyCopyDirectory});

  /// Where the data that was replaced now lives (kept until the next
  /// restore), or null when the device had no data.
  final String? safetyCopyDirectory;
}

/// What startup recovery found.
enum RestoreRecovery {
  /// No restore was in flight.
  nothingToDo,

  /// A restore was interrupted before it finished; the previous data was put
  /// back exactly as it was.
  rolledBack,

  /// A restore had finished but not cleaned up; cleanup completed.
  completed,
}

/// Thrown by [AtlasBackupService.commitRestore] when the installed data fails
/// verification. The previous data has already been put back.
class RestoreVerificationException implements Exception {
  const RestoreVerificationException(this.problems);
  final List<String> problems;

  @override
  String toString() =>
      'The restored data did not match the backup, so nothing was changed: '
      '${problems.join('; ')}';
}

/// Creates, verifies and restores Atlas Solo backups.
///
/// A backup is one encrypted file (see [BackupArchive] and [BackupCipher])
/// holding a consistent database snapshot, every attachment the books
/// reference, host configuration, and a manifest with schema/version
/// compatibility data, per-file SHA-256 hashes, table counts and
/// host-computed business totals.
///
/// A restore never edits the live data in place. It decrypts and verifies the
/// whole backup into a staging folder first ([stageRestore]); only then does
/// [commitRestore] swap folders using renames under a journal, verify the
/// result, and roll back on any failure. [recoverInterruptedRestore] must run
/// before the database is opened at startup so a restore cut short by a
/// crash or power loss is undone.
class AtlasBackupService {
  AtlasBackupService({required this.workDirectory});

  /// Scratch space for snapshots. Cleaned after each backup.
  final String workDirectory;

  /// Hook for fault-injection tests: called with a step name during
  /// [createBackup]; throwing simulates a crash at that point.
  Future<void> Function(String step)? faultHook;

  // ---------------------------------------------------------------- backup

  Future<BackupReport> createBackup(
    BackupRequest request, {
    required String outputPath,
    required String passphrase,
    BackupKdfParams? kdf,
  }) async {
    BackupCipher.checkPassphrase(passphrase);
    final work = Directory(p.join(
        workDirectory, 'backup-${DateTime.now().microsecondsSinceEpoch}'));
    work.createSync(recursive: true);
    final partial = '$outputPath.partial';
    BackupArchiveWriter? writer;
    try {
      final snapshotPath = p.join(work.path, 'mercantis.db');
      final stats = await DatabaseSnapshot.write(
        source: request.database,
        factory: request.factory,
        targetPath: snapshotPath,
      );
      await faultHook?.call('snapshot');

      // Read the attachment list from the SNAPSHOT, so files and rows agree.
      final snapshot = await request.factory.openDatabase(snapshotPath);
      final List<Map<String, Object?>> attachmentRows;
      final int schemaVersion;
      try {
        schemaVersion = await MigrationRunner.schemaVersion(snapshot);
        attachmentRows = await _attachmentRows(snapshot);
      } finally {
        await snapshot.close();
      }

      final files = <Map<String, Object?>>[];
      final missing = <MissingAttachment>[];
      final included = <(String, File, int, String)>[];
      for (final row in attachmentRows) {
        final id = '${row['id']}';
        final storagePath = '${row['storage_path']}';
        final expected = '${row['sha256']}';
        final root = request.attachmentsRoot;
        final String rel;
        try {
          rel = BackupArchive.safeRelativePath(storagePath);
        } on BackupException {
          missing.add(MissingAttachment(id, storagePath, 'invalid path'));
          continue;
        }
        final file =
            root == null ? null : File(p.joinAll([root, ...rel.split('/')]));
        if (file == null || !file.existsSync()) {
          missing.add(MissingAttachment(id, storagePath, 'file missing'));
          continue;
        }
        final digest = await _sha256(file);
        if (digest != expected) {
          missing.add(MissingAttachment(
              id, storagePath, 'file damaged (checksum mismatch)'));
          continue;
        }
        final len = file.lengthSync();
        included.add(('$backupAttachmentsPrefix$rel', file, len, digest));
        files.add({
          'path': '$backupAttachmentsPrefix$rel',
          'size': len,
          'sha256': digest,
          'role': 'attachment',
          'attachment_id': id,
        });
      }

      final dbFile = File(snapshotPath);
      final dbDigest = await _sha256(dbFile);
      files.insert(0, {
        'path': backupDatabaseEntry,
        'size': dbFile.lengthSync(),
        'sha256': dbDigest,
        'role': 'database',
      });
      final configEntries = <String, List<int>>{};
      request.configFiles.forEach((name, bytes) {
        final rel = BackupArchive.safeRelativePath('$backupConfigPrefix$name');
        configEntries[rel] = bytes;
        files.add({
          'path': rel,
          'size': bytes.length,
          'sha256': hash.sha256.convert(bytes).toString(),
          'role': 'config',
        });
      });

      final createdAt = DateTime.now().toUtc();
      final manifest = <String, Object?>{
        'format': BackupHeader.currentFormat,
        'producer': request.producer,
        'app_version': request.appVersion,
        'created_at': createdAt.toIso8601String(),
        'schema_version': schemaVersion,
        'sqlite_user_version': stats.userVersion,
        'table_counts': stats.rowsByTable,
        'files': files,
        'attachments': {
          'referenced': attachmentRows.length,
          'included': included.length,
        },
        'missing_attachments': [for (final m in missing) m.toJson()],
        'business_summary': request.businessSummary,
      };

      final header = BackupHeader(
        formatVersion: BackupHeader.currentFormat,
        createdAt: createdAt,
        producer: request.producer,
        kdf: kdf ?? BackupKdfParams.generate(),
        noncePrefix: BackupCipher.randomBytes(BackupCipher.noncePrefixLength),
      );
      final key = await BackupCipher.deriveKey(passphrase, header.kdf);
      final partialFile = File(partial);
      partialFile.parent.createSync(recursive: true);
      writer = await BackupArchiveWriter.create(partial, header, key);
      await writer.addManifest(manifest);
      await writer.addFile(backupDatabaseEntry, dbFile, dbFile.lengthSync());
      await faultHook?.call('database-written');
      for (final (name, file, len, digest) in included) {
        final written = await writer.addFile(name, file, len);
        if (written != digest) {
          throw FileSystemException(
              'attachment changed while it was being backed up', file.path);
        }
      }
      for (final e in configEntries.entries) {
        await writer.addBytes(e.key, e.value);
      }
      await faultHook?.call('attachments-written');
      await writer.close();
      writer = null;

      // Prove the file reads back (authenticates and every hash matches)
      // before it replaces anything under its real name.
      await verifyBackup(partial, passphrase);
      await faultHook?.call('verified');

      final out = File(outputPath);
      if (out.existsSync() && Platform.isWindows) out.deleteSync();
      partialFile.renameSync(outputPath);
      return BackupReport(
        path: outputPath,
        bytes: out.lengthSync(),
        manifest: manifest,
        missingAttachments: missing,
      );
    } catch (_) {
      await writer?.abort();
      final f = File(partial);
      if (f.existsSync()) f.deleteSync();
      rethrow;
    } finally {
      if (work.existsSync()) work.deleteSync(recursive: true);
    }
  }

  /// Decrypt [path] end to end without writing anything, checking every
  /// segment's authentication tag and every file's hash against the manifest.
  /// Returns the manifest.
  Future<Map<String, Object?>> verifyBackup(
      String path, String passphrase) async {
    final reader = await BackupArchiveReader.open(path);
    try {
      final key = await BackupCipher.deriveKey(passphrase, reader.header.kdf);
      Map<String, Object?>? manifest;
      final entries = await reader.extract(
        key: key,
        onManifest: (m) => manifest = m,
        destinationFor: (_) => null,
      );
      _checkEntries(manifest!, entries);
      return manifest!;
    } finally {
      await reader.close();
    }
  }

  /// Read only the public header of [path] (no passphrase needed).
  static Future<BackupHeader> readHeader(String path) async {
    final reader = await BackupArchiveReader.open(path);
    await reader.close();
    return reader.header;
  }

  // --------------------------------------------------------------- restore

  /// Decrypt and fully verify [backupPath] into [stagingDirectory] (created;
  /// must not already exist). Nothing live is touched. Throws
  /// [BackupException] for a wrong passphrase, damage, truncation, an unsafe
  /// archive or an incompatible schema; the staging folder is removed then.
  Future<StagedRestore> stageRestore({
    required String backupPath,
    required String passphrase,
    required String stagingDirectory,
    required DatabaseFactory factory,
    int supportedSchemaVersion = MigrationRunner.latestVersion,
  }) async {
    final staging = Directory(stagingDirectory);
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    try {
      final reader = await BackupArchiveReader.open(backupPath);
      final header = reader.header;
      Map<String, Object?>? manifest;
      final List<ExtractedEntry> entries;
      try {
        final key = await BackupCipher.deriveKey(passphrase, reader.header.kdf);
        entries = await reader.extract(
          key: key,
          onManifest: (m) {
            final schema = m['schema_version'];
            if (schema is! int) {
              throw const BackupException(
                  BackupException.damaged, 'The backup manifest is damaged.');
            }
            if (schema > supportedSchemaVersion) {
              throw BackupException(
                  BackupException.incompatible,
                  'This backup was made by a newer version of Atlas (data '
                  'format v$schema; this version reads up to '
                  'v$supportedSchemaVersion). Update Atlas, then restore.');
            }
            manifest = m;
          },
          destinationFor: (name) =>
              p.joinAll([stagingDirectory, 'payload', ...name.split('/')]),
        );
      } finally {
        await reader.close();
      }
      _checkEntries(manifest!, entries);

      final dbPath = p.joinAll(
          [stagingDirectory, 'payload', ...backupDatabaseEntry.split('/')]);
      final db = await factory.openDatabase(dbPath,
          options: OpenDatabaseOptions(singleInstance: false));
      final int schema;
      final Map<String, int> counts;
      try {
        try {
          await DatabaseSnapshot.verify(db);
        } on DatabaseIntegrityException catch (e) {
          throw BackupException(BackupException.damaged,
              'The database inside the backup is damaged (${e.detail}).');
        }
        schema = await MigrationRunner.schemaVersion(db);
        counts = await DatabaseSnapshot.tableCounts(db);
      } finally {
        await db.close();
      }
      if (schema != manifest!['schema_version']) {
        throw const BackupException(BackupException.damaged,
            'The backup manifest does not match its database.');
      }
      final expected = Map<String, Object?>.from(
          (manifest!['table_counts'] as Map?) ?? const {});
      for (final e in expected.entries) {
        if (counts[e.key] != e.value) {
          throw BackupException(BackupException.damaged,
              'The backup database is missing records (${e.key}).');
        }
      }

      final config = <String, List<int>>{};
      final configDir =
          Directory(p.join(stagingDirectory, 'payload', 'config'));
      if (configDir.existsSync()) {
        for (final f in configDir.listSync().whereType<File>()) {
          config[p.basename(f.path)] = f.readAsBytesSync();
        }
      }
      final attachmentsDir = p.join(stagingDirectory, 'payload', 'attachments');
      Directory(attachmentsDir).createSync(recursive: true);
      return StagedRestore(
        header: header,
        manifest: manifest!,
        stagingDirectory: stagingDirectory,
        databasePath: dbPath,
        attachmentsDirectory: attachmentsDir,
        configFiles: config,
        schemaVersion: schema,
        tableCounts: counts,
      );
    } catch (_) {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      rethrow;
    }
  }

  /// Replace the live data at [target] with [staged]. The live database MUST
  /// be closed first. Under a journal: move the live files aside, move the
  /// staged files in, verify (open + integrity check + table counts, then
  /// [verifyInstalled] for host checks such as ledger totals), and commit.
  /// Any failure — including a crash, where [recoverInterruptedRestore] runs
  /// at next start — puts the previous data back untouched.
  Future<RestoreOutcome> commitRestore(
    StagedRestore staged,
    RestoreTarget target, {
    required DatabaseFactory factory,
    Future<List<String>> Function(String databasePath)? verifyInstalled,
    String? safetyCopyDirectory,
    Future<void> Function(RestoreStep step)? onStep,
  }) async {
    final journalDir = Directory(target.journalDirectory);
    if (_journalFile(target).existsSync()) {
      throw StateError('another restore is in progress');
    }
    journalDir.createSync(recursive: true);
    final previous = p.join(target.journalDirectory, 'previous');
    final journal = _journalFile(target);
    _writeJournal(journal, {
      'state': 'prepared',
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'staging': staged.stagingDirectory,
    });
    await onStep?.call(RestoreStep.journalWritten);

    try {
      // 1. Move the live data aside (database + its journal/WAL files, and
      //    the attachment store).
      Directory(previous).createSync(recursive: true);
      for (final suffix in _dbSuffixes) {
        final f = File('${target.databasePath}$suffix');
        if (f.existsSync()) {
          f.renameSync(p.join(previous, 'mercantis.db$suffix'));
        }
      }
      final liveAttachments = Directory(target.attachmentsRoot);
      if (liveAttachments.existsSync()) {
        liveAttachments.renameSync(p.join(previous, 'attachments'));
      }
      _writeJournal(journal, {'state': 'previous-moved'});
      await onStep?.call(RestoreStep.previousMoved);

      // 2. Move the staged data in.
      File(target.databasePath).parent.createSync(recursive: true);
      File(staged.databasePath).renameSync(target.databasePath);
      Directory(target.attachmentsRoot).parent.createSync(recursive: true);
      Directory(staged.attachmentsDirectory).renameSync(target.attachmentsRoot);
      _writeJournal(journal, {'state': 'installed'});
      await onStep?.call(RestoreStep.stagedInstalled);

      // 3. Verify what is now live.
      final problems = await _verifyInstalled(staged, target, factory);
      if (verifyInstalled != null && problems.isEmpty) {
        problems.addAll(await verifyInstalled(target.databasePath));
      }
      if (problems.isNotEmpty) throw RestoreVerificationException(problems);
      await onStep?.call(RestoreStep.verified);

      // 4. Commit: from here the restored data stands.
      _writeJournal(journal, {'state': 'committed'});
      await onStep?.call(RestoreStep.committed);
    } catch (_) {
      _rollback(target);
      rethrow;
    }

    final kept = _finishCommitted(target, safetyCopyDirectory);
    staged.discard();
    return RestoreOutcome(safetyCopyDirectory: kept);
  }

  /// Run at startup BEFORE opening the database. Undoes a restore that was
  /// interrupted before it committed, or finishes one that committed but did
  /// not clean up.
  static RestoreRecovery recoverInterruptedRestore(RestoreTarget target,
      {String? safetyCopyDirectory}) {
    final journal = _journalFile(target);
    if (!journal.existsSync()) {
      // A crash before the journal was fully written leaves only a temp file.
      final tmp = File('${journal.path}.tmp');
      if (tmp.existsSync()) tmp.deleteSync();
      return RestoreRecovery.nothingToDo;
    }
    Map<String, Object?> state;
    try {
      state = Map<String, Object?>.from(
          jsonDecode(journal.readAsStringSync()) as Map);
    } catch (_) {
      state = const {'state': 'unknown'};
    }
    if (state['state'] == 'committed') {
      _finishCommitted(target, safetyCopyDirectory);
      return RestoreRecovery.completed;
    }
    _rollback(target);
    return RestoreRecovery.rolledBack;
  }

  // -------------------------------------------------------------- internals

  static const _dbSuffixes = ['', '-journal', '-wal', '-shm'];

  static File _journalFile(RestoreTarget t) =>
      File(p.join(t.journalDirectory, 'restore-journal.json'));

  /// Write the journal atomically (temp file + flush + rename).
  static void _writeJournal(File journal, Map<String, Object?> update) {
    Map<String, Object?> current = {};
    if (journal.existsSync()) {
      current = Map<String, Object?>.from(
          jsonDecode(journal.readAsStringSync()) as Map);
    }
    current.addAll(update);
    final tmp = File('${journal.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(current), flush: true);
    tmp.renameSync(journal.path);
  }

  /// Put the previous data back and forget the restore. Idempotent: safe to
  /// re-run if it is itself interrupted. What may be deleted depends on how
  /// far the restore got, which the journal records:
  ///
  /// * `prepared` — the live data may be partly moved aside, nothing new is
  ///   installed. Only move items back; delete nothing.
  /// * `previous-moved` / `installed` — every original item is in `previous`,
  ///   so whatever sits at the live paths came from the backup and is removed
  ///   before the originals return.
  static void _rollback(RestoreTarget target) {
    final journal = _journalFile(target);
    Map<String, Object?> state = const {};
    if (journal.existsSync()) {
      try {
        state = Map<String, Object?>.from(
            jsonDecode(journal.readAsStringSync()) as Map);
      } catch (_) {}
    }
    final phase = state['state'];
    final installedSomething =
        phase == 'previous-moved' || phase == 'installed';
    final previous = p.join(target.journalDirectory, 'previous');

    if (installedSomething) {
      for (final suffix in _dbSuffixes) {
        final f = File('${target.databasePath}$suffix');
        if (f.existsSync()) f.deleteSync();
      }
      final live = Directory(target.attachmentsRoot);
      if (live.existsSync()) live.deleteSync(recursive: true);
    }
    if (Directory(previous).existsSync()) {
      for (final suffix in _dbSuffixes) {
        final f = File(p.join(previous, 'mercantis.db$suffix'));
        if (f.existsSync() &&
            !File('${target.databasePath}$suffix').existsSync()) {
          f.renameSync('${target.databasePath}$suffix');
        }
      }
      final att = Directory(p.join(previous, 'attachments'));
      if (att.existsSync() && !Directory(target.attachmentsRoot).existsSync()) {
        att.renameSync(target.attachmentsRoot);
      }
    }
    final staging = state['staging'];
    if (staging is String && Directory(staging).existsSync()) {
      Directory(staging).deleteSync(recursive: true);
    }
    final journalDir = Directory(target.journalDirectory);
    if (journalDir.existsSync()) journalDir.deleteSync(recursive: true);
  }

  /// After commit: keep the replaced data as a safety copy (replacing an
  /// older one), then remove the journal.
  static String? _finishCommitted(
      RestoreTarget target, String? safetyCopyDirectory) {
    final previous = Directory(p.join(target.journalDirectory, 'previous'));
    String? kept;
    if (previous.existsSync() && previous.listSync().isNotEmpty) {
      if (safetyCopyDirectory != null) {
        final dest = Directory(safetyCopyDirectory);
        if (dest.existsSync()) dest.deleteSync(recursive: true);
        dest.parent.createSync(recursive: true);
        previous.renameSync(dest.path);
        kept = dest.path;
      }
    }
    final journalDir = Directory(target.journalDirectory);
    if (journalDir.existsSync()) journalDir.deleteSync(recursive: true);
    return kept;
  }

  Future<List<String>> _verifyInstalled(StagedRestore staged,
      RestoreTarget target, DatabaseFactory factory) async {
    final problems = <String>[];
    final db = await factory.openDatabase(target.databasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    try {
      await DatabaseSnapshot.verify(db);
      final counts = await DatabaseSnapshot.tableCounts(db);
      staged.tableCounts.forEach((table, n) {
        if (counts[table] != n) {
          problems.add('$table has ${counts[table]} rows, expected $n');
        }
      });
    } on DatabaseIntegrityException catch (e) {
      problems.add(e.toString());
    } finally {
      await db.close();
    }
    for (final f in (staged.manifest['files'] as List)) {
      final entry = Map<String, Object?>.from(f as Map);
      if (entry['role'] != 'attachment') continue;
      final rel = '${entry['path']}'.substring(backupAttachmentsPrefix.length);
      final file = File(p.joinAll([target.attachmentsRoot, ...rel.split('/')]));
      if (!file.existsSync() || await _sha256(file) != entry['sha256']) {
        problems.add('attachment ${entry['attachment_id']} did not restore');
      }
    }
    return problems;
  }

  static void _checkEntries(
      Map<String, Object?> manifest, List<ExtractedEntry> entries) {
    final files = manifest['files'];
    if (files is! List) {
      throw const BackupException(
          BackupException.damaged, 'The backup manifest is damaged.');
    }
    final expected = {
      for (final f in files)
        if (f is Map) '${f['path']}': f,
    };
    final seen = <String>{};
    for (final e in entries) {
      final want = expected[e.name];
      if (want == null || !seen.add(e.name)) {
        throw BackupException(BackupException.damaged,
            'The backup contains an unexpected file (${e.name}).');
      }
      if (want['size'] != e.length || want['sha256'] != e.sha256) {
        throw BackupException(BackupException.damaged,
            'A file inside the backup is damaged (${e.name}).');
      }
    }
    if (seen.length != expected.length || !seen.contains(backupDatabaseEntry)) {
      throw const BackupException(BackupException.damaged,
          'The backup is missing files listed in its manifest.');
    }
  }

  static Future<List<Map<String, Object?>>> _attachmentRows(Database db) async {
    final hasTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='attachments'");
    if (hasTable.isEmpty) return const [];
    return db.query('attachments',
        columns: ['id', 'storage_path', 'sha256'], orderBy: 'id');
  }

  static Future<String> _sha256(File file) async {
    final sink = _Sink();
    final conv = hash.sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      conv.add(chunk);
    }
    conv.close();
    return sink.value.toString();
  }
}

class _Sink implements Sink<hash.Digest> {
  late hash.Digest value;
  @override
  void add(hash.Digest data) => value = data;
  @override
  void close() {}
}
