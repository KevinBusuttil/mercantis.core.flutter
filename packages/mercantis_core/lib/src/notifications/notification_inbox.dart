import 'package:sqflite_common/sqflite.dart';

/// One row materialised from `notification_log`. Mirrors a
/// `NotificationLogEntry` plus the persistence-specific [readAt] flag the
/// in-app inbox uses for unread badges.
class NotificationInboxItem {
  final String id;
  final String appId;
  final String docType;
  final String documentId;
  final String channel;
  final String? recipient;
  final String subject;
  final String body;
  final DateTime emittedAt;
  final DateTime? readAt;

  const NotificationInboxItem({
    required this.id,
    required this.appId,
    required this.docType,
    required this.documentId,
    required this.channel,
    required this.recipient,
    required this.subject,
    required this.body,
    required this.emittedAt,
    required this.readAt,
  });

  bool get isRead => readAt != null;
}

/// In-app notification inbox (ADR-048). The "channel" in question is the
/// persisted `notification_log` table itself: every notification a
/// [SqliteNotificationLog] write produces becomes available here. Provides the
/// reader API — list a recipient's notifications, count unread, mark read, and
/// delete — over the same table the writer fills.
class NotificationInbox {
  final Database _db;

  NotificationInbox(this._db);

  /// All notifications for [recipient], newest first. Pass `null` to retrieve
  /// the global feed (entries with no recipient set).
  Future<List<NotificationInboxItem>> entries({
    String? recipient,
    bool unreadOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final where = StringBuffer(
        recipient != null ? 'recipient = ?' : 'recipient IS NULL');
    final args = <Object?>[];
    if (recipient != null) args.add(recipient);
    if (unreadOnly) where.write(' AND read_at IS NULL');

    final rows = await _db.query(
      'notification_log',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'emitted_at DESC, id DESC',
      limit: limit,
      offset: offset < 0 ? 0 : offset,
    );
    return rows.map(_itemFromRow).toList();
  }

  /// Count of unread notifications for [recipient] (or the global feed).
  Future<int> unreadCount({String? recipient}) async {
    final where = recipient != null
        ? 'read_at IS NULL AND recipient = ?'
        : 'read_at IS NULL AND recipient IS NULL';
    final args = recipient != null ? <Object?>[recipient] : const <Object?>[];
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM notification_log WHERE $where',
      args,
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Mark a single entry read. A no-op if it is already read or missing.
  Future<void> markRead(String id, {DateTime? at}) async {
    await _db.update(
      'notification_log',
      {'read_at': (at ?? DateTime.now()).millisecondsSinceEpoch},
      where: 'id = ? AND read_at IS NULL',
      whereArgs: [id],
    );
  }

  /// Mark every unread entry for [recipient] (or the global feed) read.
  Future<void> markAllRead({String? recipient, DateTime? at}) async {
    final ts = (at ?? DateTime.now()).millisecondsSinceEpoch;
    if (recipient != null) {
      await _db.update(
        'notification_log',
        {'read_at': ts},
        where: 'recipient = ? AND read_at IS NULL',
        whereArgs: [recipient],
      );
    } else {
      await _db.update(
        'notification_log',
        {'read_at': ts},
        where: 'recipient IS NULL AND read_at IS NULL',
      );
    }
  }

  /// Hard-delete an inbox item (e.g. "swipe to delete"). The audit log remains
  /// the canonical record of what was sent.
  Future<void> delete(String id) async {
    await _db.delete('notification_log', where: 'id = ?', whereArgs: [id]);
  }

  NotificationInboxItem _itemFromRow(Map<String, Object?> row) {
    final readAt = row['read_at'] as int?;
    return NotificationInboxItem(
      id: row['id'] as String,
      appId: row['app_id'] as String,
      docType: row['doc_type'] as String,
      documentId: row['document_id'] as String,
      channel: row['channel'] as String,
      recipient: row['recipient'] as String?,
      subject: (row['subject'] as String?) ?? '',
      body: (row['body'] as String?) ?? '',
      emittedAt: DateTime.fromMillisecondsSinceEpoch(row['emitted_at'] as int),
      readAt:
          readAt == null ? null : DateTime.fromMillisecondsSinceEpoch(readAt),
    );
  }
}
