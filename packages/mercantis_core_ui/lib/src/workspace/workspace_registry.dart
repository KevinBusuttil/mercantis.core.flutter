import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'workspace_descriptor.dart';
import 'workspace_visibility.dart';

typedef WorkspaceRouteBuilder = Widget Function(BuildContext, GoRouterState);

class WorkspaceRegistry {
  WorkspaceRegistry();

  final List<WorkspaceDescriptor> _workspaces = [];
  final Map<String, WorkspaceRouteBuilder> _customRoutes = {};

  void register(WorkspaceDescriptor descriptor) => _workspaces.add(descriptor);
  void registerAll(Iterable<WorkspaceDescriptor> descriptors) =>
      _workspaces.addAll(descriptors);

  void registerRoute(String name, WorkspaceRouteBuilder builder) =>
      _customRoutes[name] = builder;

  List<WorkspaceDescriptor> get all => List.unmodifiable(_workspaces);

  WorkspaceDescriptor? byId(String id) {
    for (final w in _workspaces) {
      if (w.id == id) return w;
    }
    return null;
  }

  WorkspaceRouteBuilder? routeFor(String name) => _customRoutes[name];

  List<WorkspaceDescriptor> visibleFor(PermissionContext ctx) =>
      const WorkspaceVisibilityFilter().apply(_workspaces, ctx);
}

final workspaceRegistryProvider = Provider<WorkspaceRegistry>(
  (_) => WorkspaceRegistry(),
);

final permissionContextProvider = Provider<PermissionContext>(
  (_) => PermissionContext.open,
);

final visibleWorkspacesProvider = Provider<List<WorkspaceDescriptor>>((ref) {
  final reg = ref.watch(workspaceRegistryProvider);
  final ctx = ref.watch(permissionContextProvider);
  return reg.visibleFor(ctx);
});
