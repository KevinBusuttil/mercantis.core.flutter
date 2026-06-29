import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// C2 (substrate): the PostingBatch primitive + store — deterministic ids,
/// idempotency, status/error capture, reversal linkage, and the per-source /
/// per-status diagnostics queries. (The atomic-with-submit `UnitOfWork` path
/// depends on C1/ExecutionContext and lands with it.)
void main() {
  setUpAll(sqfliteFfiInit);

  test('deterministic batch id', () {
    expect(PostingBatch.makeId('INV-1'), 'POST-INV-1-v1');
    expect(PostingBatch.makeId('INV-1', version: 2), 'POST-INV-1-v2');
  });

  group('PostingBatchStore', () {
    late MercantisDatabase database;
    late PostingBatchStore store;

    setUp(() async {
      database = await MercantisDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      store = PostingBatchStore(database);
    });

    tearDown(() => database.close());

    test('upsert + read round-trips all fields', () async {
      final posted = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      await store.upsert(PostingBatch(
        id: PostingBatch.makeId('a1'),
        sourceType: 'Sales Invoice',
        sourceId: 'a1',
        status: PostingStatus.posted,
        postedAt: posted,
        postedBy: 'tester',
      ));

      final b = await store.batch(PostingBatch.makeId('a1'));
      expect(b, isNotNull);
      expect(b!.status, PostingStatus.posted);
      expect(b.sourceType, 'Sales Invoice');
      expect(b.postedBy, 'tester');
      expect(b.postedAt, posted);
      expect(await store.exists(PostingBatch.makeId('a1')), isTrue);
      expect(await store.exists(PostingBatch.makeId('missing')), isFalse);
    });

    test('upsert replaces on the same id (idempotent re-post)', () async {
      final id = PostingBatch.makeId('a2');
      await store.upsert(PostingBatch(
          id: id, sourceType: 'Note', sourceId: 'a2', status: PostingStatus.pending));
      await store.upsert(PostingBatch(
          id: id, sourceType: 'Note', sourceId: 'a2', status: PostingStatus.posted));

      final all = await store.batchesForSource('Note', 'a2');
      expect(all.length, 1);
      expect(all.single.status, PostingStatus.posted);
    });

    test('queries by status preserve error fields', () async {
      await store.upsert(PostingBatch(
          id: PostingBatch.makeId('b1'),
          sourceType: 'Note',
          sourceId: 'b1',
          status: PostingStatus.posted));
      await store.upsert(PostingBatch(
          id: PostingBatch.makeId('b2'),
          sourceType: 'Note',
          sourceId: 'b2',
          status: PostingStatus.failed,
          errorCode: 'UNBALANCED',
          errorMessage: 'debits != credits'));

      expect((await store.batchesWithStatus(PostingStatus.posted)).length, 1);
      final failed = await store.batchesWithStatus(PostingStatus.failed);
      expect(failed.length, 1);
      expect(failed.single.errorCode, 'UNBALANCED');
      expect(failed.single.errorMessage, 'debits != credits');
    });

    test('currentBatch returns the highest-version attempt', () async {
      await store.upsert(PostingBatch(
          id: PostingBatch.makeId('c1'),
          sourceType: 'Note',
          sourceId: 'c1',
          status: PostingStatus.reversed));
      await store.upsert(PostingBatch(
          id: PostingBatch.makeId('c1', version: 2),
          sourceType: 'Note',
          sourceId: 'c1',
          version: 2,
          status: PostingStatus.posted,
          reversalOfBatch: PostingBatch.makeId('c1')));

      final current = await store.currentBatch('Note', 'c1');
      expect(current!.version, 2);
      expect(current.status, PostingStatus.posted);
      expect(current.reversalOfBatch, PostingBatch.makeId('c1'));

      final history = await store.batchesForSource('Note', 'c1');
      expect(history.map((b) => b.version), [1, 2]);
    });
  });
}
