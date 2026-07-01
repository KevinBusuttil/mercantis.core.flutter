import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// C5 — permission granularity: a distinct `cancel` authority (separate from
/// `delete`) plus the opt-in `failClosed` mode that stops a `delete` grant from
/// implicitly covering cancel on submittable DocTypes.
void main() {
  const engine = PermissionEngine();

  // Open (default) submittable DocType: a delete grant still covers cancel.
  const openVoucher = DocType(
    id: 'Voucher',
    name: 'Voucher',
    isSubmittable: true,
    permissions: [
      // Clerk can delete but was never granted cancel explicitly.
      PermissionRule(
          role: 'Clerk', read: true, write: true, create: true,
          submit: true, delete: true),
      // Cashier can cancel explicitly but cannot delete.
      PermissionRule(role: 'Cashier', read: true, cancel: true),
      PermissionRule(role: 'Viewer', read: true),
    ],
    fields: [FieldDefinition(key: 'title', type: FieldType.data, label: 'Title')],
  );

  // Fail-closed submittable DocType: cancel must be granted explicitly.
  const strictVoucher = DocType(
    id: 'StrictVoucher',
    name: 'StrictVoucher',
    isSubmittable: true,
    failClosed: true,
    permissions: [
      PermissionRule(
          role: 'Clerk', read: true, write: true, create: true,
          submit: true, delete: true),
      PermissionRule(role: 'Manager', read: true, submit: true, cancel: true),
    ],
    fields: [FieldDefinition(key: 'title', type: FieldType.data, label: 'Title')],
  );

  bool can(String role, DocumentOperation op, DocType on) =>
      engine.canPerform(operation: op, on: on, userRoles: {role});

  group('PermissionEngine.canPerform — cancel granularity', () {
    test('cancel is distinct from submit/amend/delete', () {
      // Cashier has ONLY cancel: it grants cancel and nothing else.
      expect(can('Cashier', DocumentOperation.cancel, openVoucher), isTrue);
      expect(can('Cashier', DocumentOperation.submit, openVoucher), isFalse);
      expect(can('Cashier', DocumentOperation.amend, openVoucher), isFalse);
      expect(can('Cashier', DocumentOperation.delete, openVoucher), isFalse);
      expect(can('Cashier', DocumentOperation.write, openVoucher), isFalse);
    });

    test('open mode: a delete grant implicitly covers cancel (back-compat)', () {
      expect(can('Clerk', DocumentOperation.delete, openVoucher), isTrue);
      expect(can('Clerk', DocumentOperation.cancel, openVoucher), isTrue);
    });

    test('fail-closed mode: delete no longer covers cancel', () {
      expect(can('Clerk', DocumentOperation.delete, strictVoucher), isTrue);
      expect(can('Clerk', DocumentOperation.cancel, strictVoucher), isFalse);
      // An explicit cancel grant still works.
      expect(can('Manager', DocumentOperation.cancel, strictVoucher), isTrue);
    });

    test('a role with no matching rule is denied cancel', () {
      expect(can('Viewer', DocumentOperation.cancel, openVoucher), isFalse);
      expect(can('Nobody', DocumentOperation.cancel, strictVoucher), isFalse);
    });

    test('superuser bypasses regardless of fail-closed', () {
      expect(
          engine.canPerform(
              operation: DocumentOperation.cancel,
              on: strictVoucher,
              userRoles: {'System Manager'}),
          isTrue);
    });
  });

  group('PermissionRule / DocType JSON round-trip', () {
    test('cancel + failClosed survive serialization', () {
      final rule = PermissionRule.fromJson(
          const PermissionRule(role: 'X', cancel: true).toJson());
      expect(rule.cancel, isTrue);
      final dt = DocType.fromJson(strictVoucher.toJson());
      expect(dt.failClosed, isTrue);
      expect(dt.permissions.firstWhere((p) => p.role == 'Manager').cancel, isTrue);
    });
  });

  group('DocumentEngine.cancel honours the cancel authority', () {
    setUpAll(sqfliteFfiInit);
    late MercantisDatabase db;
    late DocumentEngine docEngine;

    setUp(() async {
      db = await MercantisDatabase.open(
          factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final registry = MetadataRegistry(db.db);
      await registry.register(strictVoucher);
      docEngine = DocumentEngine(
        database: db.db,
        registry: registry,
        metaComposer: MetaComposer(registry, db.db),
        permissionEngine: const PermissionEngine(),
        workflowEngine: WorkflowEngine(db.db),
        expressionEvaluator: ExpressionEvaluator(),
        namingService: NamingService(),
        syncEngine: SyncEngine(database: db.db, registry: registry),
        emitter: EventEmitter(),
        deviceId: 'd',
        userId: 'u',
      );
    });

    tearDown(() => db.close());

    test('a Clerk (delete but not cancel) is denied cancel on a fail-closed type',
        () async {
      // Clerk creates + submits, but cannot cancel under fail-closed.
      final draft = await docEngine.save(
          Document(id: '', docType: 'StrictVoucher', payload: {'title': 't'}),
          const {'Clerk'});
      final submitted = await docEngine.submit(draft, const {'Clerk'});
      await expectLater(
        docEngine.cancel(submitted, const {'Clerk'}),
        throwsA(isA<DocumentEngineError>()),
      );
    });

    test('a Manager with an explicit cancel grant can cancel', () async {
      final draft = await docEngine.save(
          Document(id: '', docType: 'StrictVoucher', payload: {'title': 't'}),
          const {'Clerk'});
      final submitted = await docEngine.submit(draft, const {'Clerk'});
      final cancelled = await docEngine.cancel(submitted, const {'Manager'});
      expect(cancelled.docStatus, 2);
    });
  });
}
