// Child process for crash_safety_test.dart: saves, re-saves and submits
// invoices in a tight loop until the parent kills it with SIGKILL. Not a test
// file on its own (no `_test` suffix).
import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/ledger_fixture.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final db = await MercantisDatabase.open(
      factory: databaseFactoryFfi, path: args[0]);
  final engine = await buildTestEngine(db);
  final run = args.length > 1 ? args[1] : 'r';
  var n = 0;
  stdout.writeln('ready');
  while (true) {
    final id = 'INV-$run-${n++}';
    final saved = await engine.save(invoice(id, lineCount: 25), testRoles);
    // Re-save with a different line count: exercises delete-then-insert of
    // child rows, the window that used to lose lines on a crash.
    final again = invoice(id, lineCount: 40)..modifiedAt = saved.modifiedAt;
    again.createdAt = saved.createdAt;
    final resaved = await engine.save(again, testRoles);
    if (n.isEven) await engine.submit(resaved, testRoles);
  }
}
