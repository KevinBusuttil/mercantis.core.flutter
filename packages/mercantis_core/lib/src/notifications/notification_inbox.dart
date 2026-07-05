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

  // ── Audience queries ──────────────────────────────────────────────────────
  // An operator's inbox is the global feed (no recipient) PLUS anything
  // addressed to any of their recipient keys — their user id, email, or roles.
  // The single-recipient methods above do an exact match; these union the
  // global feed with an `IN (…)` over the audience so a logged-in operator sees
  // both broadcasts and messages addressed to them, in one pass.

  /// Notifications visible to an operator whose recipient keys are [recipients]
  /// (id / email / roles): the global feed plus anything addressed to any key,
  /// newest first. An empty [recipients] degrades to the global feed.
  ///
  /// Pass [viewerId] (the operator's stable user id) to resolve a broadcast's
  /// read state from that operator's receipt rather than the shared `read_at`,
  /// so one operator reading a broadcast doesn't mark it read for everyone.
  /// Addressed rows always use their own `read_at`. Without a [viewerId],
  /// broadcasts fall back to the shared `read_at`.
  Future<List<NotificationInboxItem>> entriesForAudience({
    required List<String> recipients,
    String? viewerId,
    bool unreadOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final (clause, args) = _audienceClause(recipients);
    // Effective (per-viewer) read state: a broadcast reads from this viewer's
    // receipt; everything else from its own read_at.
    final read = viewerId == null
        ? 'n.read_at'
        : 'CASE WHEN n.recipient IS NULL THEN r.read_at ELSE n.read_at END';
    final join = viewerId == null
        ? ''
        : 'LEFT JOIN notification_broadcast_receipt r '
            'ON r.notification_id = n.id AND r.viewer_id = ? ';
    final where = unreadOnly ? '($clause) AND $read IS NULL' : '($clause)';
    final rows = await _db.rawQuery(
      'SELECT n.id, n.app_id, n.doc_type, n.document_id, n.channel, '
      'n.recipient, n.subject, n.body, n.emitted_at, $read AS read_at '
      'FROM notification_log n $join'
      'WHERE $where '
      'ORDER BY n.emitted_at DESC, n.id DESC '
      'LIMIT ? OFFSET ?',
      [
        if (viewerId != null) viewerId,
        ...args,
        limit,
        offset < 0 ? 0 : offset,
      ],
    );
    return rows.map(_itemFromRow).toList();
  }

  /// Unread count across an operator's audience. By default this is the union
  /// of the global feed and anything addressed to the audience.
  ///
  /// Pass [viewerId] so a broadcast counts as unread only until *this* operator
  /// receipts it (via [markBroadcastRead] / [markAllReadForAudience]); the
  /// badge then always reaches zero after "mark all read" without leaking a
  /// broadcast's read state across operators. Pass [includeGlobal] `false` to
  /// count only messages **addressed to** the audience, ignoring broadcasts
  /// entirely.
  Future<int> unreadCountForAudience({
    required List<String> recipients,
    String? viewerId,
    bool includeGlobal = true,
  }) async {
    if (!includeGlobal) {
      final keys = _addressedKeys(recipients);
      if (keys.isEmpty) return 0;
      final placeholders = List.filled(keys.length, '?').join(', ');
      final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM notification_log '
        'WHERE recipient IN ($placeholders) AND read_at IS NULL',
        keys,
      );
      return (rows.first['c'] as int?) ?? 0;
    }
    final (clause, args) = _audienceClause(recipients);
    if (viewerId == null) {
      final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM notification_log '
        'WHERE ($clause) AND read_at IS NULL',
        args,
      );
      return (rows.first['c'] as int?) ?? 0;
    }
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM notification_log n '
      'LEFT JOIN notification_broadcast_receipt r '
      'ON r.notification_id = n.id AND r.viewer_id = ? '
      'WHERE ($clause) AND '
      '(CASE WHEN n.recipient IS NULL THEN r.read_at ELSE n.read_at END) IS NULL',
      [viewerId, ...args],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Mark this audience's inbox read for one operator ([viewerId]): addressed
  /// rows have their `read_at` set, and every broadcast the operator hasn't
  /// receipted yet gets a receipt. The shared broadcast `read_at` is never
  /// touched, so this clears the operator's own badge without marking any
  /// broadcast read for other operators. Without a [viewerId] only addressed
  /// rows are cleared (broadcasts are left alone, as their read state would be
  /// shared).
  Future<void> markAllReadForAudience({
    required List<String> recipients,
    String? viewerId,
    DateTime? at,
  }) async {
    final ts = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final keys = _addressedKeys(recipients);
    if (keys.isNotEmpty) {
      final placeholders = List.filled(keys.length, '?').join(', ');
      await _db.update(
        'notification_log',
        {'read_at': ts},
        where: 'recipient IN ($placeholders) AND read_at IS NULL',
        whereArgs: keys,
      );
    }
    if (viewerId != null) {
      // INSERT OR IGNORE keeps any existing receipt's original timestamp.
      await _db.rawInsert(
        'INSERT OR IGNORE INTO notification_broadcast_receipt '
        '(notification_id, viewer_id, read_at) '
        'SELECT id, ?, ? FROM notification_log WHERE recipient IS NULL',
        [viewerId, ts],
      );
    }
  }

  /// Mark a single broadcast (global) entry read for one operator via a receipt,
  /// so it clears for [viewerId] only — not everyone. Idempotent: the first
  /// read's timestamp is kept. Use [markRead] for addressed entries.
  Future<void> markBroadcastRead(
    String notificationId, {
    required String viewerId,
    DateTime? at,
  }) async {
    await _db.rawInsert(
      'INSERT OR IGNORE INTO notification_broadcast_receipt '
      '(notification_id, viewer_id, read_at) VALUES (?, ?, ?)',
      [notificationId, viewerId, (at ?? DateTime.now()).millisecondsSinceEpoch],
    );
  }

  /// The audience's recipient keys with blanks and duplicates dropped.
  List<String> _addressedKeys(List<String> recipients) => {
        for (final r in recipients)
          if (r.trim().isNotEmpty) r,
      }.toList();

  /// Builds the `recipient IS NULL OR recipient IN (?, …)` predicate (and its
  /// args) for an audience. Blank/duplicate keys are dropped; an empty audience
  /// yields just the global `recipient IS NULL`.
  (String, List<Object?>) _audienceClause(List<String> recipients) {
    final keys = _addressedKeys(recipients);
    if (keys.isEmpty) return ('recipient IS NULL', const <Object?>[]);
    final placeholders = List.filled(keys.length, '?').join(', ');
    return ('recipient IS NULL OR recipient IN ($placeholders)', keys);
  }

  /// Hard-delete an inbox item (e.g. "swipe to delete"). The audit log remains
  /// the canonical record of what was sent.
  Future<void> delete(String id) async {
    await _db.delete('notification_log', where: 'id = ?', whereArgs: [id]);
    // Drop any per-viewer broadcast receipts so they can't outlive the entry.
    await _db.delete('notification_broadcast_receipt',
        where: 'notification_id = ?', whereArgs: [id]);
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
