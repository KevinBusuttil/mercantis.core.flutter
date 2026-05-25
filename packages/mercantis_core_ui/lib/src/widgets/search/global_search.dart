import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/tokens/radius.dart';
import '../../theme/tokens/spacing.dart';
import 'global_search_service.dart';

/// Opens a Cmd-K style search palette. Wire up via shortcut elsewhere.
Future<void> showGlobalSearch(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => const _GlobalSearchDialog(),
  );
}

class _GlobalSearchDialog extends ConsumerStatefulWidget {
  const _GlobalSearchDialog();

  @override
  ConsumerState<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<_GlobalSearchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = ref.read(globalSearchServiceProvider);
    final results = svc.search(_query);

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rLg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(MercantisSpacing.md),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search documents, workspaces, actions…',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (_) {
                  if (results.isNotEmpty) {
                    _open(context, results.first);
                  }
                },
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(MercantisSpacing.xl),
                      child: Text(
                        _query.isEmpty
                            ? 'Start typing to search'
                            : 'No results for "$_query"',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final r = results[i];
                        return ListTile(
                          leading: Icon(r.icon),
                          title: Text(r.title),
                          subtitle: r.subtitle != null ? Text(r.subtitle!) : null,
                          trailing: Text(
                            r.kindLabel,
                            style: theme.textTheme.labelSmall,
                          ),
                          onTap: () => _open(context, r),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, GlobalSearchResult r) {
    Navigator.of(context).pop();
    if (r.route != null) context.go(r.route!);
  }
}
