import 'package:sqflite_common/sqflite.dart';
import 'package:uuid/uuid.dart';

/// One log entry produced by `SendNotificationHandler` (ADR-048). It is the
/// canonical record of a notification that was emitted, regardless of which
/// channel(s) ultimately delivered it.
class NotificationLogEntry {
  final String id;
  final String appId;
  final String docType;
  final String documentId;

  /// Logical transport, e.g. `default` (in-app inbox), `email`, `push`.
  final String channel;

  /// User id, email address, or role name — meaning depends on the channel.
  /// `null` denotes the global feed.
  final String? recipient;
  final String subject;
  final String body;
  final DateTime emittedAt;

  NotificationLogEntry({
    String? id,
    required this.appId,
    required this.docType,
    required this.documentId,
    this.channel = 'default',
    this.recipient,
    this.subject = '',
    this.body = '',
    DateTime? emittedAt,
  })  : id = id ?? const Uuid().v4(),
        emittedAt = emittedAt ?? DateTime.now();
}

/// Sink for `SendNotificationHandler`. Implementations may log, persist, or fan
/// out to transports. The default ([InMemoryNotificationLog]) records entries
/// for inspection and is safe to use in tests; [SqliteNotificationLog] persists
/// them so the in-app inbox survives a restart.
abstract class NotificationLogWriter {
  Future<void> write(NotificationLogEntry entry);
}

/// In-memory notification sink. Records every entry in write order.
class InMemoryNotificationLog implements NotificationLogWriter {
  final List<NotificationLogEntry> entries = [];

  @override
  Future<void> write(NotificationLogEntry entry) async => entries.add(entry);

  void reset() => entries.clear();
}

/// [NotificationLogWriter] that persists each entry to the `notification_log`
/// table. Pair with [NotificationInbox] to read and mark-as-read from the same
/// table. Re-writing an entry with an existing id is a no-op.
class SqliteNotificationLog implements NotificationLogWriter {
  final Database _db;

  SqliteNotificationLog(this._db);

  @override
  Future<void> write(NotificationLogEntry entry) async {
    await _db.insert(
      'notification_log',
      {
        'id': entry.id,
        'app_id': entry.appId,
        'doc_type': entry.docType,
        'document_id': entry.documentId,
        'channel': entry.channel,
        'recipient': entry.recipient,
        'subject': entry.subject,
        'body': entry.body,
        'emitted_at': entry.emittedAt.millisecondsSinceEpoch,
        'read_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

/// Fan-out writer that delivers each entry to every wrapped sink in order. Lets
/// a host pair [SqliteNotificationLog] (persistence) with extra channels (a
/// console logger, a future email adapter, etc.) without touching the protocol.
class CompositeNotificationLog implements NotificationLogWriter {
  final List<NotificationLogWriter> sinks;

  CompositeNotificationLog(this.sinks);

  @override
  Future<void> write(NotificationLogEntry entry) async {
    for (final sink in sinks) {
      await sink.write(entry);
    }
  }
}

/// Sink that routes entries to [downstream] only when the entry's `channel`
/// matches one of the configured channel ids. Used to plug per-channel adapters
/// (email, push, webhook) into the broader notification pipeline.
class ChannelFilteredNotificationLog implements NotificationLogWriter {
  final Set<String> allowedChannels;
  final NotificationLogWriter downstream;

  ChannelFilteredNotificationLog({
    required this.allowedChannels,
    required this.downstream,
  });

  @override
  Future<void> write(NotificationLogEntry entry) async {
    if (!allowedChannels.contains(entry.channel)) return;
    await downstream.write(entry);
  }
}
