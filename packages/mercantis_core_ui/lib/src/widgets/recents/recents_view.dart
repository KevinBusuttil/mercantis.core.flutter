import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/recents_providers.dart';
import '../empty_state.dart';

/// Lists the records the user recently opened, newest first, and routes back
/// to them on tap. Backed by [recentsProvider]; records are captured when a
/// record form loads (see `GenericFormView`).
class RecentsView extends ConsumerWidget {
  const RecentsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentsAsync = ref.watch(recentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recents'),
        actions: [
          if ((recentsAsync.valueOrNull ?? const []).isNotEmpty)
            IconButton(
              tooltip: 'Clear recents',
              icon: const Icon(Icons.clear_all),
              onPressed: () => ref.read(recentsProvider.notifier).clear(),
            ),
        ],
      ),
      body: recentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyState(
              title: 'No recents yet',
              message: 'Records you open will show up here for quick access.',
              icon: Icons.history,
            );
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = entries[i];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [e.docType, if (e.subtitle != null) e.subtitle!]
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  _relativeTime(e.openedAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                onTap: () => context.go('/form/${e.docType}/${e.docId}'),
              );
            },
          );
        },
      ),
    );
  }
}

/// Compact "time ago" label — no intl dependency on locale data.
String _relativeTime(DateTime then) {
  final d = DateTime.now().difference(then);
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${(d.inDays / 7).floor()}w';
}
