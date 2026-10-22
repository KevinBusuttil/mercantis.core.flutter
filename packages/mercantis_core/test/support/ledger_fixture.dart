import 'package:mercantis_core/mercantis_core.dart';

/// A tiny two-DocType schema (a submittable invoice with a `lines` child
/// table) for crash-safety, backup and restore tests. Shared by in-process
/// tests and the child processes under `test/fault/` that get killed
/// mid-write.
const testRoles = {'System Manager'};

Future<DocumentEngine> buildTestEngine(
  MercantisDatabase database, {
  List<DocumentInterceptor> interceptors = const [],
  String deviceId = 'test-device',
}) async {
  final registry = MetadataRegistry(database.db);
  await registry.register(const DocType(
    id: 'InvLine',
    name: 'InvLine',
    isChild: true,
    fields: [
      FieldDefinition(key: 'description', label: 'Description', type: FieldType.data),
      FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency),
    ],
  ));
  await registry.register(const DocType(
    id: 'Inv',
    name: 'Inv',
    isSubmittable: true,
    fields: [
      FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.data),
      FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency),
      FieldDefinition(
          key: 'lines',
          label: 'Lines',
          type: FieldType.table,
          tableDocType: 'InvLine',
          options: 'InvLine'),
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
    deviceId: deviceId,
    userId: 'test-user',
    interceptors: interceptors,
  );
}

/// An `Inv` draft with [lineCount] lines of 1.00 each.
Document invoice(String id, {int lineCount = 3, String customer = 'Acme'}) {
  final doc = Document(id: id, docType: 'Inv', payload: {
    'customer': customer,
    'total': lineCount * 1.0,
  });
  doc.children['lines'] = [
    for (var i = 0; i < lineCount; i++)
      ChildRow(
        id: '',
        parentId: id,
        parentDocType: 'Inv',
        tableName: 'lines',
        rowIndex: i,
        payload: {'description': 'line $i', 'amount': 1.0},
      ),
  ];
  return doc;
}
