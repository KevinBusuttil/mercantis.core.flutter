import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../../metadata/metadata_display.dart';
import '../../providers/core_providers.dart';
import '../../workspace/workspace_descriptor.dart';
import '../../workspace/workspace_registry.dart';
import 'global_search_service.dart';

/// Document-backed source for GlobalSearch. Queries DocTypes referenced by
/// the user's visible workspaces and matches against the title field.
///
/// Naive implementation — appropriate for prototype-scale datasets.
class MetadataSearchSource {
  MetadataSearchSource(this._ref, {this.perTypeLimit = 25});
  final Ref _ref;
  final int perTypeLimit;

  Future<List<GlobalSearchResult>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final registry = await _ref.read(metadataRegistryProvider.future);
    final engine = await _ref.read(documentEngineProvider.future);
    final visible = _ref.read(visibleWorkspacesProvider);

    final referencedTypes = <String>{};
    for (final w in visible) {
      for (final item in w.docTypeItems) {
        referencedTypes.add(item.docType);
      }
    }

    final results = <GlobalSearchResult>[];
    for (final id in referencedTypes) {
      final type = await registry.get(id);
      if (type == null) continue;
      final docs = await engine.list(id, limit: perTypeLimit);
      for (final d in docs) {
        final title = MetadataDisplay.titleFor(type, d);
        final hit = title.toLowerCase().contains(q) ||
            d.id.toLowerCase().contains(q);
        if (!hit) continue;
        results.add(GlobalSearchResult(
          id: '${type.id}:${d.id}',
          title: title,
          kindLabel: type.name,
          icon: Icons.description_outlined,
          subtitle: MetadataDisplay.subtitleFor(type, d) ?? d.id,
          route: '/form/${type.id}/${d.id}',
        ));
        if (results.length >= 30) return results;
      }
    }
    return results;
  }
}

final metadataSearchSourceProvider = Provider<MetadataSearchSource>(
  (ref) => MetadataSearchSource(ref),
);
