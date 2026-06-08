import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Records the ids of every document an action runs against, so tests can
/// assert which documents a scheduled rule fanned out to.
class _RecordingHandler implements AutomationActionHandler {
  final List<String> ranOn = [];

  @override
  Future<void> execute(
    Document document,
    Map<String, dynamic> parameters,
    AutomationContext context,
  ) async {
    ranOn.add(document.id);
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late DocumentEngine engine;
  late EventEmitter emitter;
  late AutomationActionRegistry registry;
  late AutomationRunner runner;
  late _RecordingHandler handler;
  late AutomationContext context;
  const roles = {'System Manager'};

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final meta = MetadataRegistry(database.db);
    final composer = MetaComposer(meta, database.db);
    final sync = SyncEngine(database: database.db, registry: meta);
    emitter = EventEmitter();
    engine = DocumentEngine(
      database: database.db,
      registry: meta,
      metaComposer: composer,
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(database.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: emitter,
      deviceId: 'test-device',
      userId: 'test-user',
    );
    await meta.register(const DocType(
      id: 'Task',
      name: 'Task',
      fields: [
        FieldDefinition(key: 'title', label: 'Title', type: FieldType.data),
        FieldDefinition(key: 'status', label: 'Status', type: FieldType.data),
      ],
    ));

    handler = _RecordingHandler();
    registry = AutomationActionRegistry()..register('record', handler);
    runner = AutomationRunner(
      registry: registry,
      evaluator: ExpressionEvaluator(),
    );
    context = AutomationContext(
      documentEngine: engine,
      userId: 'test-user',
      emitter: emitter,
    );
  });

  tearDown(() => database.close());

  Future<String> task(String title, String status) async {
    final saved = await engine.save(
      Document(id: '', docType: 'Task', payload: {
        'title': title,
        'status': status,
      }),
      roles,
    );
    return saved.id;
  }

  AutomationRule scheduledRule({String? condition}) => AutomationRule(
        id: 'overdue-sweep',
        event: 'on_schedule',
        docType: 'Task',
        conditionExpression: condition,
        schedule: const AutomationSchedule(interval: 'daily'),
        actions: const [
          {'actionType': 'record', 'parameters': {}},
        ],
      );

  test('runScheduled fans out across every document of the docType', () async {
    final a = await task('A', 'open');
    final b = await task('B', 'done');

    await runner.runScheduled(scheduledRule(), context);

    expect(handler.ranOn, unorderedEquals([a, b]));
  });

  test('runScheduled honours the rule condition per document', () async {
    final open = await task('A', 'open');
    await task('B', 'done');

    await runner.runScheduled(
        scheduledRule(condition: 'status == "open"'), context);

    expect(handler.ranOn, [open]);
  });

  test('runScheduled with no docType runs actions once', () async {
    await runner.runScheduled(
      const AutomationRule(
        id: 'tick',
        event: 'on_schedule',
        schedule: AutomationSchedule(interval: 'hourly'),
        actions: [
          {'actionType': 'record', 'parameters': {}},
        ],
      ),
      context,
    );

    expect(handler.ranOn, hasLength(1));
  });

  test('isScheduled + JSON round-trip', () {
    final rule = scheduledRule(condition: 'status == "open"');
    expect(rule.isScheduled, isTrue);

    final restored = AutomationRule.fromJson(rule.toJson());
    expect(restored.isScheduled, isTrue);
    expect(restored.schedule?.interval, 'daily');
    expect(restored.conditionExpression, 'status == "open"');
    expect(restored.actions.single['actionType'], 'record');

    // A document-event rule has no schedule.
    final plain = AutomationRule.fromJson({
      'id': 'r',
      'event': 'on_save',
      'actions': [],
    });
    expect(plain.isScheduled, isFalse);
    expect(plain.schedule, isNull);
  });

  test('ExtensionPointResolver registers a scheduled rule that fires on tick',
      () async {
    final a = await task('A', 'open');
    final b = await task('B', 'done');

    final scheduler = SchedulerService(database.db);
    final manifest = AppManifest(
      id: 'tasks-app',
      version: '1.0.0',
      name: 'Tasks',
      automationRules: [scheduledRule()],
    );

    ExtensionPointResolver.resolve(
      manifest,
      emitter,
      scheduler,
      automationRunner: runner,
      automationContext: context,
    );

    await scheduler.tick(); // daily rule with no prior run is due immediately

    expect(handler.ranOn, unorderedEquals([a, b]));
  });
}
