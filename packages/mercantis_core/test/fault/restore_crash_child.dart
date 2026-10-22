// Child process for backup_restore_test.dart: stages a backup, then commits
// the restore and terminates the process (exit, no catch/finally runs) at the
// named RestoreStep, or during backup creation at the named backup step.
import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final mode = args[0];
  final service = AtlasBackupService(workDirectory: args[1]);
  if (mode == 'restore') {
    final backup = args[2];
    final passphrase = args[3];
    final dataDir = args[4];
    final step = args[5];
    final target = RestoreTarget(
      databasePath: p.join(dataDir, 'mercantis.db'),
      attachmentsRoot: p.join(dataDir, 'attachments'),
      journalDirectory: p.join(dataDir, 'restore-journal'),
    );
    final staged = await service.stageRestore(
      backupPath: backup,
      passphrase: passphrase,
      stagingDirectory: p.join(dataDir, 'restore-staging'),
      factory: databaseFactoryFfi,
    );
    await service.commitRestore(staged, target,
        factory: databaseFactoryFfi, onStep: (s) async {
      if (s.name == step) exit(9);
    });
    exit(0);
  }
  if (mode == 'backup') {
    final dataDir = args[2];
    final out = args[3];
    final passphrase = args[4];
    final step = args[5];
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: p.join(dataDir, 'mercantis.db'));
    service.faultHook = (s) async {
      if (s == step) exit(9);
    };
    await service.createBackup(
      BackupRequest(
        database: db.db,
        factory: databaseFactoryFfi,
        producer: 'test',
        appVersion: 'test',
        attachmentsRoot: p.join(dataDir, 'attachments'),
      ),
      outputPath: out,
      passphrase: passphrase,
      kdf: BackupKdfParams.generate(memoryKiB: 1024, iterations: 1),
    );
    exit(0);
  }
}
