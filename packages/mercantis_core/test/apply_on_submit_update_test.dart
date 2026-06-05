import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers [DocumentEngine.applyOnSubmitUpdate]: the sanctioned way to mutate a
/// submitted document, restricted to `allowOnSubmit` fields. This is what lets
/// the ledger spine keep an invoice's `outstanding_amount` current after
/// submit, which plain [DocumentEngine.save] refuses.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late DocumentEngine engine;
  const roles = {'System Manager'};

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final registry = MetadataRegistry(database.db);
    final composer = MetaComposer(registry, database.db);
    final sync = SyncEngine(database: database.db, registry: registry);
    engine = DocumentEngine(
      database: database.db,
      registry: registry,
      metaComposer: composer,
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(database.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: EventEmitter(),
      deviceId: 'test-device',
      userId: 'test-user',
    );

    await registry.register(const DocType(
      id: 'Inv',
      name: 'Inv',
      isSubmittable: true,
      fields: [
        FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.data),
        FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency),
        FieldDefinition(
            key: 'outstanding_amount',
            label: 'Outstanding',
            type: FieldType.currency,
            allowOnSubmit: true),
      ],
    ));
  });

  Future<Document> submittedInvoice() async {
    final draft = Document(id: '', docType: 'Inv', payload: {
      'customer': 'C1',
      'grand_total': 1000,
      'outstanding_amount': 1000,
    });
    final saved = await engine.save(draft, roles);
    return engine.submit(saved, roles);
  }

  test('updates an allowOnSubmit field on a submitted doc', () async {
    final inv = await submittedInvoice();
    inv.payload['outstanding_amount'] = 600;

    await engine.applyOnSubmitUpdate(inv, roles);

    final reloaded = await engine.fetch('Inv', inv.id);
    expect(reloaded!.docStatus, 1);
    expect(reloaded.payload['outstanding_amount'], 600);
  });

  test('rejects changes to a non-allowOnSubmit field', () async {
    final inv = await submittedInvoice();
    inv.payload['grand_total'] = 2000;

    expect(
      () => engine.applyOnSubmitUpdate(inv, roles),
      throwsA(isA<DocumentEngineError>()
          .having((e) => e.humanMessage, 'message', contains('grand_total'))),
    );
  });

  test('refuses to run on a draft (docStatus 0)', () async {
    final draft = await engine.save(
      Document(id: '', docType: 'Inv', payload: {'outstanding_amount': 5}),
      roles,
    );
    expect(
      () => engine.applyOnSubmitUpdate(draft, roles),
      throwsA(isA<DocumentEngineError>()),
    );
  });
}
