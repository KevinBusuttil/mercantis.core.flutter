import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../providers/notification_providers.dart';

/// Reader UI for the in-app notification inbox (ADR-048): lists a recipient's
/// notifications with unread styling, tap-to-mark-read, swipe-to-delete, and a
/// "Mark all read" action. Composable — drop into a screen or pane.
class NotificationInboxView extends ConsumerWidget {
  const NotificationInboxView({super.key, this.recipient});

  /// Whose feed to show. `null` = the global (unaddressed) feed.
  final String? recipient;

  void _refresh(WidgetRef ref) {
    ref.invalidate(notificationInboxItemsProvider(recipient));
    ref.invalidate(notificationUnreadCountProvider(recipient));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationInboxItemsProvider(recipient));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Mark all read'),
                onPressed: () async {
                  final inbox = await ref.read(notificationInboxProvider.future);
                  await inbox.markAllRead(recipient: recipient);
                  _refresh(ref);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load notifications: $e')),
            data: (items) {
              if (items.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none, size: 56, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No notifications', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _tile(context, ref, items[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, NotificationInboxItem item) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) async {
        final inbox = await ref.read(notificationInboxProvider.future);
        await inbox.delete(item.id);
        _refresh(ref);
      },
      child: ListTile(
        leading: item.isRead
            ? const Icon(Icons.notifications_none)
            : Icon(Icons.circle, size: 12, color: theme.colorScheme.primary),
        title: Text(
          item.subject.isEmpty ? '(no subject)' : item.subject,
          style: TextStyle(fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold),
        ),
        subtitle: Text(
          '${item.body}\n${_when(item.emittedAt)}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        onTap: item.isRead
            ? null
            : () async {
                final inbox = await ref.read(notificationInboxProvider.future);
                await inbox.markRead(item.id);
                _refresh(ref);
              },
      ),
    );
  }

  static String _when(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
