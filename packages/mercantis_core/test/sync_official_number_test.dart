import 'dart:convert';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Applying a remote submit/cancel must land the mutation envelope's
/// payload — notably the Team posting authority's `official_number` — not
/// just flip docstatus. Before this, the legal gap-free number existed only
/// server-side (gap analysis §8-C7).
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late SyncEngine sync;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    sync = SyncEngine(
      database: database.db,
      registry: MetadataRegistry(database.db),
    );
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
  });

  Map<String, dynamic> envelope(Map<String, dynamic> fields, int docstatus) =>
      {
        'id': 'SINV-1',
        'doctype': 'Sales Invoice',
        'company': null,
        'docstatus': docstatus,
        'payload': jsonEncode(fields),
        'created_at': 1,
        'modified_at': 2,
        'sync_version': null,
        'sync_state': 'synced',
        'amended_from': null,
      };

  MutationRecord mutation(MutationType type, Map<String, dynamic> payload) =>
      MutationRecord(
        id: 'mut-${type.name}',
        type: type,
        docType: 'Sales Invoice',
        documentId: 'SINV-1',
        payload: payload,
        deviceId: 'atlas-backend',
        userId: 'system',
        localTimestamp: DateTime.fromMillisecondsSinceEpoch(1751800000000),
        syncVersion: '3',
      );

  Future<Map<String, dynamic>> storedFields() async {
    final rows = await database.db
        .query('documents', where: 'id = ?', whereArgs: ['SINV-1']);
    return {
      ...jsonDecode(rows.single['payload'] as String) as Map<String, dynamic>,
      '__docstatus': rows.single['docstatus'],
    };
  }

  test('submit apply lands the official number; cancel keeps it', () async {
    // The draft as the device knew it.
    await sync.applyRemoteMutations([
      mutation(MutationType.createDocument,
          envelope({'customer': 'CUST-1', 'grand_total': 44}, 0)),
    ]);

    // The posting authority's replicated submit: same payload + the
    // allocated number.
    await sync.applyRemoteMutations([
      mutation(
          MutationType.submitDocument,
          envelope({
            'customer': 'CUST-1',
            'grand_total': 44,
            'official_number': 'SINV-00012',
          }, 1)),
    ]);
    var fields = await storedFields();
    expect(fields['__docstatus'], 1);
    expect(fields['official_number'], 'SINV-00012');
    expect(fields['customer'], 'CUST-1'); // nothing else lost

    // Cancellation keeps the number (a cancelled official document is
    // still that document).
    await sync.applyRemoteMutations([
      mutation(
          MutationType.cancelDocument,
          envelope({
            'customer': 'CUST-1',
            'grand_total': 44,
            'official_number': 'SINV-00012',
          }, 2)),
    ]);
    fields = await storedFields();
    expect(fields['__docstatus'], 2);
    expect(fields['official_number'], 'SINV-00012');
  });

  test('a payload-less lifecycle mutation still flips docstatus', () async {
    await sync.applyRemoteMutations([
      mutation(MutationType.createDocument,
          envelope({'customer': 'CUST-1'}, 0)),
    ]);
    // Legacy/minimal mutation: no envelope payload at all.
    await sync.applyRemoteMutations([
      mutation(MutationType.submitDocument, {'docstatus': 1}),
    ]);
    final fields = await storedFields();
    expect(fields['__docstatus'], 1);
    expect(fields['customer'], 'CUST-1'); // untouched
  });
}
