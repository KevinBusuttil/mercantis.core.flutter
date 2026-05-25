import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../providers/core_providers.dart';

final _recordCollectionProvider =
    FutureProvider.family<List<Document>, String>((ref, docTypeName) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return engine.list(docTypeName);
});

final _resolvedDocTypeProvider =
    FutureProvider.family<DocType?, String>((ref, docTypeName) async {
  final registry = await ref.watch(metadataRegistryProvider.future);
  try {
    return await registry.get(docTypeName);
  } catch (_) {
    return null;
  }
});

/// A reusable record workspace surface for a DocType.
///
/// Provides:
///  - workspace header (icon, title, subtitle)
///  - record count
///  - primary action (`New <DocType>`) that routes to `/form/:docType/new`
///  - search filter
///  - list of records that route to `/form/:docType/:name` on tap
///  - empty/loading/error states
class RecordCollectionView extends ConsumerStatefulWidget {
  const RecordCollectionView({
    super.key,
    required this.docTypeName,
    this.title,
    this.subtitle,
    this.icon,
    this.newButtonLabel,
  });

  final String docTypeName;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final String? newButtonLabel;

  @override
  ConsumerState<RecordCollectionView> createState() =>
      _RecordCollectionViewState();
}

class _RecordCollectionViewState extends ConsumerState<RecordCollectionView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(_recordCollectionProvider(widget.docTypeName));
    final docTypeAsync =
        ref.watch(_resolvedDocTypeProvider(widget.docTypeName));

    final resolvedTitle = widget.title ??
        docTypeAsync.maybeWhen<String>(
          data: (dt) => dt?.name ?? widget.docTypeName,
          orElse: () => widget.docTypeName,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(resolvedTitle),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(_recordCollectionProvider(widget.docTypeName)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            GoRouter.of(context).go('/form/${widget.docTypeName}/new'),
        icon: const Icon(Icons.add),
        label: Text(widget.newButtonLabel ?? 'New $resolvedTitle'),
      ),
      body: docsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(message: e.toString()),
        data: (docs) => _buildBody(context, resolvedTitle, docs),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, String resolvedTitle, List<Document> docs) {
    final filtered = _query.isEmpty
        ? docs
        : docs.where((d) {
            final q = _query.toLowerCase();
            if (d.id.toLowerCase().contains(q)) return true;
            return d.payload.values.any(
              (v) => v != null && v.toString().toLowerCase().contains(q),
            );
          }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Header(
            title: resolvedTitle,
            subtitle: widget.subtitle,
            icon: widget.icon,
            recordCount: docs.length,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _SearchField(
              hint: 'Search $resolvedTitle',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              title: resolvedTitle,
              docTypeName: widget.docTypeName,
              isFiltered: _query.isNotEmpty,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _RecordTile(
                doc: filtered[i],
                docTypeName: widget.docTypeName,
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.recordCount,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _CountBadge(count: recordCount),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count ${count == 1 ? 'record' : 'records'}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.doc, required this.docTypeName});
  final Document doc;
  final String docTypeName;

  String _primaryLabel() {
    if (doc.id.isNotEmpty) return doc.id;
    return '—';
  }

  String? _secondaryLabel() {
    final status = doc['status'];
    if (status is String && status.isNotEmpty) return status;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.article_outlined),
        title: Text(_primaryLabel()),
        subtitle:
            _secondaryLabel() != null ? Text(_secondaryLabel()!) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            GoRouter.of(context).go('/form/$docTypeName/${doc.id}'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.docTypeName,
    required this.isFiltered,
  });
  final String title;
  final String docTypeName;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFiltered ? Icons.search_off : Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered ? 'No matches' : 'No $title records yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Try a different search term.'
                  : 'Use the New $title button to create the first record.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!isFiltered) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    GoRouter.of(context).go('/form/$docTypeName/new'),
                icon: const Icon(Icons.add),
                label: Text('New $title'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Failed to load records',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
