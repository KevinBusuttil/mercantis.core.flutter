import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import 'core_providers.dart';

/// The in-app [NotificationInbox] over the shared database.
final notificationInboxProvider = FutureProvider<NotificationInbox>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return NotificationInbox(db.db);
});

/// A recipient's notifications, newest first. Pass `null` for the global feed.
final notificationInboxItemsProvider =
    FutureProvider.family<List<NotificationInboxItem>, String?>((ref, recipient) async {
  final inbox = await ref.watch(notificationInboxProvider.future);
  return inbox.entries(recipient: recipient);
});

/// Unread count for a recipient (or the global feed) — drives the bell badge.
final notificationUnreadCountProvider =
    FutureProvider.family<int, String?>((ref, recipient) async {
  final inbox = await ref.watch(notificationInboxProvider.future);
  return inbox.unreadCount(recipient: recipient);
});
