import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers ADR-048: the persistent notification log + in-app inbox reader.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late SqliteNotificationLog log;
  late NotificationInbox inbox;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    log = SqliteNotificationLog(database.db);
    inbox = NotificationInbox(database.db);
  });

  tearDown(() => database.close());

  NotificationLogEntry entry({
    String? id,
    String? recipient,
    String subject = 'Subject',
    DateTime? emittedAt,
  }) =>
      NotificationLogEntry(
        id: id,
        appId: 'erp',
        docType: 'Sales Invoice',
        documentId: 'SINV-0001',
        recipient: recipient,
        subject: subject,
        body: 'Body',
        emittedAt: emittedAt,
      );

  group('persistence + reads', () {
    test('writes survive and read back for a recipient', () async {
      await log.write(entry(recipient: 'alice', subject: 'Hi Alice'));
      await log.write(entry(recipient: 'bob', subject: 'Hi Bob'));

      final alice = await inbox.entries(recipient: 'alice');
      expect(alice, hasLength(1));
      expect(alice.single.subject, 'Hi Alice');
      expect(alice.single.isRead, isFalse);
      expect(alice.single.docType, 'Sales Invoice');
    });

    test('null recipient is the global feed, distinct from named recipients',
        () async {
      await log.write(entry(recipient: null, subject: 'Broadcast'));
      await log.write(entry(recipient: 'alice'));

      final global = await inbox.entries(recipient: null);
      expect(global.map((e) => e.subject), ['Broadcast']);
    });

    test('newest first by emitted_at', () async {
      await log.write(entry(
          id: 'old',
          recipient: 'alice',
          subject: 'Old',
          emittedAt: DateTime(2026, 1, 1)));
      await log.write(entry(
          id: 'new',
          recipient: 'alice',
          subject: 'New',
          emittedAt: DateTime(2026, 6, 1)));

      final items = await inbox.entries(recipient: 'alice');
      expect(items.map((e) => e.subject), ['New', 'Old']);
    });

    test('limit + offset paginate', () async {
      for (var i = 0; i < 5; i++) {
        await log.write(entry(
            id: 'n$i', recipient: 'alice', emittedAt: DateTime(2026, 1, 1 + i)));
      }
      final page = await inbox.entries(recipient: 'alice', limit: 2, offset: 2);
      expect(page, hasLength(2));
    });

    test('re-writing an existing id is a no-op', () async {
      await log.write(entry(id: 'dup', recipient: 'alice', subject: 'First'));
      await log.write(entry(id: 'dup', recipient: 'alice', subject: 'Second'));

      final items = await inbox.entries(recipient: 'alice');
      expect(items, hasLength(1));
      expect(items.single.subject, 'First'); // original kept
    });
  });

  group('unread state', () {
    test('unreadOnly + unreadCount track read state', () async {
      await log.write(entry(id: 'a', recipient: 'alice'));
      await log.write(entry(id: 'b', recipient: 'alice'));
      expect(await inbox.unreadCount(recipient: 'alice'), 2);

      await inbox.markRead('a');
      expect(await inbox.unreadCount(recipient: 'alice'), 1);
      final unread = await inbox.entries(recipient: 'alice', unreadOnly: true);
      expect(unread.map((e) => e.id), ['b']);
    });

    test('markRead is idempotent and preserves the original timestamp',
        () async {
      await log.write(entry(id: 'a', recipient: 'alice'));
      await inbox.markRead('a', at: DateTime(2026, 3, 1));
      await inbox.markRead('a', at: DateTime(2026, 4, 1)); // should not overwrite

      final item =
          (await inbox.entries(recipient: 'alice')).single;
      expect(item.isRead, isTrue);
      expect(item.readAt, DateTime(2026, 3, 1));
    });

    test('markAllRead clears the recipient feed only', () async {
      await log.write(entry(id: 'a', recipient: 'alice'));
      await log.write(entry(id: 'b', recipient: 'alice'));
      await log.write(entry(id: 'c', recipient: 'bob'));

      await inbox.markAllRead(recipient: 'alice');
      expect(await inbox.unreadCount(recipient: 'alice'), 0);
      expect(await inbox.unreadCount(recipient: 'bob'), 1);
    });
  });

  test('delete removes an inbox item', () async {
    await log.write(entry(id: 'a', recipient: 'alice'));
    await inbox.delete('a');
    expect(await inbox.entries(recipient: 'alice'), isEmpty);
  });

  group('writer composition', () {
    test('CompositeNotificationLog fans out to every sink', () async {
      final mem = InMemoryNotificationLog();
      final composite = CompositeNotificationLog([log, mem]);

      await composite.write(entry(id: 'a', recipient: 'alice'));

      expect(mem.entries, hasLength(1));
      expect(await inbox.entries(recipient: 'alice'), hasLength(1));
    });

    test('ChannelFilteredNotificationLog only forwards matching channels',
        () async {
      final mem = InMemoryNotificationLog();
      final emailOnly = ChannelFilteredNotificationLog(
          allowedChannels: {'email'}, downstream: mem);

      await emailOnly.write(NotificationLogEntry(
          appId: 'erp',
          docType: 'X',
          documentId: '1',
          channel: 'default'));
      expect(mem.entries, isEmpty);

      await emailOnly.write(NotificationLogEntry(
          appId: 'erp', docType: 'X', documentId: '1', channel: 'email'));
      expect(mem.entries, hasLength(1));
    });
  });

  group('SendNotificationHandler', () {
    test('interpolate expands {field}, leaves unknowns literal', () {
      final doc = Document(
          id: 'd', docType: 'Task', payload: {'customer': 'Acme', 'n': 3});
      expect(SendNotificationHandler.interpolate('Hi {customer} x{n}', doc),
          'Hi Acme x3');
      expect(SendNotificationHandler.interpolate('Hi {missing}', doc),
          'Hi {missing}');
      expect(SendNotificationHandler.interpolate('no placeholders', doc),
          'no placeholders');
    });

    test('writes an interpolated entry to the inbox via the context', () async {
      final composer = MetaComposer(MetadataRegistry(database.db), database.db);
      final registry = MetadataRegistry(database.db);
      final engine = DocumentEngine(
        database: database.db,
        registry: registry,
        metaComposer: composer,
        permissionEngine: const PermissionEngine(),
        workflowEngine: WorkflowEngine(database.db),
        expressionEvaluator: ExpressionEvaluator(),
        namingService: NamingService(),
        syncEngine: SyncEngine(database: database.db, registry: registry),
        emitter: EventEmitter(),
        deviceId: 'd',
        userId: 'u',
      );
      final context = AutomationContext(
        documentEngine: engine,
        userId: 'u',
        emitter: EventEmitter(),
        appId: 'erp',
        notificationLog: log,
      );
      final doc = Document(
          id: 'SINV-9', docType: 'Sales Invoice', payload: {'customer': 'Acme'});

      await const SendNotificationHandler().execute(
        doc,
        {
          'recipient': 'alice',
          'subject': 'Invoice for {customer}',
          'body': 'Dear {customer}, your invoice is ready.',
          'channel': 'default',
        },
        context,
      );

      final items = await inbox.entries(recipient: 'alice');
      expect(items, hasLength(1));
      expect(items.single.subject, 'Invoice for Acme');
      expect(items.single.body, 'Dear Acme, your invoice is ready.');
      expect(items.single.documentId, 'SINV-9');
      expect(items.single.appId, 'erp');
    });

    test('no sink configured → no-op', () async {
      final composer = MetaComposer(MetadataRegistry(database.db), database.db);
      final registry = MetadataRegistry(database.db);
      final engine = DocumentEngine(
        database: database.db,
        registry: registry,
        metaComposer: composer,
        permissionEngine: const PermissionEngine(),
        workflowEngine: WorkflowEngine(database.db),
        expressionEvaluator: ExpressionEvaluator(),
        namingService: NamingService(),
        syncEngine: SyncEngine(database: database.db, registry: registry),
        emitter: EventEmitter(),
        deviceId: 'd',
        userId: 'u',
      );
      final context = AutomationContext(
          documentEngine: engine, userId: 'u', emitter: EventEmitter());

      await const SendNotificationHandler().execute(
        Document(id: 'x', docType: 'Y'),
        {'recipient': 'alice', 'subject': 'Hi'},
        context,
      );
      expect(await inbox.entries(recipient: 'alice'), isEmpty);
    });
  });
}
