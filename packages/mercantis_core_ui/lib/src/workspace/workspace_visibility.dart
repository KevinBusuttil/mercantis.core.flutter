import 'workspace_descriptor.dart';

class PermissionContext {
  const PermissionContext({
    this.roles = const [],
    this.userId,
    this.docTypePermissions = const {},
  });

  final List<String> roles;
  final String? userId;

  /// Map of docTypeId -> set of granted operations ('read','write','create',...).
  final Map<String, Set<String>> docTypePermissions;

  bool hasAnyRole(List<String> required) {
    if (required.isEmpty) return true;
    return required.any(roles.contains);
  }

  bool canRead(String docType) {
    final ops = docTypePermissions[docType];
    if (ops == null) return true;
    return ops.contains('read');
  }

  static const PermissionContext open = PermissionContext();
}

class WorkspaceVisibilityFilter {
  const WorkspaceVisibilityFilter();

  List<WorkspaceDescriptor> apply(
    List<WorkspaceDescriptor> all,
    PermissionContext ctx,
  ) {
    final visible = <WorkspaceDescriptor>[];
    for (final w in all) {
      if (!ctx.hasAnyRole(w.requiredRoles)) continue;
      final keptSections = <WorkspaceSection>[];
      for (final s in w.sections) {
        final keptItems = s.items.where((i) {
          if (!ctx.hasAnyRole(i.requiredRoles)) return false;
          if (i is DocTypeWorkspaceItem) return ctx.canRead(i.docType);
          return true;
        }).toList();
        if (keptItems.isNotEmpty) {
          keptSections.add(WorkspaceSection(
            label: s.label,
            description: s.description,
            icon: s.icon,
            items: keptItems,
          ));
        }
      }
      if (keptSections.isEmpty && w.dashboardCards.isEmpty && w.quickActions.isEmpty) {
        continue;
      }
      visible.add(WorkspaceDescriptor(
        id: w.id,
        label: w.label,
        icon: w.icon,
        selectedIcon: w.selectedIcon,
        subtitle: w.subtitle,
        accentColor: w.accentColor,
        sections: keptSections,
        quickActions: w.quickActions,
        dashboardCards: w.dashboardCards,
        requiredRoles: w.requiredRoles,
        visibilityExpression: w.visibilityExpression,
        showInPrimaryNav: w.showInPrimaryNav,
        homeRoute: w.homeRoute,
        order: w.order,
      ));
    }
    visible.sort((a, b) => a.order.compareTo(b.order));
    return visible;
  }
}
