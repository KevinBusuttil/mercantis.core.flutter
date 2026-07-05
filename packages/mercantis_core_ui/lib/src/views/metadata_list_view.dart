import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../metadata/metadata_display.dart';
import '../panes/document_list_pane.dart';
import '../panes/responsive_split.dart';
import '../providers/core_providers.dart';
import '../shell/breakpoints.dart';
import '../widgets/empty_state.dart';
import '../widgets/import_export_menu.dart';
import '../widgets/search/global_search.dart';
import 'generic_form_view.dart';
import 'record_tree_view.dart';
import 'record_view_mode.dart';
import 'record_view_mode_toggle.dart';

final _docsProvider =
    FutureProvider.family<List<Document>, _ListArgs>((ref, args) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return engine.list(
    args.docType,
    filters: args.filter,
    limit: 200,
  );
});

final _docTypeProvider =
    FutureProvider.family<DocType?, String>((ref, docTypeName) async {
  final registry = await ref.watch(metadataRegistryProvider.future);
  try {
    return await registry.get(docTypeName);
  } catch (_) {
    return null;
  }
});

class _ListArgs {
  const _ListArgs(this.docType, this.filter);
  final String docType;
  final Map<String, dynamic>? filter;

  @override
  bool operator ==(Object other) =>
      other is _ListArgs &&
      other.docType == docType &&
      _mapEq(other.filter, filter);

  @override
  int get hashCode => Object.hash(docType, filter?.length);

  static bool _mapEq(Map? a, Map? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}

/// Metadata-driven document list with the new design language.
///
/// - Phone: single column list. Row tap pushes the form route.
/// - Tablet / desktop: list-detail split. Row tap selects in-place, syncing the
///   selection into the route as `?selected=:id` so it survives refresh and is
///   deep-linkable.
class MetadataListView extends ConsumerStatefulWidget {
  const MetadataListView({
    super.key,
    required this.docTypeName,
    this.title,
    this.subtitle,
    this.filter,
    this.selectedId,
  });

  final String docTypeName;
  final String? title;
  final String? subtitle;
  final Map<String, dynamic>? filter;

  /// The selected record id, sourced from the route's `?selected=` query
  /// parameter (tablet/desktop split only). Null selects the first record for
  /// the detail pane without pinning a selection in the URL.
  final String? selectedId;

  @override
  ConsumerState<MetadataListView> createState() => _MetadataListViewState();
}

class _MetadataListViewState extends ConsumerState<MetadataListView> {
  String _query = '';
  String _statusFilter = 'all';

  /// List ↔ Tree choice for hierarchical DocTypes. Persisted per-DocType under
  /// the same key the studio [GenericListView] uses, so the choice is shared and
  /// sticks across launches. Ignored (always list) for non-tree DocTypes.
  RecordViewMode _viewMode = RecordViewMode.list;
  String get _viewModeKey => 'core.record_view_mode.${widget.docTypeName}';

  @override
  void initState() {
    super.initState();
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = RecordViewMode.fromName(prefs.getString(_viewModeKey));
      if (!mounted || saved == null) return;
      setState(() => _viewMode = saved);
    } catch (_) {
      // Prefs unavailable (e.g. a widget test without a mock) — keep the default.
    }
  }

  Future<void> _setViewMode(RecordViewMode mode) async {
    setState(() => _viewMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewModeKey, mode.name);
    } catch (_) {
      // Best-effort persistence; the in-session choice still applies.
    }
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(_docsProvider(
      _ListArgs(widget.docTypeName, widget.filter),
    ));
    final docTypeAsync = ref.watch(_docTypeProvider(widget.docTypeName));
    final bp = Breakpoint.of(context);

    return docTypeAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Metadata error: $e')),
      ),
      data: (type) {
        if (type == null) {
          return Scaffold(
            body: EmptyState(
              title: 'Unknown DocType',
              message: '"${widget.docTypeName}" is not registered.',
              icon: Icons.help_outline,
            ),
          );
        }
        return docsAsync.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
          data: (docs) => _build(context, type, docs, bp),
        );
      },
    );
  }

  Widget _build(
    BuildContext context, DocType type, List<Document> docs, Breakpoint bp,
  ) {
    final filtered = _applyFilters(docs);
    final list = _buildCollection(type, filtered);
    if (bp.isPhone) return Scaffold(body: list);

    final selected = _pickSelected(filtered);
    final detail = selected == null
        ? _emptyDetail()
        : GenericFormView(
            key: ValueKey(selected.id),
            docTypeName: type.id,
            documentName: selected.id,
          );

    return Scaffold(
      body: ResponsiveSplit(list: list, detail: detail),
    );
  }

  /// The collection region: the [DocumentListPane] for flat DocTypes, or — for
  /// hierarchical (`isTree`) DocTypes — a List/Tree toggle above either the pane
  /// or a [RecordTreeView]. Used identically on phone and in the desktop split.
  Widget _buildCollection(DocType type, List<Document> docs) {
    if (!type.isTree) return _buildList(type, docs);
    return Column(
      children: [
        RecordViewModeToggle(mode: _viewMode, onChanged: _setViewMode),
        Expanded(
          child: _viewMode == RecordViewMode.tree
              ? RecordTreeView(
                  docType: type,
                  documents: docs,
                  selectedDocumentId: widget.selectedId,
                  onSelect: (d) => _openRecord(type, d.id),
                )
              : _buildList(type, docs),
        ),
      ],
    );
  }

  /// Open a record — push the form on phone, or sync the selection into the
  /// route (`?selected=`) so the detail pane updates in the desktop split.
  void _openRecord(DocType type, String id) {
    if (Breakpoint.of(context).isPhone) {
      context.go('/form/${type.id}/$id');
    } else {
      context.go('/list/${type.id}?selected=${Uri.encodeQueryComponent(id)}');
    }
  }

  Widget _buildList(DocType type, List<Document> docs) {
    final rows = [
      for (final d in docs)
        DocumentListPaneRow(
          id: d.id,
          title: MetadataDisplay.titleFor(type, d),
          subtitle: MetadataDisplay.subtitleFor(type, d) ?? d.id,
          amount: MetadataDisplay.amountFor(type, d),
          statusLabel: type.isSubmittable
              ? MetadataDisplay.docStatusLabel(d.docStatus)
              : null,
          statusTone: type.isSubmittable
              ? MetadataDisplay.docStatusTone(d.docStatus)
              : null,
          timestamp: MetadataDisplay.timestampFor(type, d),
        ),
    ];

    return DocumentListPane(
      title: widget.title ?? type.name,
      subtitle: widget.subtitle ??
          '${docs.length} ${docs.length == 1 ? 'record' : 'records'}',
      searchHint: 'Search ${type.name.toLowerCase()}',
      onSearchChanged: (v) => setState(() => _query = v),
      filterChips: type.isSubmittable
          ? [
              for (final entry in const {
                'all': 'All',
                'draft': 'Draft',
                'submitted': 'Submitted',
                'cancelled': 'Cancelled',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(entry.value),
                    selected: _statusFilter == entry.key,
                    onSelected: (_) =>
                        setState(() => _statusFilter = entry.key),
                  ),
                ),
            ]
          : const [],
      rows: rows,
      selectedId: widget.selectedId,
      // Sync the selection into the route so it survives refresh and is
      // deep-linkable; the query change rebuilds this view with the new
      // selectedId (local filter state persists — same route page key).
      onRowTap: (r) => _openRecord(type, r.id),
      onNew: () => context.go('/form/${type.id}/new'),
      newLabel: 'New ${type.name}',
      trailingActions: [
        // Phones have no navigation-rail search button, and this pane's own
        // field only filters the current list — so surface global search here
        // too. `manage_search` disambiguates it from the list filter field.
        if (Breakpoint.of(context).isPhone)
          IconButton(
            icon: const Icon(Icons.manage_search),
            tooltip: 'Search everything',
            onPressed: () => showGlobalSearch(context),
          ),
        ImportExportMenu(
          docType: type.id,
          onChanged: () => ref.invalidate(
            _docsProvider(_ListArgs(widget.docTypeName, widget.filter)),
          ),
        ),
      ],
    );
  }

  Widget _emptyDetail() => const EmptyState(
        title: 'Nothing selected',
        message: 'Pick a record on the left to see details.',
        icon: Icons.touch_app_outlined,
      );

  Document? _pickSelected(List<Document> docs) {
    if (docs.isEmpty) return null;
    final selected = widget.selectedId;
    if (selected != null) {
      for (final d in docs) {
        if (d.id == selected) return d;
      }
    }
    return docs.first;
  }

  List<Document> _applyFilters(List<Document> docs) {
    final q = _query.trim().toLowerCase();
    return docs.where((d) {
      if (_statusFilter == 'draft' && d.docStatus != 0) return false;
      if (_statusFilter == 'submitted' && d.docStatus != 1) return false;
      if (_statusFilter == 'cancelled' && d.docStatus != 2) return false;
      if (q.isEmpty) return true;
      if (d.id.toLowerCase().contains(q)) return true;
      for (final v in d.payload.values) {
        if (v is String && v.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }
}
