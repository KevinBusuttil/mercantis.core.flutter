import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Numbering hold and recovery series (schema v9): what a host relies on
/// after restoring an older backup whose later numbers cannot be verified.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  const docType = DocType(
      id: 'Sales Invoice',
      name: 'Sales Invoice',
      module: 'test',
      namingRule: 'SINV-.YYYY.-.####',
      fields: []);
  const other = DocType(
      id: 'Task',
      name: 'Task',
      module: 'test',
      namingRule: 'TASK-.####',
      fields: []);

  setUp(() async {
    database = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });
  tearDown(() => database.close());

  Future<String> mint(DocType dt) =>
      NamingSeriesStrategy(dt.namingRule!).resolve(
          dt,
          Document(id: '', docType: dt.name, payload: const {}),
          NamingContext(database: database.db, userId: 'u', deviceId: 'dev'));

  Future<String> mintWith(DocType dt) => NamingService().resolve(
      dt,
      Document(id: '', docType: dt.name, payload: const {}),
      NamingContext(database: database.db, userId: 'u', deviceId: 'dev'));

  test('a hold refuses to mint and consumes no number', () async {
    expect(await mintWith(docType), endsWith('0001'));
    await NamingSeriesPolicyStore.write(
        database.db,
        const NamingSeriesPolicy(
            docType: 'Sales Invoice', hold: true, holdReason: 'decide first'));
    await expectLater(
        mintWith(docType),
        throwsA(isA<NamingHoldException>()
            .having((e) => e.message, 'message', 'decide first')));
    // Another DocType is not affected.
    expect(await mintWith(other), 'TASK-0001');
    await NamingSeriesPolicyStore.write(
        database.db, const NamingSeriesPolicy(docType: 'Sales Invoice'));
    expect(await mintWith(docType), endsWith('0002'),
        reason: 'the refused attempt did not use a number');
  });

  test('a recovery segment starts a distinct series', () async {
    final normal = await mintWith(docType);
    await NamingSeriesPolicyStore.write(database.db,
        const NamingSeriesPolicy(docType: 'Sales Invoice', segment: 'R1'));
    final recovery = await mintWith(docType);
    final year = DateTime.now().year;
    expect(normal, 'SINV-.$year.-0001');
    expect(recovery, 'SINV-.$year.-R1-0001');
  });

  test('segments must be short and id-safe', () async {
    expect(
        () => NamingSeriesPolicyStore.write(database.db,
            const NamingSeriesPolicy(docType: 'Sales Invoice', segment: 'r-1')),
        throwsArgumentError);
  });

  test('issuedThrough reports consumed numbers, and raise never lowers',
      () async {
    const alloc = CounterBlockAllocator();
    for (var i = 0; i < 5; i++) {
      await alloc.next(database.db, 'SINV-2026-', 'devA');
    }
    expect((await alloc.issuedThrough(database.db))['SINV-2026-'], 5,
        reason: 'the reserved block runs to 1000, but only 5 were issued');
    expect(await alloc.raiseNextNumber(database.db, 'SINV-2026-', 3), isFalse);
    expect(await alloc.raiseNextNumber(database.db, 'SINV-2026-', 9), isTrue);
    expect(await alloc.next(database.db, 'SINV-2026-', 'devA'), 9);
    expect((await alloc.issuedThrough(database.db))['SINV-2026-'], 9);
  });

  test('a database from before v9 has no policy and mints normally', () async {
    await database.db.execute('DROP TABLE naming_series_policy');
    expect(await NamingSeriesPolicyStore.read(database.db, 'Sales Invoice'),
        isNull);
    expect(await mint(docType), isNotEmpty);
  });
}
