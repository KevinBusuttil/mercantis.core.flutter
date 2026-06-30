import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../metadata/metadata_display.dart';
import '../panes/document_list_pane.dart';
import '../panes/responsive_split.dart';
import '../providers/core_providers.dart';
import '../shell/breakpoints.dart';
import '../widgets/empty_state.dart';
import '../widgets/import_export_menu.dart';
import 'generic_form_view.dart';

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
/// - Tablet / desktop: list-detail split. Row tap selects in-place.
class MetadataListView extends ConsumerStatefulWidget {
  const MetadataListView({
    super.key,
    required this.docTypeName,
    this.title,
    this.subtitle,
    this.filter,
  });

  final String docTypeName;
  final String? title;
  final String? subtitle;
  final Map<String, dynamic>? filter;

  @override
  ConsumerState<MetadataListView> createState() => _MetadataListViewState();
}

class _MetadataListViewState extends ConsumerState<MetadataListView> {
  String _query = '';
  String _statusFilter = 'all';
  String? _selectedId;

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
    final list = _buildList(type, filtered);
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
      selectedId: _selectedId,
      onRowTap: (r) {
        if (Breakpoint.of(context).isPhone) {
          context.go('/form/${type.id}/${r.id}');
        } else {
          setState(() => _selectedId = r.id);
        }
      },
      onNew: () => context.go('/form/${type.id}/new'),
      newLabel: 'New ${type.name}',
      trailingActions: [
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
    if (_selectedId != null) {
      for (final d in docs) {
        if (d.id == _selectedId) return d;
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
