import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/ledger_fixture.dart';

/// Writes into the submit/cancel transaction, like a posting outbox.
class _OutboxMarker extends DocumentInterceptor {
  const _OutboxMarker({this.fail = false});
  final bool fail;
  @override
  Future<void> inLifecycleTransaction(DocumentEngine engine, Document doc,
      DocType docType, UnitOfWork uow, LifecycleAction action) async {
    await uow.recordPostingBatch(PostingBatch(
      id: 'PB-${doc.id}-${action.name}',
      sourceType: doc.docType,
      sourceId: doc.id,
      status: PostingStatus.pending,
    ));
    if (fail) throw StateError('injected failure inside the transaction');
  }
}

/// Fault injection for the document write path (M1.5): a failed write, a full
/// disk and a killed process must never leave a half-saved document, a
/// submitted document without its audit/sync records, or a corrupt file.
///
/// Failures are injected with real SQLite mechanisms rather than mocks: a
/// TEMP trigger that RAISEs (a write that fails part-way through), and
/// `PRAGMA max_page_count` (SQLITE_FULL, the "disk full" error).
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  late MercantisDatabase database;
  late DocumentEngine engine;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mc_crash_');
    database = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: p.join(dir.path, 'm.db'));
    engine = await buildTestEngine(database);
  });

  tearDown(() async {
    await database.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<int> count(String table, [String? where, List<Object?>? args]) async {
    final rows = await database.db.rawQuery(
        'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}',
        args);
    return rows.first['n'] as int;
  }

  Future<void> failInsertsInto(String table) => database.db.execute(
      'CREATE TEMP TRIGGER fail_$table BEFORE INSERT ON $table '
      "BEGIN SELECT RAISE(ABORT, 'injected write failure'); END");

  test('a write failure mid-save leaves the previous version whole', () async {
    final first = await engine.save(invoice('INV-1', lineCount: 3), testRoles);
    final audits = await count('audit_log');
    final queued = await count('sync_queue');

    // Second save fails while inserting the new child rows — after the old
    // rows were deleted. Before the fix this lost every line.
    await failInsertsInto('document_children');
    final edit = invoice('INV-1', lineCount: 5)..modifiedAt = first.modifiedAt;
    await expectLater(engine.save(edit, testRoles), throwsA(anything));
    await database.db.execute('DROP TRIGGER fail_document_children');

    final reloaded = await engine.fetch('Inv', 'INV-1');
    expect(reloaded!.children['lines'], hasLength(3));
    expect(await count('audit_log'), audits, reason: 'no orphan audit row');
    expect(await count('sync_queue'), queued, reason: 'no phantom mutation');
  });

  test('a failed sync-queue write rolls the whole save back', () async {
    await failInsertsInto('sync_queue');
    await expectLater(
        engine.save(invoice('INV-2'), testRoles), throwsA(anything));
    expect(await engine.fetch('Inv', 'INV-2'), isNull);
    expect(await count('document_children'), 0);
    expect(await count('audit_log'), 0);
  });

  test('submit is all-or-nothing: status, audit, mutation, outbox', () async {
    final e = await buildTestEngine(database,
        interceptors: const [_OutboxMarker()]);
    final draft = await e.save(invoice('INV-3'), testRoles);
    await failInsertsInto('audit_log');
    await expectLater(e.submit(draft, testRoles), throwsA(anything));
    await database.db.execute('DROP TRIGGER fail_audit_log');

    expect((await e.fetch('Inv', 'INV-3'))!.docStatus, 0);
    expect(draft.docStatus, 0, reason: 'in-memory doc stays Draft');
    expect(await count('posting_batches'), 0);
    expect(await count('sync_queue', 'type = ?', ['submitDocument']), 0);

    final submitted = await e.submit(draft, testRoles);
    expect(submitted.docStatus, 1);
    expect(await count('posting_batches', 'id = ?', ['PB-INV-3-submit']), 1);
    expect(await count('audit_log', 'action = ?', ['submitted']), 1);
  });

  test('an interceptor failing inside the transaction blocks the submit',
      () async {
    final e = await buildTestEngine(database,
        interceptors: const [_OutboxMarker(fail: true)]);
    final draft = await e.save(invoice('INV-4'), testRoles);
    await expectLater(e.submit(draft, testRoles), throwsA(isA<StateError>()));
    expect((await e.fetch('Inv', 'INV-4'))!.docStatus, 0);
    expect(await count('posting_batches'), 0, reason: 'marker rolled back');
  });

  test('cancel writes its outbox marker atomically with the status flip',
      () async {
    final e = await buildTestEngine(database,
        interceptors: const [_OutboxMarker()]);
    final doc = await e.submit(await e.save(invoice('INV-5'), testRoles),
        testRoles);
    await failInsertsInto('sync_queue');
    await expectLater(e.cancel(doc, testRoles), throwsA(anything));
    await database.db.execute('DROP TRIGGER fail_sync_queue');
    expect((await e.fetch('Inv', 'INV-5'))!.docStatus, 1);
    expect(await count('posting_batches', 'id = ?', ['PB-INV-5-cancel']), 0);
    await e.cancel(doc, testRoles);
    expect((await e.fetch('Inv', 'INV-5'))!.docStatus, 2);
    expect(await count('posting_batches', 'id = ?', ['PB-INV-5-cancel']), 1);
  });

  test('disk full: the save fails clearly and the file stays sound',
      () async {
    await engine.save(invoice('INV-6', lineCount: 2), testRoles);
    final pages = (await database.db.rawQuery('PRAGMA page_count'))
        .first
        .values
        .first as int;
    await database.db.execute('PRAGMA max_page_count = $pages');

    Object? error;
    try {
      for (var i = 0; i < 200; i++) {
        await engine.save(invoice('BIG-$i', lineCount: 200), testRoles);
      }
    } catch (e) {
      error = e;
    }
    expect(error, isNotNull, reason: 'the store must refuse, not truncate');
    expect('$error'.toLowerCase(), contains('full'));
    await database.db.execute('PRAGMA max_page_count = 1073741823');

    expect(await database.quickCheck(), isTrue);
    expect((await engine.fetch('Inv', 'INV-6'))!.children['lines'],
        hasLength(2));
    // Every document that did land has all 200 lines: none is half-written.
    final big = await database.db.rawQuery(
        "SELECT id FROM documents WHERE id LIKE 'BIG-%'");
    for (final r in big) {
      expect(await count('document_children', 'parent_id = ?', [r['id']]),
          200);
    }
    // And the store accepts writes again once space is freed.
    await engine.save(invoice('INV-7'), testRoles);
  });

  test('killing the process mid-write never leaves a partial document',
      () async {
    final dbPath = p.join(dir.path, 'killed.db');
    final rng = Random(42);
    final dart = Platform.resolvedExecutable;
    for (var run = 0; run < 6; run++) {
      final child = await Process.start(dart, [
        'run',
        'test/fault/save_loop_child.dart',
        dbPath,
        'r$run',
      ]);
      final ready = Completer<void>();
      final out = StringBuffer();
      child.stdout.transform(utf8.decoder).listen((s) {
        out.write(s);
        if (s.contains('ready') && !ready.isCompleted) ready.complete();
      });
      child.stderr.transform(utf8.decoder).listen(out.write);
      await ready.future.timeout(const Duration(seconds: 60),
          onTimeout: () => fail('child never started: $out'));
      await Future<void>.delayed(Duration(milliseconds: 150 + rng.nextInt(600)));
      expect(child.kill(ProcessSignal.sigkill), isTrue);
      await child.exitCode;

      // Reopen exactly as the app would after a crash.
      final reopened = await MercantisDatabase.open(
          factory: databaseFactoryFfi, path: dbPath);
      try {
        expect(await reopened.quickCheck(), isTrue);
        final docs = await reopened.db.rawQuery(
            "SELECT id, docstatus FROM documents WHERE doctype = 'Inv'");
        expect(docs, isNotEmpty, reason: 'run $run made progress');
        for (final d in docs) {
          final lines = (await reopened.db.rawQuery(
                  'SELECT COUNT(*) AS n FROM document_children '
                  'WHERE parent_id = ?',
                  [d['id']]))
              .first['n'];
          expect(lines, anyOf(25, 40), reason: '${d['id']} lost lines');
          final created = (await reopened.db.rawQuery(
                  "SELECT COUNT(*) AS n FROM sync_queue WHERE document_id = ? "
                  "AND type = 'createDocument'",
                  [d['id']]))
              .first['n'];
          expect(created, 1, reason: '${d['id']} has its create mutation');
          if (d['docstatus'] == 1) {
            final audit = (await reopened.db.rawQuery(
                    "SELECT COUNT(*) AS n FROM audit_log WHERE document_id = ? "
                    "AND action = 'submitted'",
                    [d['id']]))
                .first['n'];
            expect(audit, 1, reason: '${d['id']} submitted without audit');
          }
        }
        // No mutation or audit row may describe a document that does not
        // exist (the save it belonged to was rolled back).
        final orphanMutations = (await reopened.db.rawQuery(
                "SELECT COUNT(*) AS n FROM sync_queue q WHERE doctype = 'Inv' "
                'AND NOT EXISTS (SELECT 1 FROM documents d '
                'WHERE d.id = q.document_id)'))
            .first['n'];
        expect(orphanMutations, 0);
      } finally {
        await reopened.close();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  group('attachment store', () {
    test('a failed write leaves no file under the real name', () {
      final store = AttachmentStore(p.join(dir.path, 'att'));
      // Make the rename target a directory so the final step fails.
      Directory(p.join(dir.path, 'att', 'DOC', 'A1')).createSync(recursive: true);
      expect(() => store.write('DOC', 'A1', [1, 2, 3]), throwsA(anything));
      expect(
          File(p.join(dir.path, 'att', 'DOC',
                  'A1${AttachmentStore.partialSuffix}'))
              .existsSync(),
          isFalse);
    });

    test('sweepPartials removes leftovers of an interrupted write', () {
      final store = AttachmentStore(p.join(dir.path, 'att2'));
      store.write('DOC', 'OK', [1]);
      File(p.join(dir.path, 'att2', 'DOC', 'X${AttachmentStore.partialSuffix}'))
          .writeAsBytesSync([9, 9]);
      expect(store.sweepPartials(), 1);
      expect(store.exists('DOC/OK'), isTrue);
    });
  });
}
