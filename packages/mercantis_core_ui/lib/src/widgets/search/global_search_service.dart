import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../workspace/workspace_registry.dart';

class GlobalSearchResult {
  const GlobalSearchResult({
    required this.id,
    required this.title,
    required this.icon,
    required this.kindLabel,
    this.subtitle,
    this.route,
  });

  final String id;
  final String title;
  final String kindLabel;
  final IconData icon;
  final String? subtitle;
  final String? route;
}

class GlobalSearchService {
  GlobalSearchService(this._ref);

  final Ref _ref;

  List<GlobalSearchResult> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _suggestions();

    final results = <GlobalSearchResult>[];
    final workspaces = _ref.read(visibleWorkspacesProvider);
    for (final w in workspaces) {
      if (w.label.toLowerCase().contains(q)) {
        results.add(GlobalSearchResult(
          id: 'w:${w.id}',
          title: w.label,
          kindLabel: 'Workspace',
          icon: w.icon,
          subtitle: w.subtitle,
          route: w.path,
        ));
      }
      for (final section in w.sections) {
        for (final item in section.items) {
          final label = item.resolvedLabel();
          if (label.toLowerCase().contains(q)) {
            results.add(GlobalSearchResult(
              id: 'i:${w.id}:$label',
              title: label,
              kindLabel: 'In ${w.label}',
              icon: item.icon ?? w.icon,
              subtitle: section.label,
              route: _routeForItem(w.id, item),
            ));
          }
        }
      }
      for (final qa in w.quickActions) {
        if (qa.label.toLowerCase().contains(q)) {
          results.add(GlobalSearchResult(
            id: 'qa:${w.id}:${qa.id}',
            title: qa.label,
            kindLabel: 'Action · ${w.label}',
            icon: qa.icon,
            route: qa.docType != null ? '/form/${qa.docType}/new' : qa.routeName,
          ));
        }
      }
    }
    return results;
  }

  String? _routeForItem(String workspaceId, item) {
    if (item is DocTypeWorkspaceItem) return '/list/${item.docType}';
    if (item is DashboardWorkspaceItem) return '/w/$workspaceId';
    if (item is CustomWorkspaceItem) return '/w/$workspaceId/${item.routeName}';
    return null;
  }

  List<GlobalSearchResult> _suggestions() {
    final results = <GlobalSearchResult>[];
    for (final w in _ref.read(visibleWorkspacesProvider).take(6)) {
      results.add(GlobalSearchResult(
        id: 'w:${w.id}',
        title: w.label,
        kindLabel: 'Workspace',
        icon: w.icon,
        subtitle: w.subtitle,
        route: w.path,
      ));
    }
    return results;
  }
}

final globalSearchServiceProvider = Provider<GlobalSearchService>(
  (ref) => GlobalSearchService(ref),
);
