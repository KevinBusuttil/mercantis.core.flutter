import 'dart:convert';
import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/dart_executable.dart';
import 'support/ledger_fixture.dart';

/// Encrypted backup and staged, journaled restore (M1.4 / M1.5).
///
/// Argon2id runs with small parameters here so the suite stays fast; the
/// production defaults are asserted separately.
void main() {
  setUpAll(sqfliteFfiInit);

  const passphrase = 'harbour lane ledger 2026';
  final fastKdf = BackupKdfParams.generate(memoryKiB: 1024, iterations: 1);

  late Directory root;
  late String dataDir;
  late MercantisDatabase db;
  late DocumentEngine engine;
  late AttachmentManager attachments;
  late AtlasBackupService service;

  RestoreTarget targetFor(String dir) => RestoreTarget(
        databasePath: p.join(dir, 'mercantis.db'),
        attachmentsRoot: p.join(dir, 'attachments'),
        journalDirectory: p.join(dir, 'restore-journal'),
      );

  Future<void> openLive() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: p.join(dataDir, 'mercantis.db'));
    engine = await buildTestEngine(db);
    attachments = AttachmentManager(
        db.db, AttachmentStore(p.join(dataDir, 'attachments')));
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('mc_backup_');
    dataDir = p.join(root.path, 'device-a');
    Directory(dataDir).createSync();
    service = AtlasBackupService(workDirectory: p.join(root.path, 'work'));
    await openLive();
    for (var i = 0; i < 5; i++) {
      final doc = await engine.save(invoice('INV-$i', lineCount: i + 1),
          testRoles);
      if (i.isOdd) await engine.submit(doc, testRoles);
    }
    await attachments.attach(
        documentId: 'INV-1',
        docType: 'Inv',
        fileName: 'receipt.pdf',
        data: utf8.encode('%PDF receipt bytes'),
        userId: 'u');
    await attachments.attach(
        documentId: 'INV-3',
        docType: 'Inv',
        fileName: 'photo.jpg',
        data: List<int>.generate(1500000, (i) => i % 251),
        userId: 'u');
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<BackupReport> backup(String out, {Map<String, Object?>? summary}) =>
      service.createBackup(
        BackupRequest(
          database: db.db,
          factory: databaseFactoryFfi,
          producer: 'Neuradix Atlas',
          appVersion: '1.0.0-test',
          attachmentsRoot: p.join(dataDir, 'attachments'),
          configFiles: {'preferences.json': utf8.encode('{"theme":"dark"}')},
          businessSummary: summary ?? {'documents': 5},
        ),
        outputPath: out,
        passphrase: passphrase,
        kdf: fastKdf,
      );

  Future<Map<String, Object?>> fingerprint(MercantisDatabase d) async {
    final docs = await d.db.query('documents', orderBy: 'id');
    final children = await d.db.query('document_children', orderBy: 'id');
    final atts = await d.db.query('attachments', orderBy: 'id');
    return {
      'docs': [for (final r in docs) jsonEncode(r)],
      'children': [for (final r in children) jsonEncode(r)],
      'attachments': [for (final r in atts) jsonEncode(r)],
    };
  }

  test('default key derivation is Argon2id at 64 MiB, 3 passes', () {
    final kdf = BackupKdfParams.generate();
    expect(kdf.memoryKiB, 65536);
    expect(kdf.iterations, 3);
    expect(kdf.salt, hasLength(16));
  });

  test('backup → restore into a clean installation is identical', () async {
    final out = p.join(root.path, 'books.atlasbackup');
    final report = await backup(out);
    expect(report.missingAttachments, isEmpty);
    expect(File(out).existsSync(), isTrue);
    expect(File('$out.partial').existsSync(), isFalse);
    final original = await fingerprint(db);

    // A brand-new device: no database yet.
    final cleanDir = p.join(root.path, 'device-b');
    final target = targetFor(cleanDir);
    final staged = await service.stageRestore(
      backupPath: out,
      passphrase: passphrase,
      stagingDirectory: p.join(cleanDir, 'restore-staging'),
      factory: databaseFactoryFfi,
    );
    expect(staged.businessSummary, {'documents': 5});
    expect(utf8.decode(staged.configFiles['preferences.json']!),
        '{"theme":"dark"}');
    final outcome = await service.commitRestore(staged, target,
        factory: databaseFactoryFfi);
    expect(outcome.safetyCopyDirectory, isNull);
    expect(Directory(target.journalDirectory).existsSync(), isFalse);

    final restored = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: target.databasePath);
    try {
      expect(await fingerprint(restored), original);
      final m = AttachmentManager(
          restored.db, AttachmentStore(target.attachmentsRoot));
      for (final a in await m.attachmentsForDocument('INV-3')) {
        // read() re-verifies the SHA-256 recorded in the books.
        expect(await m.read(a), hasLength(1500000));
      }
      // Normal use resumes: a new document saves and submits.
      final e = await buildTestEngine(restored, deviceId: 'device-b');
      await e.submit(await e.save(invoice('AFTER-RESTORE'), testRoles),
          testRoles);
    } finally {
      await restored.close();
    }
  });

  test('the passphrase is never written into the backup', () async {
    final out = p.join(root.path, 'b.atlasbackup');
    await backup(out);
    final bytes = File(out).readAsBytesSync();
    final hay = latin1.decode(bytes);
    expect(hay.contains(passphrase), isFalse);
    expect(hay.contains('INV-1'), isFalse, reason: 'business data encrypted');
    expect(hay.contains('receipt.pdf'), isFalse);
  });

  test('weak passphrases are refused before anything is written', () async {
    final out = p.join(root.path, 'weak.atlasbackup');
    await expectLater(
      service.createBackup(
        BackupRequest(
            database: db.db,
            factory: databaseFactoryFfi,
            producer: 'x',
            appVersion: 'x'),
        outputPath: out,
        passphrase: 'short',
      ),
      throwsA(isA<BackupException>().having(
          (e) => e.code, 'code', BackupException.weakPassphrase)),
    );
    expect(File(out).existsSync(), isFalse);
  });

  group('invalid backups never touch live data', () {
    late String out;
    late Map<String, Object?> before;

    setUp(() async {
      out = p.join(root.path, 'b.atlasbackup');
      await backup(out);
      before = await fingerprint(db);
    });

    Future<void> expectRejected(String path, String code,
        {String pass = passphrase}) async {
      final staging = p.join(dataDir, 'restore-staging');
      await expectLater(
        service.stageRestore(
          backupPath: path,
          passphrase: pass,
          stagingDirectory: staging,
          factory: databaseFactoryFfi,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', code)),
      );
      expect(Directory(staging).existsSync(), isFalse,
          reason: 'staging cleaned up');
      expect(await fingerprint(db), before, reason: 'live data untouched');
    }

    test('wrong passphrase', () async {
      await expectRejected(out, BackupException.wrongPassphraseOrDamaged,
          pass: 'not the right passphrase');
    });

    test('a flipped byte in the encrypted body', () async {
      final bytes = File(out).readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0x01;
      final bad = p.join(root.path, 'flipped.atlasbackup');
      File(bad).writeAsBytesSync(bytes);
      await expectRejected(bad, BackupException.wrongPassphraseOrDamaged);
    });

    test('a truncated file', () async {
      final bytes = File(out).readAsBytesSync();
      final bad = p.join(root.path, 'cut.atlasbackup');
      File(bad).writeAsBytesSync(bytes.sublist(0, bytes.length - 100));
      await expectRejected(bad, BackupException.truncated);
    });

    test('a file cut exactly at a segment boundary', () async {
      // Drop the final segment entirely: the previous one was sealed as
      // "not last", so it fails when presented as the end of the stream.
      final bytes = File(out).readAsBytesSync();
      final reader = await BackupArchiveReader.open(out);
      await reader.close();
      final headerLen = jsonEncode(reader.header.toJson()).length;
      var pos = 8 + 4 + headerLen;
      final starts = <int>[];
      while (pos < bytes.length) {
        starts.add(pos);
        final len = (bytes[pos] << 24) |
            (bytes[pos + 1] << 16) |
            (bytes[pos + 2] << 8) |
            bytes[pos + 3];
        pos += 4 + len;
      }
      expect(starts.length, greaterThan(1));
      final bad = p.join(root.path, 'boundary.atlasbackup');
      File(bad).writeAsBytesSync(bytes.sublist(0, starts.last));
      await expectRejected(bad, BackupException.wrongPassphraseOrDamaged);
    });

    test('data appended after the end', () async {
      final bad = p.join(root.path, 'appended.atlasbackup');
      File(bad).writeAsBytesSync([...File(out).readAsBytesSync(), 0, 0, 0, 4, 1, 2, 3, 4]);
      await expectRejected(bad, BackupException.damaged);
    });

    test('an edited public header', () async {
      final text = latin1.decode(File(out).readAsBytesSync());
      final edited = text.replaceFirst('"producer":"Neuradix Atlas"',
          '"producer":"Neuradix Atlaz"');
      expect(edited, isNot(text));
      final bad = p.join(root.path, 'header.atlasbackup');
      File(bad).writeAsBytesSync(latin1.encode(edited));
      await expectRejected(bad, BackupException.wrongPassphraseOrDamaged);
    });

    test('a file that is not a backup', () async {
      final bad = p.join(root.path, 'notes.txt');
      File(bad).writeAsStringSync('hello');
      await expectRejected(bad, BackupException.notABackup);
    });

    test('a backup from a newer schema', () async {
      // Build a backup whose database claims schema v99.
      final future = await databaseFactoryFfi
          .openDatabase(p.join(root.path, 'future.db'));
      await future.execute('CREATE TABLE schema_version (version INTEGER)');
      await future.insert('schema_version', {'version': 99});
      final newer = p.join(root.path, 'newer.atlasbackup');
      await service.createBackup(
        BackupRequest(
            database: future,
            factory: databaseFactoryFfi,
            producer: 'Neuradix Atlas',
            appVersion: '9.0'),
        outputPath: newer,
        passphrase: passphrase,
        kdf: fastKdf,
      );
      await future.close();
      await expectRejected(newer, BackupException.incompatible);
    });

    test('an archive entry that tries to escape the restore folder',
        () async {
      final header = BackupHeader(
        formatVersion: 1,
        createdAt: DateTime.now(),
        producer: 'evil',
        kdf: fastKdf,
        noncePrefix: BackupCipher.randomBytes(7),
      );
      final key = await BackupCipher.deriveKey(passphrase, header.kdf);
      final evil = p.join(root.path, 'evil.atlasbackup');
      final w = await BackupArchiveWriter.create(evil, header, key);
      await w.addManifest({
        'schema_version': 1,
        'files': [
          {'path': '../escaped.txt', 'size': 3, 'sha256': 'x'},
        ],
      });
      await w.addBytes('../escaped.txt', [1, 2, 3]);
      await w.close();
      await expectRejected(evil, BackupException.unsafePath);
      expect(File(p.join(dataDir, 'escaped.txt')).existsSync(), isFalse);
    });
  });

  test('the business summary describes the snapshot, not later live writes',
      () async {
    // A document saved while the backup is being written must not reach the
    // summary, or the restore (which re-computes it) would be refused.
    service.faultHook = (step) async {
      if (step == 'snapshot') {
        await engine.save(invoice('INV-LATE'), testRoles);
      }
    };
    final out = p.join(root.path, 'books.atlasbackup');
    await service.createBackup(
      BackupRequest(
        database: db.db,
        factory: databaseFactoryFfi,
        producer: 'Neuradix Atlas',
        appVersion: '1.0.0-test',
        attachmentsRoot: p.join(dataDir, 'attachments'),
        businessSummary: const {'ignored': true},
        summarizeSnapshot: (snapshot) async => {
          'documents': (await snapshot.rawQuery(
                  "SELECT COUNT(*) AS n FROM documents WHERE doctype = 'Inv'"))
              .single['n'],
        },
      ),
      outputPath: out,
      passphrase: passphrase,
      kdf: fastKdf,
    );
    service.faultHook = null;
    expect(await engine.fetch('Inv', 'INV-LATE'), isNotNull);
    final staged = await service.stageRestore(
      backupPath: out,
      passphrase: passphrase,
      stagingDirectory: p.join(root.path, 'staging'),
      factory: databaseFactoryFfi,
    );
    expect(staged.businessSummary, {'documents': 5});
  });

  test('a missing attachment is reported, not silently dropped', () async {
    final rows = await db.db.query('attachments', where: 'document_id = ?',
        whereArgs: ['INV-1']);
    File(p.joinAll([
      dataDir,
      'attachments',
      ...(rows.single['storage_path'] as String).split('/'),
    ])).deleteSync();
    final report = await backup(p.join(root.path, 'm.atlasbackup'));
    expect(report.missingAttachments, hasLength(1));
    expect(report.missingAttachments.single.reason, 'file missing');
  });

  test('replacing live data keeps the replaced data as a safety copy',
      () async {
    final out = p.join(root.path, 'b.atlasbackup');
    await backup(out);
    final atBackup = await fingerprint(db);
    // Work done after the backup, which the restore will replace.
    await engine.save(invoice('AFTER-BACKUP'), testRoles);
    await db.close();

    final target = targetFor(dataDir);
    final staged = await service.stageRestore(
      backupPath: out,
      passphrase: passphrase,
      stagingDirectory: p.join(dataDir, 'restore-staging'),
      factory: databaseFactoryFfi,
    );
    final safety = p.join(root.path, 'pre-restore');
    final outcome = await service.commitRestore(staged, target,
        factory: databaseFactoryFfi, safetyCopyDirectory: safety);
    expect(outcome.safetyCopyDirectory, safety);
    expect(File(p.join(safety, 'mercantis.db')).existsSync(), isTrue);

    await openLive();
    expect(await fingerprint(db), atBackup);
    expect(await engine.fetch('Inv', 'AFTER-BACKUP'), isNull);
  });

  test('a host verification failure rolls the restore back', () async {
    final out = p.join(root.path, 'b.atlasbackup');
    await backup(out);
    final before = await fingerprint(db);
    await db.close();

    final staged = await service.stageRestore(
      backupPath: out,
      passphrase: passphrase,
      stagingDirectory: p.join(dataDir, 'restore-staging'),
      factory: databaseFactoryFfi,
    );
    await expectLater(
      service.commitRestore(staged, targetFor(dataDir),
          factory: databaseFactoryFfi,
          verifyInstalled: (_) async => ['trial balance differs by 0.01']),
      throwsA(isA<RestoreVerificationException>()),
    );
    await openLive();
    expect(await fingerprint(db), before);
  });

  group('process killed during restore', () {
    for (final step in RestoreStep.values) {
      test('at ${step.name}: startup recovery leaves consistent data',
          () async {
        final out = p.join(root.path, 'b.atlasbackup');
        await backup(out);
        // Diverge the live data so we can tell which copy survived.
        await engine.save(invoice('LIVE-ONLY'), testRoles);
        final live = await fingerprint(db);
        await db.close();

        final result = await Process.run(dartExecutable(), [
          'run',
          'test/fault/restore_crash_child.dart',
          'restore',
          p.join(root.path, 'work'),
          out,
          passphrase,
          dataDir,
          step.name,
        ]);
        expect(result.exitCode, 9, reason: '${result.stdout}${result.stderr}');

        final recovery =
            AtlasBackupService.recoverInterruptedRestore(targetFor(dataDir));
        expect(Directory(p.join(dataDir, 'restore-journal')).existsSync(),
            isFalse);
        await openLive();
        expect(await db.quickCheck(), isTrue);
        final now = await fingerprint(db);
        if (step == RestoreStep.committed) {
          // Committed before the crash: the restore stands.
          expect(recovery, RestoreRecovery.completed);
          expect(await engine.fetch('Inv', 'LIVE-ONLY'), isNull);
        } else {
          expect(recovery, RestoreRecovery.rolledBack);
          expect(now, live, reason: 'the previous data is back, unchanged');
        }
        // Attachments match the books either way.
        for (final a in await attachments.attachmentsForDocument('INV-3')) {
          expect(await attachments.read(a), hasLength(1500000));
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });

  group('process killed during backup', () {
    for (final step in const ['snapshot', 'database-written', 'verified']) {
      test('at $step: no backup appears and an older one survives', () async {
        final out = p.join(root.path, 'b.atlasbackup');
        await backup(out);
        final older = File(out).readAsBytesSync();
        final before = await fingerprint(db);
        await db.close();

        final result = await Process.run(dartExecutable(), [
          'run',
          'test/fault/restore_crash_child.dart',
          'backup',
          p.join(root.path, 'work'),
          dataDir,
          out,
          passphrase,
          step,
        ]);
        expect(result.exitCode, 9, reason: '${result.stdout}${result.stderr}');
        expect(File(out).readAsBytesSync(), older,
            reason: 'the last good backup is never replaced by a partial one');
        await openLive();
        expect(await fingerprint(db), before);
        // The previous good backup still restores.
        await service.verifyBackup(out, passphrase);
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });
}
