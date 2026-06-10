import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/tokens/brand_colors.dart';
import '../theme/tokens/radius.dart';
import '../theme/tokens/spacing.dart';
import '../widgets/search/global_search.dart';
import '../workspace/workspace_descriptor.dart';
import '../workspace/workspace_registry.dart';
import 'breakpoints.dart';

class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({
    super.key,
    required this.child,
    required this.location,
  });

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bp = Breakpoint.of(context);
    final visible = ref.watch(visibleWorkspacesProvider);
    if (visible.isEmpty) {
      return Scaffold(body: Center(child: const Text('No workspaces registered')));
    }
    final selected = _selectedWorkspaceIndex(location, visible);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            showGlobalSearch(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            showGlobalSearch(context),
      },
      child: Focus(
        autofocus: true,
        child: switch (bp) {
          Breakpoint.phone => _PhoneShell(
              visible: visible,
              selectedIndex: selected,
              child: child,
            ),
          Breakpoint.compact => _RailShell(
              visible: visible,
              selectedIndex: selected,
              extended: false,
              child: child,
            ),
          Breakpoint.medium => _RailShell(
              visible: visible,
              selectedIndex: selected,
              extended: true,
              child: child,
            ),
          Breakpoint.expanded => _SidebarShell(
              visible: visible,
              selectedIndex: selected,
              child: child,
            ),
        },
      ),
    );
  }
}

int _selectedWorkspaceIndex(String loc, List<WorkspaceDescriptor> all) {
  int best = -1;
  int bestLen = 0;
  for (var i = 0; i < all.length; i++) {
    final p = all[i].path;
    if (loc == p || loc.startsWith('$p/')) {
      if (p.length > bestLen) {
        best = i;
        bestLen = p.length;
      }
    }
  }
  return best == -1 ? 0 : best;
}

// ─── Phone ───────────────────────────────────────────────────────────────────
class _PhoneShell extends StatelessWidget {
  const _PhoneShell({
    required this.visible,
    required this.selectedIndex,
    required this.child,
  });

  final List<WorkspaceDescriptor> visible;
  final int selectedIndex;
  final Widget child;

  static const _maxPrimary = 4;

  @override
  Widget build(BuildContext context) {
    final primary = visible.length <= _maxPrimary + 1
        ? visible
        : visible.take(_maxPrimary).toList();
    final overflow = visible.length <= _maxPrimary + 1
        ? const <WorkspaceDescriptor>[]
        : visible.skip(_maxPrimary).toList();
    final destinations = [
      for (final w in primary)
        NavigationDestination(
          icon: Icon(w.icon),
          selectedIcon: Icon(w.selectedIcon),
          label: w.navLabel,
        ),
      if (overflow.isNotEmpty)
        const NavigationDestination(
          icon: Icon(Icons.more_horiz),
          selectedIcon: Icon(Icons.more_horiz),
          label: 'More',
        ),
    ];

    final selectedIsInPrimary = selectedIndex < primary.length;
    final navIndex = selectedIsInPrimary ? selectedIndex : destinations.length - 1;

    return Scaffold(
      body: SafeArea(top: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: (i) {
          if (i < primary.length) {
            context.go(primary[i].path);
          } else {
            _showMore(context, overflow);
          }
        },
        destinations: destinations,
      ),
    );
  }

  void _showMore(BuildContext context, List<WorkspaceDescriptor> overflow) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          for (final w in overflow)
            ListTile(
              leading: Icon(w.icon),
              title: Text(w.label),
              subtitle: w.subtitle != null ? Text(w.subtitle!) : null,
              onTap: () {
                Navigator.of(context).pop();
                context.go(w.path);
              },
            ),
        ],
      ),
    );
  }
}

// ─── Rail (compact / medium) ─────────────────────────────────────────────────
class _RailShell extends StatelessWidget {
  const _RailShell({
    required this.visible,
    required this.selectedIndex,
    required this.extended,
    required this.child,
  });

  final List<WorkspaceDescriptor> visible;
  final int selectedIndex;
  final bool extended;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          _Brand(extended: extended),
          NavigationRail(
            extended: extended,
            minWidth: 72,
            minExtendedWidth: 220,
            selectedIndex: selectedIndex,
            onDestinationSelected: (i) => context.go(visible[i].path),
            leading: _SearchButton(extended: extended),
            destinations: [
              for (final w in visible)
                NavigationRailDestination(
                  icon: Icon(w.icon),
                  selectedIcon: Icon(w.selectedIcon),
                  // Full label beside the icon (extended rail) has room; the
                  // compact rail stacks it under the icon, so use the terse one.
                  label: Text(extended ? w.label : w.navLabel),
                ),
            ],
          ),
          VerticalDivider(thickness: 1, width: 1, color: cs.outlineVariant),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: MercantisSpacing.lg),
      child: SizedBox(
        width: extended ? 220 : 72,
        child: Row(
          mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            const SizedBox(width: MercantisSpacing.lg),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: MercantisBrandColors.primary,
                borderRadius: MercantisRadius.rSm,
              ),
              alignment: Alignment.center,
              child: const Text(
                'M',
                style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16,
                ),
              ),
            ),
            if (extended) ...[
              const SizedBox(width: MercantisSpacing.sm),
              Text(
                'Mercantis',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fixed width (matching the rail) so the extended layout's Spacer has a
    // bounded width even while the rail is measured under unbounded-width
    // intrinsic sizing. Mirrors [_Brand].
    return SizedBox(
      width: extended ? 220 : 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MercantisSpacing.sm, vertical: 12),
        child: InkWell(
          borderRadius: MercantisRadius.rMd,
          onTap: () => showGlobalSearch(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: MercantisRadius.rMd,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: extended ? MainAxisSize.max : MainAxisSize.min,
              children: [
                const Icon(Icons.search, size: 16),
                if (extended) ...[
                  const SizedBox(width: 6),
                  Text('Search', style: theme.textTheme.labelMedium),
                  const Spacer(),
                  Text('⌘K', style: theme.textTheme.labelSmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sidebar (expanded) ──────────────────────────────────────────────────────
class _SidebarShell extends StatelessWidget {
  const _SidebarShell({
    required this.visible,
    required this.selectedIndex,
    required this.child,
  });

  final List<WorkspaceDescriptor> visible;
  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 248,
            color: cs.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Brand(extended: true),
                const SizedBox(height: MercantisSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MercantisSpacing.lg),
                  child: _SearchButton(extended: true),
                ),
                const SizedBox(height: MercantisSpacing.sm),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: MercantisSpacing.sm),
                    children: [
                      for (var i = 0; i < visible.length; i++)
                        _SidebarTile(
                          workspace: visible[i],
                          selected: i == selectedIndex,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(thickness: 1, width: 1, color: cs.outlineVariant),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({required this.workspace, required this.selected});
  final WorkspaceDescriptor workspace;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = workspace.accentColor ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: MercantisRadius.rMd,
        child: InkWell(
          borderRadius: MercantisRadius.rMd,
          onTap: () => context.go(workspace.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? workspace.selectedIcon : workspace.icon,
                  size: 20,
                  color: selected ? accent : cs.onSurfaceVariant,
                ),
                const SizedBox(width: MercantisSpacing.sm),
                Expanded(
                  child: Text(
                    workspace.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? cs.onSurface : cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
