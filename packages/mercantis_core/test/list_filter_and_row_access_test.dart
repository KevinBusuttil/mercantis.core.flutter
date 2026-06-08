import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers ADR-036 (typed ListFilter predicates pushed down to SQL) and ADR-037
/// (DocType.rowAccessExpression auto-applied by DocumentEngine.list).
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late DocumentEngine engine;
  const roles = {'System Manager'};

  Future<void> seed(DocType docType) async {
    final registry = MetadataRegistry(database.db);
    await registry.register(docType);
    engine = DocumentEngine(
      database: database.db,
      registry: registry,
      metaComposer: MetaComposer(registry, database.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(database.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: SyncEngine(database: database.db, registry: registry),
      emitter: EventEmitter(),
      deviceId: 'd',
      userId: 'alice',
    );
  }

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => database.close());

  group('ListFilter (ADR-036)', () {
    setUp(() async {
      await seed(const DocType(id: 'Inv', name: 'Inv', fields: [
        FieldDefinition(key: 'customer', label: 'C', type: FieldType.data),
        FieldDefinition(key: 'total', label: 'T', type: FieldType.currency),
      ]));
      for (final (c, t) in [('A', 100), ('B', 250), ('C', 500)]) {
        await engine.save(
          Document(id: '', docType: 'Inv', payload: {'customer': c, 'total': t}),
          roles,
        );
      }
    });

    Future<List<num>> totalsWhere(ListFilter f) async {
      final docs = await engine.list('Inv', predicates: [f], userRoles: roles);
      final out = [for (final d in docs) d.payload['total'] as num]..sort();
      return out;
    }

    test('gt / gte / lt push down to SQL', () async {
      expect(await totalsWhere(const ListFilter.gt('total', 100)), [250, 500]);
      expect(await totalsWhere(const ListFilter.gte('total', 250)), [250, 500]);
      expect(await totalsWhere(const ListFilter.lt('total', 250)), [100]);
    });

    test('between is inclusive', () async {
      expect(await totalsWhere(ListFilter.between('total', 100, 250)),
          [100, 250]);
    });

    test('isIn / notIn over customer', () async {
      final inDocs = await engine.list('Inv',
          predicates: const [ListFilter.isIn('customer', ['A', 'C'])],
          userRoles: roles);
      expect(inDocs.length, 2);
      final emptyIn = await engine.list('Inv',
          predicates: const [ListFilter.isIn('customer', [])], userRoles: roles);
      expect(emptyIn, isEmpty); // IN () matches nothing
    });

    test('like matches a pattern', () async {
      final docs = await engine.list('Inv',
          predicates: const [ListFilter.like('customer', 'B')], userRoles: roles);
      expect(docs.single.payload['customer'], 'B');
    });
  });

  group('rowAccessExpression (ADR-037)', () {
    test('auto-applies the DocType row filter to list()', () async {
      await seed(const DocType(
        id: 'Note',
        name: 'Note',
        rowAccessExpression: 'owner == user.id',
        fields: [
          FieldDefinition(key: 'owner', label: 'Owner', type: FieldType.data),
          FieldDefinition(key: 'body', label: 'Body', type: FieldType.data),
        ],
      ));
      await engine.save(
        Document(id: '', docType: 'Note', payload: {'owner': 'alice', 'body': 'mine'}),
        roles,
      );
      await engine.save(
        Document(id: '', docType: 'Note', payload: {'owner': 'bob', 'body': 'theirs'}),
        roles,
      );

      // userId is 'alice' — only her row comes back, without any caller filter.
      final docs = await engine.list('Note', userRoles: roles);
      expect(docs.length, 1);
      expect(docs.single.payload['owner'], 'alice');
    });
  });
}
