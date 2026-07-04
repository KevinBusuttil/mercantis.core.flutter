import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../workspace/workspace_registry.dart';
import '../workspace/workspace_descriptor.dart';
import '../views/generic_form_view.dart';
import '../views/metadata_list_view.dart';
import 'adaptive_shell.dart';
import '../workspace/workspace_view.dart';

/// Builds a [GoRouter] from registered workspaces. Routes:
///   /                       → first workspace (Home)
///   /w/:workspaceId         → workspace dashboard / sections
///   /w/:workspaceId/:route  → custom route registered by Hub
///   /list/:docType          → document list (full screen / list pane)
///   /form/:docType/new      → new document
///   /form/:docType/:name    → existing document
class AppNavigationRegistry {
  AppNavigationRegistry(this._registry);

  final WorkspaceRegistry _registry;

  GoRouter buildRouter({
    String? initialLocation,
    String brandLabel = 'Mercantis',
    String brandMark = 'M',
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
                final w = _registry.byId(id);
                if (w == null) {
                  return _NotFound(message: 'Workspace "$id" not found');
                }
                return WorkspaceView(descriptor: w);
              },
              routes: [
                GoRoute(
                  path: ':routeName',
                  builder: (context, state) {
                    final name = state.pathParameters['routeName']!;
                    final builder = _registry.routeFor(name);
                    if (builder == null) {
                      return _NotFound(message: 'Route "$name" not registered');
                    }
                    return builder(context, state);
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/list/:docType',
              builder: (context, state) => MetadataListView(
                docTypeName: state.pathParameters['docType']!,
                selectedId: state.uri.queryParameters['selected'],
              ),
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
  (ref) => AppNavigationRegistry(ref.watch(workspaceRegistryProvider)),
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
