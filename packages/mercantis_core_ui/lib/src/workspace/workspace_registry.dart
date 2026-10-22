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

  /// Swaps the registered workspaces for [descriptors] (custom routes are
  /// kept). Lets a host re-shape navigation live — e.g. when the user turns an
  /// optional module on — instead of only at the next launch.
  void replaceWorkspaces(Iterable<WorkspaceDescriptor> descriptors) {
    _workspaces
      ..clear()
      ..addAll(descriptors);
  }

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

/// Decides whether a workspace location may render. Given the workspace id,
/// the custom route name (null for the workspace dashboard) and a builder for
/// the real screen, returns either that screen or a replacement (e.g. "this
/// optional feature is turned off"). Purely presentational: it never replaces
/// a permission or posting check. The default renders everything.
typedef WorkspaceRouteGate = Widget Function(
  BuildContext context, {
  required String workspaceId,
  required String? routeName,
  required WidgetBuilder child,
});

final workspaceRouteGateProvider = Provider<WorkspaceRouteGate?>((_) => null);

final permissionContextProvider = Provider<PermissionContext>(
  (_) => PermissionContext.open,
);

final visibleWorkspacesProvider = Provider<List<WorkspaceDescriptor>>((ref) {
  final reg = ref.watch(workspaceRegistryProvider);
  final ctx = ref.watch(permissionContextProvider);
  return reg.visibleFor(ctx);
});
