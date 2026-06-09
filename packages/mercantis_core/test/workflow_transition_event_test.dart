import 'package:test/test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await database.close();
  });

  const workflow = WorkflowDefinition(
    id: 'wf-work-order',
    states: [
      WorkflowState(name: 'Draft', isDefault: true),
      WorkflowState(name: 'Completed'),
    ],
    transitions: [
      WorkflowTransition(
        id: 'wo-complete',
        fromState: 'Draft',
        toState: 'Completed',
        action: 'Complete',
      ),
    ],
  );

  test('transition publishes a WorkflowTransitionEvent when an emitter is set',
      () async {
    final emitter = EventEmitter();
    final events = <WorkflowTransitionEvent>[];
    emitter.subscribe<WorkflowTransitionEvent>(events.add);

    final engine = WorkflowEngine(database.db, emitter: emitter);
    final doc = Document(
      id: 'WO-0001',
      docType: 'Work Order',
      payload: {'workflow_state': 'Draft'},
    );

    await engine.transition(
      document: doc,
      workflow: workflow,
      action: 'Complete',
      userRoles: {'System Manager'},
    );

    expect(events, hasLength(1));
    final e = events.single;
    expect(e.documentId, 'WO-0001');
    expect(e.workflow, 'wf-work-order');
    expect(e.fromState, 'Draft');
    expect(e.toState, 'Completed');
    expect(e.action, 'Complete');
  });

  test('transition without an emitter still succeeds (no event)', () async {
    final engine = WorkflowEngine(database.db);
    final doc = Document(
      id: 'WO-0002',
      docType: 'Work Order',
      payload: {'workflow_state': 'Draft'},
    );

    final result = await engine.transition(
      document: doc,
      workflow: workflow,
      action: 'Complete',
      userRoles: {'System Manager'},
    );

    expect(result.payload['workflow_state'], 'Completed');
  });
}
