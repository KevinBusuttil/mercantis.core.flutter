import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../workspace/current_user.dart';
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

/// The current operator's recipient keys: their id, email (when set), and roles.
/// The global feed (no recipient) is always included by the audience queries, so
/// it isn't listed here.
List<String> currentUserRecipients(CurrentUser user) => [
      user.id,
      if ((user.email ?? '').trim().isNotEmpty) user.email!,
      ...user.roles,
    ];

/// The current operator's inbox: the global feed plus anything addressed to
/// their id / email / roles, newest first. Re-fetches when the user changes.
final notificationInboxForCurrentUserProvider =
    FutureProvider<List<NotificationInboxItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  final inbox = await ref.watch(notificationInboxProvider.future);
  return inbox.entriesForAudience(recipients: currentUserRecipients(user));
});

/// Unread count across the current operator's audience — drives the shell bell
/// badge.
final notificationUnreadForCurrentUserProvider = FutureProvider<int>((ref) async {
  final user = ref.watch(currentUserProvider);
  final inbox = await ref.watch(notificationInboxProvider.future);
  return inbox.unreadCountForAudience(recipients: currentUserRecipients(user));
});
