import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// A defaults hook: fills a blank `currency` on create, so a draft that omits a
/// required field still validates.
class _DefaultCurrency extends DocumentInterceptor {
  const _DefaultCurrency();
  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (isNew && (doc.payload['currency'] == null || doc.payload['currency'] == '')) {
      doc.payload['currency'] = 'USD';
    }
  }
}

/// A posting-time guard: blocks submit unless a posting_date is present.
class _RequirePostingDate extends DocumentInterceptor {
  const _RequirePostingDate();
  @override
  Future<void> beforeSubmit(
      DocumentEngine engine, Document doc, DocType docType) async {
    if (doc.payload['posting_date'] == null) {
      throw DocumentEngineError.malformedRow('posting_date is required to submit');
    }
  }
}

/// Covers the [DocumentInterceptor] seam: beforeSave may fill defaults (run
/// before validation) and beforeSubmit may veto a submission.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  const roles = {'System Manager'};

  Future<DocumentEngine> engineWith(List<DocumentInterceptor> hooks) async {
    final registry = MetadataRegistry(database.db);
    await registry.register(const DocType(
      id: 'Inv',
      name: 'Inv',
      isSubmittable: true,
      fields: [
        FieldDefinition(
            key: 'currency', label: 'Currency', type: FieldType.data, required: true),
        FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date),
      ],
    ));
    return DocumentEngine(
      database: database.db,
      registry: registry,
      metaComposer: MetaComposer(registry, database.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(database.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: SyncEngine(database: database.db, registry: registry),
      emitter: EventEmitter(),
      deviceId: 'test-device',
      userId: 'test-user',
      interceptors: hooks,
    );
  }

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  test('beforeSave fills a default that satisfies a required field', () async {
    final engine = await engineWith(const [_DefaultCurrency()]);
    // currency omitted; without the hook this would fail required validation.
    final saved = await engine.save(
      Document(id: '', docType: 'Inv', payload: {'posting_date': '2026-01-01'}),
      roles,
    );
    final reloaded = await engine.fetch('Inv', saved.id);
    expect(reloaded!.payload['currency'], 'USD');
  });

  test('beforeSubmit can veto a submission', () async {
    final engine = await engineWith(const [_RequirePostingDate()]);
    final draft = await engine.save(
      Document(id: '', docType: 'Inv', payload: {'currency': 'USD'}),
      roles,
    );
    await expectLater(
      engine.submit(draft, roles),
      throwsA(isA<DocumentEngineError>()),
    );
    final reloaded = await engine.fetch('Inv', draft.id);
    expect(reloaded!.docStatus, 0); // still a draft

    reloaded.payload['posting_date'] = '2026-01-01';
    final ok = await engine.save(reloaded, roles);
    final submitted = await engine.submit(ok, roles);
    expect(submitted.docStatus, 1);
  });
}
