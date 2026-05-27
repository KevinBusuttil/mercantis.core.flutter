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

/// Signature for the optional save hook on [RecordCollectionView].
///
/// Mirrors Swift PR #116: must return the persisted copy of [document]
/// (typically a refetch) so the caller's local binding picks up the
/// refreshed `modifiedAt`. Returning the same `document` is fine when
/// the engine doesn't mutate timestamps, but it WILL trip
/// `concurrencyConflict` on the next save if the engine did stamp it.
typedef RecordSaveHandler = Future<Document> Function(Document document);

/// Signature for the optional delete hook on [RecordCollectionView].
/// Throws on failure; the host shows the message via
/// [DocumentEngineError.humanMessage] when available.
typedef RecordDeleteHandler = Future<void> Function(Document document);

/// A reusable record workspace surface for a DocType.
///
/// Provides:
///  - workspace header (icon, title, subtitle)
///  - record count
///  - primary action (`New <DocType>`) that routes to `/form/:docType/new`
///  - search filter
///  - list of records that route to `/form/:docType/:name` on tap
///  - empty/loading/error states
///
/// Callers may opt into in-place persistence by passing [onSaveDocument]
/// and/or [onDeleteDocument]; when [onDeleteDocument] is supplied the
/// row gains a destructive trailing action with an AlertDialog
/// confirmation. Submitted records (docStatus == 1) intentionally hide
/// the delete affordance — the engine rejects the operation anyway, but
/// hiding the button up front avoids the dead-end interaction.
class RecordCollectionView extends ConsumerStatefulWidget {
  const RecordCollectionView({
    super.key,
    required this.docTypeName,
    this.title,
    this.subtitle,
    this.icon,
    this.newButtonLabel,
    this.onSaveDocument,
    this.onDeleteDocument,
  });

  final String docTypeName;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final String? newButtonLabel;

  /// Persists `document` and returns the refreshed copy (caller is
  /// expected to refetch). Wiring this enables a `Save` row action.
  final RecordSaveHandler? onSaveDocument;

  /// Deletes `document` from the underlying store. Wiring this enables
  /// a destructive `Delete` row action with an `AlertDialog`
  /// confirmation; hidden when `docStatus == 1`.
  final RecordDeleteHandler? onDeleteDocument;

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
                onSave: widget.onSaveDocument == null
                    ? null
                    : () => _performSave(filtered[i]),
                onDelete: widget.onDeleteDocument == null
                    ? null
                    : () => _confirmDelete(filtered[i]),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _performSave(Document doc) async {
    final handler = widget.onSaveDocument;
    if (handler == null) return;
    try {
      final saved = await handler(doc);
      if (!mounted) return;
      ref.invalidate(_recordCollectionProvider(widget.docTypeName));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${saved.id}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_humanError(e))),
      );
    }
  }

  /// Two-step delete: AlertDialog confirms, then `onDeleteDocument`
  /// runs. The list provider is invalidated on success so the row
  /// disappears without a separate refresh tap.
  Future<void> _confirmDelete(Document doc) async {
    final handler = widget.onDeleteDocument;
    if (handler == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${doc.id.isEmpty ? "this draft" : doc.id}?'),
        content: const Text(
          'This will permanently remove the record. This action cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await handler(doc);
      if (!mounted) return;
      ref.invalidate(_recordCollectionProvider(widget.docTypeName));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${doc.id}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_humanError(e))),
      );
    }
  }

  String _humanError(Object e) =>
      e is DocumentEngineError ? e.humanMessage : e.toString();
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.doc,
    required this.docTypeName,
    this.onSave,
    this.onDelete,
  });
  final Document doc;
  final String docTypeName;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;

  String _primaryLabel() {
    if (doc.id.isNotEmpty) return doc.id;
    return '—';
  }

  String? _secondaryLabel() {
    final status = doc['status'];
    if (status is String && status.isNotEmpty) return status;
    return null;
  }

  /// Mirrors Swift PR #116's `canDeleteSelected` — hide delete on a
  /// Submitted (docStatus == 1) row so users don't see a button that
  /// always errors. The engine itself also blocks the operation.
  bool get _canDelete => onDelete != null && doc.docStatus != 1;

  @override
  Widget build(BuildContext context) {
    final hasActions = onSave != null || _canDelete;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.article_outlined),
        title: Text(_primaryLabel()),
        subtitle: _secondaryLabel() != null ? Text(_secondaryLabel()!) : null,
        trailing: hasActions
            ? _RowActions(
                onSave: onSave,
                onDelete: _canDelete ? onDelete : null,
              )
            : const Icon(Icons.chevron_right),
        onTap: () => GoRouter.of(context).go('/form/$docTypeName/${doc.id}'),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({this.onSave, this.onDelete});
  final VoidCallback? onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onSave != null)
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_outlined),
            onPressed: onSave,
          ),
        if (onDelete != null)
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, color: cs.error),
            onPressed: onDelete,
          ),
      ],
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
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Failed to load records', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
