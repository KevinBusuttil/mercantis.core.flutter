import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../workspace/workspace_registry.dart';
import '../workspace/workspace_descriptor.dart';
import '../views/generic_form_view.dart';
import '../views/metadata_list_view.dart';
import 'adaptive_shell.dart';
import 'list_location.dart';
import '../workspace/workspace_view.dart';

/// Builds a [GoRouter] from registered workspaces. Routes:
///   /                       → first workspace (Home)
///   /w/:workspaceId         → workspace dashboard / sections
///   /w/:workspaceId/:route  → custom route registered by Hub
///   /list/:docType          → document list (full screen / list pane);
///                             `?title=` relabels it and `?f.<field>=<value>`
///                             pre-filters it (see [listLocation])
///   /form/:docType/new      → new document
///   /form/:docType/:name    → existing document
class AppNavigationRegistry {
  AppNavigationRegistry(this._registry, {WorkspaceRouteGate? gate})
      : _gate = gate;

  final WorkspaceRegistry _registry;
  final WorkspaceRouteGate? _gate;

  Widget _gated(BuildContext context, String workspaceId, String? routeName,
      WidgetBuilder child) {
    final gate = _gate;
    if (gate == null) return child(context);
    return gate(context,
        workspaceId: workspaceId, routeName: routeName, child: child);
  }

  GoRouter buildRouter({
    String? initialLocation,
    String brandLabel = 'Mercantis',
    String brandMark = 'M',
    String? notificationsLocation,
  }) {
    final initial = initialLocation ?? _initialLocation();
    return GoRouter(
      initialLocation: initial,
      routes: [
        ShellRoute(
          builder: (context, state, child) => AdaptiveShell(
            location: state.matchedLocation,
            brandLabel: brandLabel,
            brandMark: brandMark,
            notificationsLocation: notificationsLocation,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/',
              redirect: (_, __) => _initialLocation(),
            ),
            GoRoute(
              path: '/w/:workspaceId',
              builder: (context, state) {
                final id = state.pathParameters['workspaceId']!;
                return _gated(context, id, null, (context) {
                  final w = _registry.byId(id);
                  if (w == null) {
                    return _NotFound(message: 'Workspace "$id" not found');
                  }
                  return WorkspaceView(descriptor: w);
                });
              },
              routes: [
                GoRoute(
                  path: ':routeName',
                  builder: (context, state) {
                    final id = state.pathParameters['workspaceId']!;
                    final name = state.pathParameters['routeName']!;
                    return _gated(context, id, name, (context) {
                      final builder = _registry.routeFor(name);
                      if (builder == null) {
                        return _NotFound(
                            message: 'Route "$name" not registered');
                      }
                      return builder(context, state);
                    });
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/list/:docType',
              builder: (context, state) {
                final q = state.uri.queryParameters;
                final filter = {
                  for (final e in q.entries)
                    if (e.key.startsWith('f.'))
                      e.key.substring(2): listFilterValue(e.value),
                };
                return MetadataListView(
                  docTypeName: state.pathParameters['docType']!,
                  selectedId: q['selected'],
                  title: q['title'],
                  filter: filter.isEmpty ? null : filter,
                );
              },
            ),
            GoRoute(
              path: '/form/:docType/new',
              builder: (context, state) => GenericFormView(
                docTypeName: state.pathParameters['docType']!,
                documentName: null,
              ),
            ),
            GoRoute(
              path: '/form/:docType/:name',
              builder: (context, state) => GenericFormView(
                docTypeName: state.pathParameters['docType']!,
                documentName: state.pathParameters['name'],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _initialLocation() {
    final all = _registry.all;
    if (all.isEmpty) return '/';
    return '/w/${all.first.id}';
  }
}

final appNavigationRegistryProvider = Provider<AppNavigationRegistry>(
  (ref) => AppNavigationRegistry(
    ref.watch(workspaceRegistryProvider),
    gate: ref.watch(workspaceRouteGateProvider),
  ),
);

class _NotFound extends StatelessWidget {
  const _NotFound({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(message));
}

extension WorkspacePath on WorkspaceDescriptor {
  String pathFor(String routeName) => '/w/$id/$routeName';
}
