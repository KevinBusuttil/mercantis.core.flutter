import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../providers/core_providers.dart';

final _allDocTypesProvider = FutureProvider<List<DocType>>((ref) async {
  final registry = await ref.watch(metadataRegistryProvider.future);
  return registry.all();
});

class DocTypeListView extends ConsumerWidget {
  const DocTypeListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_allDocTypesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_allDocTypesProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (types) => _build(context, types),
      ),
    );
  }

  Widget _build(BuildContext context, List<DocType> types) {
    final byModule = <String, List<DocType>>{};
    for (final dt in types) {
      (byModule[dt.module] ??= []).add(dt);
    }
    if (byModule.isEmpty) {
      return const Center(child: Text('No DocTypes registered'));
    }
    final modules = byModule.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final module in modules) ..._moduleSection(context, module, byModule[module]!),
      ],
    );
  }

  List<Widget> _moduleSection(
    BuildContext context,
    String module,
    List<DocType> types,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          module,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
      Card(
        child: Column(
          children: [
            for (int i = 0; i < types.length; i++) ...[  
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(types[i].name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => (context as Element)
                    .findAncestorWidgetOfExactType<Navigator>() != null
                    ? GoRouter.of(context).go('/list/${types[i].id}')
                    : null,
              ),
              if (i < types.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),
    ];
  }
}
