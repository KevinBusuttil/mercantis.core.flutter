import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../shell/breakpoints.dart';
import '../shell/responsive_scaffold.dart';
import '../theme/tokens/radius.dart';
import '../theme/tokens/spacing.dart';
import '../widgets/quick_action_tile.dart';
import 'dashboard_card_spec.dart';
import 'quick_action.dart';
import 'workspace_descriptor.dart';

/// Dashboard host registry — Hub registers card data builders by id.
typedef DashboardCardBuilder = Widget Function(
  BuildContext context, DashboardCardSpec spec);

class DashboardCardHostRegistry {
  DashboardCardHostRegistry();
  final Map<String, DashboardCardBuilder> _byId = {};
  final Map<DashboardCardKind, DashboardCardBuilder> _byKind = {};

  void registerCard(String id, DashboardCardBuilder builder) =>
      _byId[id] = builder;
  void registerKindDefault(DashboardCardKind kind, DashboardCardBuilder builder) =>
      _byKind[kind] = builder;

  Widget build(BuildContext context, DashboardCardSpec spec) {
    final byId = _byId[spec.id];
    if (byId != null) return byId(context, spec);
    final byKind = _byKind[spec.kind];
    if (byKind != null) return byKind(context, spec);
    return _PlaceholderCard(spec: spec);
  }
}

final dashboardCardHostRegistryProvider = Provider<DashboardCardHostRegistry>(
  (_) => DashboardCardHostRegistry(),
);

class WorkspaceView extends ConsumerWidget {
  const WorkspaceView({super.key, required this.descriptor});
  final WorkspaceDescriptor descriptor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(dashboardCardHostRegistryProvider);
    final bp = Breakpoint.of(context);
    final isPhone = bp.isPhone;

    return ResponsiveScaffold(
      title: descriptor.label,
      subtitle: descriptor.subtitle,
      actions: isPhone
          ? const []
          : [
              if (descriptor.quickActions.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _showQuickActions(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Quick action'),
                ),
            ],
      body: CustomScrollView(
        slivers: [
          if (descriptor.dashboardCards.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _CardGrid(
                cards: descriptor.dashboardCards,
                builder: (c, s) => cards.build(c, s),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: MercantisSpacing.xl)),
          ],
          if (descriptor.quickActions.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(label: 'Quick actions'),
            ),
            SliverToBoxAdapter(
              child: _QuickActionsRow(
                actions: descriptor.quickActions,
                accent: descriptor.accentColor,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: MercantisSpacing.xl)),
          ],
          for (final section in descriptor.sections) ...[
            SliverToBoxAdapter(child: _SectionHeader(label: section.label, description: section.description)),
            SliverToBoxAdapter(child: _SectionGrid(section: section, workspaceId: descriptor.id, accent: descriptor.accentColor)),
            const SliverToBoxAdapter(child: SizedBox(height: MercantisSpacing.xl)),
          ],
        ],
      ),
      floatingActionButton: isPhone && descriptor.quickActions.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showQuickActions(context),
              icon: const Icon(Icons.add),
              label: const Text('Action'),
            )
          : null,
    );
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MercantisSpacing.lg, vertical: MercantisSpacing.sm,
              ),
              child: Text('Quick actions',
                style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final qa in descriptor.quickActions)
              ListTile(
                leading: Icon(qa.icon),
                title: Text(qa.label),
                subtitle: qa.description != null ? Text(qa.description!) : null,
                onTap: () {
                  Navigator.of(context).pop();
                  if (qa.docType != null) {
                    context.go('/form/${qa.docType}/new');
                  } else if (qa.routeName != null) {
                    context.go(qa.routeName!);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.description});
  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MercantisSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleMedium),
          if (description != null) ...[
            const SizedBox(height: 2),
            Text(description!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards, required this.builder});
  final List<DashboardCardSpec> cards;
  final Widget Function(BuildContext, DashboardCardSpec) builder;

  @override
  Widget build(BuildContext context) {
    final bp = Breakpoint.of(context);
    final cols = switch (bp) {
      Breakpoint.phone => 2,
      Breakpoint.compact => 3,
      Breakpoint.medium => 4,
      Breakpoint.expanded => 4,
    };
    final spacing = MercantisSpacing.md;
    return LayoutBuilder(
      builder: (context, c) {
        final totalSpacing = spacing * (cols - 1);
        final colWidth = (c.maxWidth - totalSpacing) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final s in cards)
              SizedBox(
                width: (colWidth * s.span + spacing * (s.span - 1))
                    .clamp(0, c.maxWidth)
                    .toDouble(),
                child: builder(context, s),
              ),
          ],
        );
      },
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.actions, this.accent});
  final List<QuickAction> actions;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final bp = Breakpoint.of(context);
    final cols = bp.isPhone ? 2 : (bp == Breakpoint.compact ? 3 : 4);
    return LayoutBuilder(builder: (context, c) {
      final spacing = MercantisSpacing.md;
      final colWidth = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final qa in actions)
            SizedBox(
              width: colWidth,
              child: QuickActionTile(
                action: qa,
                accentColor: accent,
                onTap: () {
                  if (qa.docType != null) {
                    GoRouter.of(context).go('/form/${qa.docType}/new');
                  } else if (qa.routeName != null) {
                    GoRouter.of(context).go(qa.routeName!);
                  }
                },
              ),
            ),
        ],
      );
    });
  }
}

class _SectionGrid extends StatelessWidget {
  const _SectionGrid({required this.section, required this.workspaceId, this.accent});
  final WorkspaceSection section;
  final String workspaceId;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final bp = Breakpoint.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cols = bp.isPhone ? 1 : (bp == Breakpoint.compact ? 2 : 3);
    return LayoutBuilder(builder: (context, c) {
      final spacing = MercantisSpacing.md;
      final colWidth = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final item in section.items)
            SizedBox(
              width: colWidth,
              child: Material(
                color: cs.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: MercantisRadius.rMd,
                  side: BorderSide(color: cs.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(
                    item.icon ?? _iconFor(item),
                    color: accent ?? cs.primary,
                  ),
                  title: Text(item.resolvedLabel()),
                  subtitle: _subtitleFor(item, theme),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _onTap(context, item),
                ),
              ),
            ),
        ],
      );
    });
  }

  IconData _iconFor(WorkspaceItem item) {
    if (item is DocTypeWorkspaceItem) return Icons.description_outlined;
    if (item is DashboardWorkspaceItem) return Icons.dashboard_outlined;
    if (item is ReportWorkspaceItem) return Icons.bar_chart_outlined;
    return Icons.chevron_right;
  }

  Widget? _subtitleFor(WorkspaceItem item, ThemeData theme) {
    if (item is DocTypeWorkspaceItem && item.description != null) {
      return Text(item.description!, style: theme.textTheme.bodySmall);
    }
    if (item is CustomWorkspaceItem && item.description != null) {
      return Text(item.description!, style: theme.textTheme.bodySmall);
    }
    return null;
  }

  void _onTap(BuildContext context, WorkspaceItem item) {
    if (item is DocTypeWorkspaceItem) {
      context.go('/list/${item.docType}');
    } else if (item is CustomWorkspaceItem) {
      context.go('/w/$workspaceId/${item.routeName}');
    } else if (item is DashboardWorkspaceItem) {
      context.go('/w/$workspaceId');
    }
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.spec});
  final DashboardCardSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: MercantisRadius.rLg,
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(MercantisSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(spec.title, style: theme.textTheme.labelMedium),
          const Spacer(),
          Text('—', style: theme.textTheme.displaySmall),
          if (spec.subtitle != null)
            Text(spec.subtitle!, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
