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

  group('audience queries (global + addressed)', () {
    setUp(() async {
      await log.write(entry(id: 'g', recipient: null, subject: 'Broadcast'));
      await log.write(entry(id: 'a', recipient: 'alice', subject: 'Hi Alice'));
      await log.write(
          entry(id: 'm', recipient: 'Manager', subject: 'For managers'));
      await log.write(entry(id: 'b', recipient: 'bob', subject: 'Hi Bob'));
    });

    test('entriesForAudience unions the global feed with addressed keys',
        () async {
      final items =
          await inbox.entriesForAudience(recipients: ['alice', 'Manager']);
      expect(items.map((e) => e.subject).toSet(),
          {'Broadcast', 'Hi Alice', 'For managers'});
      expect(items.map((e) => e.subject), isNot(contains('Hi Bob')));
    });

    test('an empty audience degrades to the global feed', () async {
      final items = await inbox.entriesForAudience(recipients: const []);
      expect(items.map((e) => e.subject), ['Broadcast']);
    });

    test('blank + duplicate keys are ignored', () async {
      final items = await inbox
          .entriesForAudience(recipients: ['alice', '', 'alice', '  ']);
      expect(items.map((e) => e.subject).toSet(), {'Broadcast', 'Hi Alice'});
    });

    test('unreadCountForAudience counts global + addressed', () async {
      expect(
          await inbox
              .unreadCountForAudience(recipients: ['alice', 'Manager']),
          3);
      expect(await inbox.unreadCountForAudience(recipients: const []),
          1); // global only
    });

    test('unreadCountForAudience(includeGlobal: false) counts addressed only',
        () async {
      // The badge count: the shared broadcast is excluded, only addressed rows.
      expect(
          await inbox.unreadCountForAudience(
              recipients: ['alice', 'Manager'], includeGlobal: false),
          2);
      // No addressed keys → nothing (the global feed doesn't count here).
      expect(
          await inbox.unreadCountForAudience(
              recipients: const [], includeGlobal: false),
          0);
    });

    test('markAllReadForAudience clears addressed rows but not shared broadcasts',
        () async {
      await inbox.markAllReadForAudience(recipients: ['alice']);
      // Alice's addressed message is read...
      expect(await inbox.unreadCount(recipient: 'alice'), 0);
      // ...but the shared broadcast is not — its read_at is global, so clearing
      // it here would mark it read for every operator. Others untouched.
      expect(await inbox.unreadCount(recipient: null), 1);
      expect(await inbox.unreadCount(recipient: 'bob'), 1);
      expect(await inbox.unreadCount(recipient: 'Manager'), 1);
      // The union count still includes the unread broadcast...
      expect(await inbox.unreadCountForAudience(recipients: ['alice']), 1);
      // ...but the addressed-only badge count — what "mark all read" governs —
      // is now fully cleared, so the bell zeroes out.
      expect(
          await inbox.unreadCountForAudience(
              recipients: ['alice'], includeGlobal: false),
          0);
    });
  });

  group('broadcast read receipts (per-viewer)', () {
    setUp(() async {
      await log.write(entry(id: 'g', recipient: null, subject: 'Broadcast'));
      await log.write(entry(id: 'a', recipient: 'alice', subject: 'Hi Alice'));
    });

    test('markBroadcastRead clears a broadcast for one viewer only', () async {
      await inbox.markBroadcastRead('g', viewerId: 'alice');

      // Alice sees the broadcast read; bob still sees it unread.
      final alice =
          await inbox.entriesForAudience(recipients: ['alice'], viewerId: 'alice');
      expect(alice.firstWhere((e) => e.id == 'g').isRead, isTrue);
      final bob =
          await inbox.entriesForAudience(recipients: ['bob'], viewerId: 'bob');
      expect(bob.firstWhere((e) => e.id == 'g').isRead, isFalse);

      // The shared column is never touched, so exact-match reads are unaffected.
      expect(await inbox.unreadCount(recipient: null), 1);
    });

    test('markBroadcastRead is idempotent, keeping the first read time',
        () async {
      await inbox.markBroadcastRead('g', viewerId: 'alice', at: DateTime(2026, 3, 1));
      await inbox.markBroadcastRead('g', viewerId: 'alice', at: DateTime(2026, 4, 1));
      final item = (await inbox.entriesForAudience(
              recipients: ['alice'], viewerId: 'alice'))
          .firstWhere((e) => e.id == 'g');
      expect(item.readAt, DateTime(2026, 3, 1));
    });

    test('unreadCountForAudience(viewerId) counts a broadcast until receipted',
        () async {
      // Broadcast + Hi Alice both unread for alice.
      expect(
          await inbox.unreadCountForAudience(
              recipients: ['alice'], viewerId: 'alice'),
          2);
      await inbox.markBroadcastRead('g', viewerId: 'alice');
      // Only the broadcast cleared for alice...
      expect(
          await inbox.unreadCountForAudience(
              recipients: ['alice'], viewerId: 'alice'),
          1);
      // ...but bob's audience still counts the broadcast.
      expect(
          await inbox.unreadCountForAudience(
              recipients: ['bob'], viewerId: 'bob'),
          1);
    });

    test('markAllReadForAudience(viewerId) zeroes the viewer without leaking',
        () async {
      await inbox.markAllReadForAudience(recipients: ['alice'], viewerId: 'alice');
      // Alice's whole audience (broadcast + addressed) is clear...
      expect(
          await inbox.unreadCountForAudience(
              recipients: ['alice'], viewerId: 'alice'),
          0);
      // ...but the shared broadcast read_at is untouched, so bob still sees it.
      expect(await inbox.unreadCount(recipient: null), 1);
      expect(
          await inbox.unreadCountForAudience(
              recipients: ['bob'], viewerId: 'bob'),
          1);
    });

    test('deleting a broadcast drops its receipts', () async {
      await inbox.markBroadcastRead('g', viewerId: 'alice');
      await inbox.delete('g');
      // Re-inserting the same id must not resurrect the old receipt.
      await log.write(entry(id: 'g', recipient: null, subject: 'Broadcast 2'));
      final alice = await inbox.entriesForAudience(
          recipients: ['alice'], viewerId: 'alice');
      expect(alice.firstWhere((e) => e.id == 'g').isRead, isFalse);
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
