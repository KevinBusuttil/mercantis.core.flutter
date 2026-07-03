import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/core_providers.dart';
import '../theme/atlas/atlas.dart';
import 'record_tree_view.dart';
import 'record_view_mode.dart';

final _listProvider =
    FutureProvider.family<List<Document>, String>((ref, docTypeName) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return engine.list(docTypeName);
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

class GenericListView extends ConsumerStatefulWidget {
  const GenericListView({super.key, required this.docTypeName});
  final String docTypeName;

  @override
  ConsumerState<GenericListView> createState() => _GenericListViewState();
}

class _GenericListViewState extends ConsumerState<GenericListView> {
  /// Persisted per-DocType so a user's Tree/List choice sticks across launches —
  /// mirrors Swift `RecordCollectionHostView`'s UserDefaults-backed view mode.
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
    final async = ref.watch(_listProvider(widget.docTypeName));
    final docType = ref.watch(_docTypeProvider(widget.docTypeName)).asData?.value;
    // Tree is offered only for hierarchical (isTree) DocTypes — e.g. the chart
    // of accounts — matching Swift's `effectiveViewModes` gate.
    final supportsTree = docType?.isTree ?? false;
    final mode = supportsTree ? _viewMode : RecordViewMode.list;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.docTypeName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_listProvider(widget.docTypeName)),
          ),
        ],
      ),
      floatingActionButton: AtlasFloatingActionButton(
        onPressed: () =>
            GoRouter.of(context).go('/form/${widget.docTypeName}/new'),
        icon: Icons.add,
        tooltip: 'New',
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (docs) => Column(
          children: [
            if (supportsTree)
              _ViewModeToggle(mode: mode, onChanged: _setViewMode),
            Expanded(
              child: mode == RecordViewMode.tree && docType != null
                  ? RecordTreeView(
                      docType: docType,
                      documents: docs,
                      selectedDocumentId: null,
                      onSelect: (d) => GoRouter.of(context)
                          .go('/form/${widget.docTypeName}/${d.id}'),
                    )
                  : _buildList(context, docs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Document> docs) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No ${widget.docTypeName} records',
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final doc = docs[i];
        final name = doc.id.isEmpty ? '—' : doc.id;
        final status = doc['status'] as String?;
        return Card(
          child: ListTile(
            title: Text(name),
            subtitle: status != null ? Text(status) : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                GoRouter.of(context).go('/form/${widget.docTypeName}/$name'),
          ),
        );
      },
    );
  }
}

/// List ↔ Tree switcher shown only for hierarchical DocTypes.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode, required this.onChanged});

  final RecordViewMode mode;
  final ValueChanged<RecordViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
          selected: {
            mode == RecordViewMode.tree
                ? RecordViewMode.tree
                : RecordViewMode.list
          },
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    );
  }
}
