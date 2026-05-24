import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../providers/core_providers.dart';

final _listProvider =
    FutureProvider.family<List<Document>, String>((ref, docTypeName) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return engine.list(docTypeName);
});

class GenericListView extends ConsumerWidget {
  const GenericListView({super.key, required this.docTypeName});
  final String docTypeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_listProvider(docTypeName));
    return Scaffold(
      appBar: AppBar(
        title: Text(docTypeName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_listProvider(docTypeName)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => GoRouter.of(context).go('/form/$docTypeName/new'),
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (docs) => _buildList(context, docs),
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
            Text('No $docTypeName records',
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
        final name = doc['name'] as String? ?? '—';
        final status = doc['status'] as String?;
        return Card(
          child: ListTile(
            title: Text(name),
            subtitle: status != null ? Text(status) : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => GoRouter.of(context).go('/form/$docTypeName/$name'),
          ),
        );
      },
    );
  }
}
