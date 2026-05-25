import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

void main() {
  group('WorkspaceVisibilityFilter', () {
    const workspaces = <WorkspaceDescriptor>[
      WorkspaceDescriptor(
        id: 'home',
        label: 'Home',
        icon: Icons.home,
        selectedIcon: Icons.home,
      ),
      WorkspaceDescriptor(
        id: 'sales',
        label: 'Sales',
        icon: Icons.point_of_sale,
        selectedIcon: Icons.point_of_sale,
        sections: [
          WorkspaceSection(label: 'Documents', items: [
            DocTypeWorkspaceItem(docType: 'Sales Order'),
            DocTypeWorkspaceItem(docType: 'Sales Invoice'),
          ]),
        ],
      ),
      WorkspaceDescriptor(
        id: 'admin',
        label: 'Admin',
        icon: Icons.admin_panel_settings,
        selectedIcon: Icons.admin_panel_settings,
        requiredRoles: ['Administrator'],
        sections: [
          WorkspaceSection(label: 'Setup', items: [
            DocTypeWorkspaceItem(docType: 'User'),
          ]),
        ],
      ),
    ];

    test('open context shows everything', () {
      final visible = const WorkspaceVisibilityFilter()
          .apply(workspaces, PermissionContext.open);
      expect(visible.map((w) => w.id), ['home', 'sales', 'admin']);
    });

    test('role gate hides admin workspace for non-Administrator', () {
      final ctx = const PermissionContext(roles: ['Sales User']);
      final visible =
          const WorkspaceVisibilityFilter().apply(workspaces, ctx);
      expect(visible.map((w) => w.id), ['home', 'sales']);
    });

    test('docType permission hides individual items', () {
      final ctx = const PermissionContext(
        roles: ['Sales User'],
        docTypePermissions: {
          'Sales Order': {'read'},
          // Sales Invoice missing 'read' → hidden
          'Sales Invoice': {'write'},
        },
      );
      final visible =
          const WorkspaceVisibilityFilter().apply(workspaces, ctx);
      final sales = visible.firstWhere((w) => w.id == 'sales');
      final items = sales.sections.expand((s) => s.items).toList();
      expect(items.length, 1);
      expect((items.first as DocTypeWorkspaceItem).docType, 'Sales Order');
    });

    test('order is preserved by order field', () {
      const ws = <WorkspaceDescriptor>[
        WorkspaceDescriptor(
          id: 'late', label: 'Late',
          icon: Icons.home, selectedIcon: Icons.home, order: 99,
        ),
        WorkspaceDescriptor(
          id: 'early', label: 'Early',
          icon: Icons.home, selectedIcon: Icons.home, order: 1,
        ),
      ];
      final visible = const WorkspaceVisibilityFilter()
          .apply(ws, PermissionContext.open);
      expect(visible.map((w) => w.id), ['early', 'late']);
    });
  });
}
