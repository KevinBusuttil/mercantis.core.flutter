import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../theme/tokens/radius.dart';
import '../../theme/tokens/spacing.dart';
import 'global_search_service.dart';
import 'metadata_search_source.dart';

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
  List<GlobalSearchResult> _docHits = const [];
  bool _docsLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runDocSearch);
  }

  Future<void> _runDocSearch() async {
    final q = _query;
    if (q.trim().isEmpty) {
      if (mounted) setState(() => _docHits = const []);
      return;
    }
    setState(() => _docsLoading = true);
    try {
      final hits = await ref.read(metadataSearchSourceProvider).search(q);
      if (mounted && q == _query) {
        setState(() {
          _docHits = hits;
          _docsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _docsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = ref.read(globalSearchServiceProvider);
    final navResults = svc.search(_query);

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rLg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
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
                onChanged: _onChanged,
                onSubmitted: (_) {
                  if (navResults.isNotEmpty) {
                    _open(context, navResults.first);
                  } else if (_docHits.isNotEmpty) {
                    _open(context, _docHits.first);
                  }
                },
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                children: [
                  if (navResults.isEmpty &&
                      _docHits.isEmpty &&
                      !_docsLoading)
                    Padding(
                      padding: const EdgeInsets.all(MercantisSpacing.xl),
                      child: Text(
                        _query.isEmpty
                            ? 'Start typing to search'
                            : 'No results for "$_query"',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (navResults.isNotEmpty) ...[
                    _SectionHeader(label: 'Navigate'),
                    for (final r in navResults) _ResultTile(result: r, onTap: _open),
                  ],
                  if (_query.isNotEmpty)
                    _SectionHeader(
                      label: 'Documents',
                      trailing: _docsLoading
                          ? const SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : null,
                    ),
                  for (final r in _docHits) _ResultTile(result: r, onTap: _open),
                ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MercantisSpacing.lg, MercantisSpacing.md,
        MercantisSpacing.lg, MercantisSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: MercantisSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.onTap});
  final GlobalSearchResult result;
  final void Function(BuildContext, GlobalSearchResult) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(result.icon),
      title: Text(result.title),
      subtitle: result.subtitle != null ? Text(result.subtitle!) : null,
      trailing: Text(
        result.kindLabel,
        style: theme.textTheme.labelSmall,
      ),
      onTap: () => onTap(context, result),
    );
  }
}
