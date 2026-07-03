import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/core_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/link_picker_field.dart';
import 'record_tree_view.dart';
import 'record_view_mode.dart';

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

/// Builder for a custom detail editor — mirrors Swift PR #113's
/// `detailEditor: ((Binding<Document>) -> AnyView)?` slot. Replaces the
/// view's default routed form when supplied; the host suppresses the
/// per-row Save action because the editor is expected to own Save.
typedef RecordDetailEditorBuilder = Widget Function(
  BuildContext context,
  DocType docType,
  Document document,
);

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
    this.detailEditor,
    this.linkSearchProvider,
    this.childDocTypeProvider,
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

  /// Optional caller-owned editor used in place of the routed
  /// `GenericFormView` when the host renders a detail pane. When
  /// supplied, the per-row Save action is suppressed because the
  /// editor is expected to own Save (matching Swift PR #113's
  /// `detailEditor == nil ? builtInSave : nothing` guard). On phone /
  /// list-only layouts this view doesn't host a detail pane today, so
  /// the slot is also forwarded into [CreateRecordSheet] for embedders
  /// that want a bespoke create form.
  final RecordDetailEditorBuilder? detailEditor;

  /// Caller-supplied lookup for link-picker search results. Forwarded
  /// into embedded forms (and the create sheet) so external shells can
  /// inject a server-backed search without coupling Core to a
  /// particular transport.
  final LinkSearchProvider? linkSearchProvider;

  /// Caller-supplied resolver for a link / child-table target DocType.
  /// Lets the form prefer the registry's title field when rendering
  /// link picker rows, and lets embedders short-circuit the registry
  /// lookup (e.g. resolve a virtual DocType).
  final DocType? Function(String docTypeId)? childDocTypeProvider;

  @override
  ConsumerState<RecordCollectionView> createState() =>
      _RecordCollectionViewState();
}

class _RecordCollectionViewState extends ConsumerState<RecordCollectionView> {
  String _query = '';

  /// Persisted per-DocType so a user's choice of Tree vs List sticks across
  /// launches — mirrors Swift `RecordCollectionHostView`'s UserDefaults-backed
  /// `recordViewMode.<preferenceKey>`.
  RecordViewMode _viewMode = RecordViewMode.list;
  String get _viewModeKey => 'core.record_view_mode.${widget.docTypeName}';

  @override
  void initState() {
    super.initState();
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = RecordViewMode.fromName(prefs.getString(_viewModeKey));
    if (!mounted || saved == null) return;
    setState(() => _viewMode = saved);
  }

  Future<void> _setViewMode(RecordViewMode mode) async {
    setState(() => _viewMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewModeKey, mode.name);
  }

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
        data: (docs) => _buildBody(
            context, resolvedTitle, docs, docTypeAsync.asData?.value),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String resolvedTitle,
      List<Document> docs, DocType? docType) {
    // Tree is offered only for hierarchical (isTree) DocTypes — e.g. the chart
    // of accounts — matching Swift's `effectiveViewModes` gate.
    final supportsTree = docType?.isTree ?? false;
    final mode = supportsTree ? _viewMode : RecordViewMode.list;

    if (mode == RecordViewMode.tree && docType != null) {
      return Column(
        children: [
          _Header(
            title: resolvedTitle,
            subtitle: widget.subtitle,
            icon: widget.icon,
            recordCount: docs.length,
          ),
          _ViewModeToggle(mode: mode, onChanged: _setViewMode),
          Expanded(
            child: RecordTreeView(
              docType: docType,
              documents: docs,
              selectedDocumentId: null,
              onSelect: (d) => GoRouter.of(context)
                  .go('/form/${widget.docTypeName}/${d.id}'),
            ),
          ),
        ],
      );
    }

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
        if (supportsTree)
          SliverToBoxAdapter(
            child: _ViewModeToggle(mode: mode, onChanged: _setViewMode),
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
                // Suppress the per-row Save when the caller supplies a
                // custom detailEditor — that editor is expected to own
                // its own Save affordance (Swift PR #113 contract).
                onSave: (widget.onSaveDocument == null ||
                        widget.detailEditor != null)
                    ? null
                    : () => _performSave(filtered[i]),
                onDelete: widget.onDeleteDocument == null
                    ? null
                    : () => _confirmDelete(filtered[i]),
                detailEditor: widget.detailEditor,
                docTypeResolver: widget.childDocTypeProvider,
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

/// List ↔ Tree switcher shown only for hierarchical DocTypes.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode, required this.onChanged});

  final RecordViewMode mode;
  final ValueChanged<RecordViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<RecordViewMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: RecordViewMode.list,
              icon: Icon(Icons.view_list_outlined),
              label: Text('List'),
            ),
            ButtonSegment(
              value: RecordViewMode.tree,
              icon: Icon(Icons.account_tree_outlined),
              label: Text('Tree'),
            ),
          ],
          selected: {mode == RecordViewMode.tree ? RecordViewMode.tree : RecordViewMode.list},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }
}

class _RecordTile extends ConsumerWidget {
  const _RecordTile({
    required this.doc,
    required this.docTypeName,
    this.onSave,
    this.onDelete,
    this.detailEditor,
    this.docTypeResolver,
  });
  final Document doc;
  final String docTypeName;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;
  final RecordDetailEditorBuilder? detailEditor;
  final DocType? Function(String)? docTypeResolver;

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

  Future<void> _openRow(BuildContext context, WidgetRef ref) async {
    final builder = detailEditor;
    if (builder == null) {
      GoRouter.of(context).go('/form/$docTypeName/${doc.id}');
      return;
    }
    // Resolve the DocType so the custom editor receives the same shape
    // its Swift counterpart did (`(Binding<Document>) -> AnyView` plus
    // the surrounding `docType`). Prefer the injected resolver — it's
    // what callers reach for when they want to short-circuit the
    // registry (e.g. virtual DocTypes).
    DocType? type = docTypeResolver?.call(docTypeName);
    if (type == null) {
      final registry = await ref.read(metadataRegistryProvider.future);
      type = await registry.get(docTypeName);
    }
    if (!context.mounted || type == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => builder(ctx, type!, doc),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        onTap: () => _openRow(context, ref),
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
    // Route through the shared Atlas EmptyState so a record list's placeholder
    // matches every other empty list/table/search in the app.
    return EmptyState(
      icon: isFiltered ? Icons.search_off : Icons.inbox_outlined,
      title: isFiltered ? 'No matches' : 'No $title records yet',
      message: isFiltered
          ? 'Try a different search term.'
          : 'Use the New $title button to create the first record.',
      action: isFiltered
          ? null
          : FilledButton.icon(
              onPressed: () => GoRouter.of(context).go('/form/$docTypeName/new'),
              icon: const Icon(Icons.add),
              label: Text('New $title'),
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
