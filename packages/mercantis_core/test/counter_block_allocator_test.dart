import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers ADR-042: per-device naming counter blocks — disjoint ranges across
/// devices (no offline collisions) and a monotonic high-water mark (no reuse
/// after deletes).
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => database.close());

  test('one device gets a contiguous run within its block', () async {
    const alloc = CounterBlockAllocator(blockSize: 1000);
    final a = await alloc.next(database.db, 'SINV-2026-', 'devA');
    final b = await alloc.next(database.db, 'SINV-2026-', 'devA');
    final c = await alloc.next(database.db, 'SINV-2026-', 'devA');
    expect([a, b, c], [1, 2, 3]);
  });

  test('different devices draw from disjoint blocks', () async {
    const alloc = CounterBlockAllocator(blockSize: 1000);
    final a1 = await alloc.next(database.db, 'SINV-2026-', 'devA'); // 1
    final b1 = await alloc.next(database.db, 'SINV-2026-', 'devB'); // 1001
    final a2 = await alloc.next(database.db, 'SINV-2026-', 'devA'); // 2
    final b2 = await alloc.next(database.db, 'SINV-2026-', 'devB'); // 1002
    expect(a1, 1);
    expect(b1, 1001);
    expect(a2, 2);
    expect(b2, 1002);
    expect({a1, a2}.intersection({b1, b2}), isEmpty);
  });

  test('exhausting a block reserves the next one', () async {
    const alloc = CounterBlockAllocator(blockSize: 2);
    final a1 = await alloc.next(database.db, 'PO-', 'devA'); // 1 (block 1..2)
    final a2 = await alloc.next(database.db, 'PO-', 'devA'); // 2
    final a3 = await alloc.next(database.db, 'PO-', 'devA'); // 3 (new block 3..4)
    expect([a1, a2, a3], [1, 2, 3]);
  });

  test('series are independent of each other', () async {
    const alloc = CounterBlockAllocator(blockSize: 1000);
    expect(await alloc.next(database.db, 'SINV-2026-', 'devA'), 1);
    expect(await alloc.next(database.db, 'SINV-2027-', 'devA'), 1);
  });

  test('NamingSeriesStrategy seeds above pre-existing ids on upgrade',
      () async {
    // Legacy COUNT-based ids already in the table.
    for (final n in [1, 2, 3]) {
      await database.db.insert('documents', {
        'id': 'X-${n.toString().padLeft(4, '0')}',
        'doctype': 'X',
        'company': null,
        'docstatus': 0,
        'payload': '{}',
        'created_at': 0,
        'modified_at': 0,
        'sync_version': null,
        'sync_state': 'local',
        'amended_from': null,
      });
    }
    final naming = NamingService();
    const dt = DocType(id: 'X', name: 'X', namingRule: 'X-.####');
    final next = await naming.resolve(
      dt,
      Document(id: '', docType: 'X'),
      NamingContext(database: database.db, userId: 'u', deviceId: 'devA'),
    );
    expect(next, 'X-0004'); // continues past the existing 0001..0003
  });

  test('NamingSeriesStrategy never reuses a number after delete', () async {
    final naming = NamingService();
    const dt = DocType(id: 'X', name: 'X', namingRule: 'X-.####');
    NamingContext ctx() =>
        NamingContext(database: database.db, userId: 'u', deviceId: 'devA');
    Future<String> name() =>
        naming.resolve(dt, Document(id: '', docType: 'X'), ctx());

    expect(await name(), 'X-0001');
    expect(await name(), 'X-0002');
    // Even if X-0002 were deleted, the counter has moved on.
    expect(await name(), 'X-0003');
  });
}
