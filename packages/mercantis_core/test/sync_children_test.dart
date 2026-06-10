import 'dart:convert';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// A pulled document must rebuild its line items, not just its header
/// (child-table sync). Verifies the reserved `__children` envelope is unpacked
/// into document_children on apply, and that a later header-only update leaves
/// those children intact.
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

  tearDown(() => database.close());

  MutationRecord create({
    required String id,
    required Map<String, dynamic> fields,
    Map<String, List<Map<String, dynamic>>>? children,
  }) {
    return MutationRecord(
      id: 'mut-$id',
      type: MutationType.createDocument,
      docType: 'Sales Invoice',
      documentId: id,
      payload: {
        'id': id,
        'doctype': 'Sales Invoice',
        'company': null,
        'docstatus': 0,
        'payload': jsonEncode(fields),
        'created_at': 0,
        'modified_at': 0,
        'sync_version': null,
        'sync_state': 'local',
        'amended_from': null,
        if (children != null)
          '__children': {
            for (final entry in children.entries)
              entry.key: [
                for (var i = 0; i < entry.value.length; i++)
                  {
                    'id': '$id-${entry.key}-$i',
                    'parent_id': id,
                    'parent_doctype': 'Sales Invoice',
                    'table_name': entry.key,
                    'row_index': i,
                    'payload': jsonEncode(entry.value[i]),
                  }
              ],
          },
      },
      deviceId: 'devA',
      userId: 'u',
      localTimestamp: DateTime.now(),
    );
  }

  Future<List<Map<String, dynamic>>> childRows(String parentId) =>
      database.db.query('document_children',
          where: 'parent_id = ?', whereArgs: [parentId], orderBy: 'row_index');

  test('applying a create rebuilds the document\'s line items', () async {
    await sync.applyRemoteMutations([
      create(
        id: 'SINV-1',
        fields: {'customer': 'C1', 'grand_total': 820},
        children: {
          'items': [
            {'item': 'WGT-A', 'qty': 1, 'rate': 1000},
            {'item': 'WGT-B', 'qty': 2, 'rate': 410},
          ],
        },
      ),
    ]);

    final rows = await childRows('SINV-1');
    expect(rows, hasLength(2));
    expect(jsonDecode(rows[0]['payload'] as String)['item'], 'WGT-A');
    expect(jsonDecode(rows[1]['payload'] as String)['qty'], 2);
  });

  test('a header-only update leaves existing children intact', () async {
    await sync.applyRemoteMutations([
      create(
        id: 'SINV-2',
        fields: {'grand_total': 100},
        children: {
          'items': [
            {'item': 'X', 'qty': 1},
          ],
        },
      ),
    ]);
    expect(await childRows('SINV-2'), hasLength(1));

    // An update with no __children (e.g. an outstanding-amount change) must not
    // wipe the line items.
    await sync.applyRemoteMutations([
      MutationRecord(
        id: 'mut-upd',
        type: MutationType.updateDocument,
        docType: 'Sales Invoice',
        documentId: 'SINV-2',
        payload: {
          'id': 'SINV-2',
          'doctype': 'Sales Invoice',
          'docstatus': 1,
          'payload': jsonEncode({'grand_total': 100, 'outstanding_amount': 0}),
          'created_at': 0,
          'sync_state': 'local',
        },
        deviceId: 'devA',
        userId: 'u',
        localTimestamp: DateTime.now(),
      ),
    ]);

    expect(await childRows('SINV-2'), hasLength(1));
  });
}
