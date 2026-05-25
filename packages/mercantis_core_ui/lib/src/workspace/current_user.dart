import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../providers/core_providers.dart';
import 'workspace_visibility.dart';

/// Identifies the current user. Hub overrides this to plug in real auth.
class CurrentUser {
  const CurrentUser({
    required this.id,
    this.displayName,
    this.email,
    this.roles = const {'System Manager'},
  });

  final String id;
  final String? displayName;
  final String? email;
  final Set<String> roles;

  bool hasRole(String role) => roles.contains(role);

  static const guest = CurrentUser(id: 'guest', roles: {});
}

/// Default current user — Hub overrides this to wire real auth.
final currentUserProvider = Provider<CurrentUser>(
  (_) => const CurrentUser(
    id: 'local-user',
    displayName: 'Local user',
    roles: {'System Manager'},
  ),
);

/// Async PermissionContext computed from the current user and the
/// per-DocType permission rules already loaded into the metadata
/// registry. Workspaces and items the user can't see are filtered out
/// of the navigation by [visibleWorkspacesProvider] once Hub overrides
/// [permissionContextProvider] to read this future.
final metadataPermissionContextProvider =
    FutureProvider<PermissionContext>((ref) async {
  final user = ref.watch(currentUserProvider);
  final registry = await ref.watch(metadataRegistryProvider.future);
  final engine = ref.watch(permissionEngineProvider);
  final allTypes = await registry.all();

  final perms = <String, Set<String>>{};
  for (final type in allTypes) {
    final ops = <String>{};
    for (final entry in const [
      ('read', DocumentOperation.read),
      ('write', DocumentOperation.write),
      ('create', DocumentOperation.create),
      ('delete', DocumentOperation.delete),
      ('submit', DocumentOperation.submit),
      ('amend', DocumentOperation.amend),
    ]) {
      if (engine.canPerform(
        operation: entry.$2, on: type, userRoles: user.roles,
      )) {
        ops.add(entry.$1);
      }
    }
    perms[type.id] = ops;
  }
  return PermissionContext(
    roles: user.roles.toList(),
    userId: user.id,
    docTypePermissions: perms,
  );
});
