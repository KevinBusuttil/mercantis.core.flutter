import 'package:flutter/widgets.dart';
import 'dashboard_card_spec.dart';
import 'quick_action.dart';

sealed class WorkspaceItem {
  const WorkspaceItem({this.label, this.icon, this.requiredRoles = const []});
  final String? label;
  final IconData? icon;
  final List<String> requiredRoles;

  String resolvedLabel();
}

class DocTypeWorkspaceItem extends WorkspaceItem {
  const DocTypeWorkspaceItem({
    required this.docType,
    super.label,
    super.icon,
    super.requiredRoles,
    this.listFilter,
    this.defaultSort,
    this.badgeBuilder,
    this.description,
  });

  final String docType;
  final Map<String, dynamic>? listFilter;
  final String? defaultSort;
  final String? badgeBuilder;
  final String? description;

  @override
  String resolvedLabel() => label ?? docType;
}

class DashboardWorkspaceItem extends WorkspaceItem {
  const DashboardWorkspaceItem({
    required this.dashboardId,
    super.label,
    super.icon,
    super.requiredRoles,
  });

  final String dashboardId;

  @override
  String resolvedLabel() => label ?? dashboardId;
}

class CustomWorkspaceItem extends WorkspaceItem {
  const CustomWorkspaceItem({
    required this.routeName,
    super.label,
    super.icon,
    super.requiredRoles,
    this.description,
  });

  final String routeName;
  final String? description;

  @override
  String resolvedLabel() => label ?? routeName;
}

class ReportWorkspaceItem extends WorkspaceItem {
  const ReportWorkspaceItem({
    required this.reportId,
    super.label,
    super.icon,
    super.requiredRoles,
  });

  final String reportId;

  @override
  String resolvedLabel() => label ?? reportId;
}

class WorkspaceSection {
  const WorkspaceSection({
    required this.label,
    required this.items,
    this.description,
    this.icon,
  });

  final String label;
  final String? description;
  final IconData? icon;
  final List<WorkspaceItem> items;
}

class WorkspaceDescriptor {
  const WorkspaceDescriptor({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.shortLabel,
    this.subtitle,
    this.accentColor,
    this.sections = const [],
    this.quickActions = const [],
    this.dashboardCards = const [],
    this.requiredRoles = const [],
    this.visibilityExpression,
    this.showInPrimaryNav = true,
    this.homeRoute,
    this.order = 100,
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// A terse label for tight navigation slots (phone bottom bar, compact rail),
  /// where the full [label] wraps. Falls back to [label] via [navLabel].
  final String? shortLabel;
  final String? subtitle;
  final Color? accentColor;
  final List<WorkspaceSection> sections;
  final List<QuickAction> quickActions;
  final List<DashboardCardSpec> dashboardCards;
  final List<String> requiredRoles;
  final String? visibilityExpression;
  final bool showInPrimaryNav;
  final String? homeRoute;
  final int order;

  String get path => '/w/$id';
  String get dashboardPath => '/w/$id';

  /// Label for cramped nav slots — [shortLabel] when set, else [label].
  String get navLabel => shortLabel ?? label;

  Iterable<DocTypeWorkspaceItem> get docTypeItems sync* {
    for (final s in sections) {
      for (final i in s.items) {
        if (i is DocTypeWorkspaceItem) yield i;
      }
    }
  }
}
