import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late MercantisDatabase database;
  late RecentsStore store;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    store = RecentsStore(database.db);
  });

  tearDown(() async {
    await database.close();
  });

  RecentEntry entry(String docType, String id, {required int at, String? title}) =>
      RecentEntry(
        docType: docType,
        docId: id,
        title: title ?? '$docType $id',
        openedAt: DateTime.fromMillisecondsSinceEpoch(at),
      );

  test('records and lists an opened record', () async {
    await store.record(entry('Customer', 'CUST-1', at: 1000));
    final list = await store.list();
    expect(list, hasLength(1));
    expect(list.single.docType, 'Customer');
    expect(list.single.docId, 'CUST-1');
    expect(list.single.title, 'Customer CUST-1');
  });

  test('lists newest first', () async {
    await store.record(entry('Customer', 'A', at: 1000));
    await store.record(entry('Customer', 'B', at: 2000));
    await store.record(entry('Customer', 'C', at: 1500));
    final ids = (await store.list()).map((e) => e.docId).toList();
    expect(ids, ['B', 'C', 'A']);
  });

  test('re-opening a record de-dupes and moves it to the top', () async {
    await store.record(entry('Customer', 'A', at: 1000));
    await store.record(entry('Customer', 'B', at: 2000));
    // Re-open A more recently with a refreshed title.
    await store.record(entry('Customer', 'A', at: 3000, title: 'ACME Corp'));
    final list = await store.list();
    expect(list.map((e) => e.docId), ['A', 'B']);
    expect(list.first.title, 'ACME Corp');
  });

  test('caps the list at maxEntries, keeping the newest', () async {
    for (var i = 0; i < RecentsStore.maxEntries + 5; i++) {
      await store.record(entry('Doc', 'D$i', at: 1000 + i));
    }
    final list = await store.list();
    expect(list, hasLength(RecentsStore.maxEntries));
    // Newest (highest timestamp) survives; oldest five are trimmed.
    expect(list.first.docId, 'D${RecentsStore.maxEntries + 4}');
    expect(list.map((e) => e.docId), isNot(contains('D0')));
  });

  test('clear empties the list', () async {
    await store.record(entry('Customer', 'A', at: 1000));
    await store.clear();
    expect(await store.list(), isEmpty);
  });
}
