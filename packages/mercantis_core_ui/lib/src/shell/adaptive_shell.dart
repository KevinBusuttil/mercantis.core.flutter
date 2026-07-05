import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/atlas/atlas_bottom_navigation.dart';
import '../theme/atlas/atlas_nav_destination.dart';
import '../theme/atlas/atlas_navigation_rail.dart';
import '../providers/notification_providers.dart';
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
    this.brandLabel = 'Mercantis',
    this.brandMark = 'M',
    this.notificationsLocation,
  });

  final Widget child;
  final String location;

  /// Route the shell bell navigates to, e.g. a workspace's notifications view.
  /// When null (the default), no bell is shown — the host opts in by threading
  /// a location. Skipped on phone, where the bottom bar has no room; the phone
  /// reaches notifications through a Home quick-action instead.
  final String? notificationsLocation;

  /// Product name shown beside the mark on the extended rail / sidebar, and the
  /// single glyph shown in the brand square. Defaults to the core studio brand;
  /// the hub overrides these (e.g. "Neuradix Atlas" / "N") so the shell reads
  /// the same as the rest of the app.
  final String brandLabel;
  final String brandMark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bp = Breakpoint.of(context);
    final visible = ref.watch(visibleWorkspacesProvider);
    if (visible.isEmpty) {
      return const Scaffold(body: Center(child: Text('No workspaces registered')));
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
          // Phone: a left-edge swipe goes up one level (form → its list →
          // home), matching the drill-in path. Only on phone, where the left
          // edge is content (no nav rail) and back-swipe is expected.
          Breakpoint.phone => _EdgeBackDetector(
              onBack: () {
                final parent = parentLocation(location);
                if (parent != null) context.go(parent);
              },
              child: _PhoneShell(
                visible: visible,
                selectedIndex: selected,
                child: child,
              ),
            ),
          Breakpoint.compact => _RailShell(
              visible: visible,
              selectedIndex: selected,
              extended: false,
              brandLabel: brandLabel,
              brandMark: brandMark,
              notificationsLocation: notificationsLocation,
              child: child,
            ),
          Breakpoint.medium => _RailShell(
              visible: visible,
              selectedIndex: selected,
              extended: true,
              brandLabel: brandLabel,
              brandMark: brandMark,
              notificationsLocation: notificationsLocation,
              child: child,
            ),
          Breakpoint.expanded => _SidebarShell(
              visible: visible,
              selectedIndex: selected,
              location: location,
              brandLabel: brandLabel,
              brandMark: brandMark,
              notificationsLocation: notificationsLocation,
              child: child,
            ),
        },
      ),
    );
  }
}

/// The location a left-edge back-swipe navigates to from [location] — one level
/// up the drill path. `/form/:type/:name` → its list, `/list/:type` → home,
/// `/w/:id/:route` → its workspace, `/w/:id` → home. Null at a top-level
/// location (nothing to go back to). Operates on the raw (still URL-encoded)
/// path segments so the rebuilt location matches how the route was addressed.
String? parentLocation(String location) {
  final q = location.indexOf('?');
  final path = q >= 0 ? location.substring(0, q) : location;
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  switch (segs.first) {
    case 'form':
      return segs.length >= 2 ? '/list/${segs[1]}' : '/';
    case 'list':
      return '/';
    case 'w':
      return segs.length >= 3 ? '/w/${segs[1]}' : '/';
    default:
      return null;
  }
}

/// Overlays a thin left-edge strip that turns a rightward swipe/flick into
/// [onBack]. The strip is narrow (24px) and only handles horizontal drags, so
/// taps and in-content gestures (row swipes, tab swipes) are unaffected.
class _EdgeBackDetector extends StatefulWidget {
  const _EdgeBackDetector({required this.onBack, required this.child});
  final VoidCallback onBack;
  final Widget child;

  @override
  State<_EdgeBackDetector> createState() => _EdgeBackDetectorState();
}

class _EdgeBackDetectorState extends State<_EdgeBackDetector> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _dx = 0,
            onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
            onHorizontalDragEnd: (d) {
              final flick = (d.primaryVelocity ?? 0) > 300;
              if (_dx > 90 || flick) widget.onBack();
              _dx = 0;
            },
          ),
        ),
      ],
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
    final destinations = <AtlasNavDestination>[
      for (final w in primary)
        AtlasNavDestination(
          icon: w.icon,
          selectedIcon: w.selectedIcon,
          label: w.navLabel,
        ),
      if (overflow.isNotEmpty)
        const AtlasNavDestination(
          icon: Icons.more_horiz,
          selectedIcon: Icons.more_horiz,
          label: 'More',
        ),
    ];

    final selectedIsInPrimary = selectedIndex < primary.length;
    final navIndex = selectedIsInPrimary ? selectedIndex : destinations.length - 1;

    return Scaffold(
      body: SafeArea(top: false, child: child),
      bottomNavigationBar: AtlasBottomNavigation(
        selectedIndex: navIndex,
        // Tint the selection pill with the active workspace's accent so the
        // module keeps its colour when the rail collapses to the bottom bar.
        accentColor: visible[selectedIndex].accentColor,
        destinations: destinations,
        onSelected: (i) {
          if (i < primary.length) {
            context.go(primary[i].path);
          } else {
            _showMore(context, overflow);
          }
        },
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
    required this.brandLabel,
    required this.brandMark,
    required this.notificationsLocation,
    required this.child,
  });

  final List<WorkspaceDescriptor> visible;
  final int selectedIndex;
  final bool extended;
  final String brandLabel;
  final String brandMark;
  final String? notificationsLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notificationsLocation = this.notificationsLocation;
    return Scaffold(
      body: Row(
        children: [
          _Brand(extended: extended, label: brandLabel, mark: brandMark),
          AtlasNavigationRail(
            extended: extended,
            selectedIndex: selectedIndex,
            // Tint the selection indicator with the active workspace's accent.
            accentColor: visible[selectedIndex].accentColor,
            onSelected: (i) => context.go(visible[i].path),
            leading: _SearchButton(extended: extended),
            // Pin the notifications bell to the bottom of the rail.
            trailing: notificationsLocation == null
                ? null
                : Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding:
                            const EdgeInsets.only(bottom: MercantisSpacing.lg),
                        child:
                            _NotificationBell(location: notificationsLocation),
                      ),
                    ),
                  ),
            destinations: [
              for (final w in visible)
                AtlasNavDestination(
                  icon: w.icon,
                  selectedIcon: w.selectedIcon,
                  // Full label beside the icon (extended rail) has room; the
                  // compact rail stacks it under the icon, so use the terse one.
                  label: extended ? w.label : w.navLabel,
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
  const _Brand({
    required this.extended,
    this.label = 'Mercantis',
    this.mark = 'M',
  });
  final bool extended;
  final String label;
  final String mark;

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
              decoration: const BoxDecoration(
                color: MercantisBrandColors.primary,
                borderRadius: MercantisRadius.rSm,
              ),
              alignment: Alignment.center,
              child: Text(
                mark,
                style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16,
                ),
              ),
            ),
            if (extended) ...[
              const SizedBox(width: MercantisSpacing.sm),
              // Flexible + ellipsis so a longer brand (e.g. "Neuradix Atlas")
              // can't overflow the fixed-width brand row on the narrow rail.
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

/// Shell bell: a notifications button badged with the current operator's unread
/// count of **addressed** messages (see
/// [notificationUnreadForCurrentUserProvider] — broadcasts are shown in the
/// inbox but don't drive the badge). Icon-only on the rail, a labelled row in
/// the sidebar footer. Tapping routes to the host-supplied [location].
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell({required this.location, this.labelled = false});

  final String location;
  final bool labelled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unread = ref.watch(notificationUnreadForCurrentUserProvider).maybeWhen(
          data: (c) => c,
          orElse: () => 0,
        );
    final badgedIcon = Badge.count(
      count: unread,
      isLabelVisible: unread > 0,
      child: const Icon(Icons.notifications_outlined),
    );

    if (!labelled) {
      return IconButton(
        icon: badgedIcon,
        tooltip: 'Notifications',
        onPressed: () => context.go(location),
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: MercantisRadius.rMd,
      child: InkWell(
        borderRadius: MercantisRadius.rMd,
        onTap: () => context.go(location),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              badgedIcon,
              const SizedBox(width: MercantisSpacing.sm),
              Expanded(
                child: Text('Notifications', style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sidebar (expanded) ──────────────────────────────────────────────────────

/// Which workspaces are expanded in the desktop sidebar (HU5 multi-expand).
/// A set, so any number of workspaces can be open at once. Held in a provider
/// so the expanded state survives the shell rebuilding on every in-shell
/// navigation — session-level persistence; a storage-backed notifier can later
/// replace this seam for cross-launch persistence.
final sidebarExpandedProvider =
    NotifierProvider<SidebarExpandedNotifier, Set<String>>(
        SidebarExpandedNotifier.new);

class SidebarExpandedNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String workspaceId) {
    final next = {...state};
    if (!next.remove(workspaceId)) next.add(workspaceId);
    state = next;
  }
}

/// Canonical item → route mapping, mirroring [WorkspaceView]'s item taps so the
/// sidebar and the workspace dashboard navigate identically.
String _sidebarItemPath(String workspaceId, WorkspaceItem item) {
  if (item is DocTypeWorkspaceItem) return '/list/${item.docType}';
  if (item is CustomWorkspaceItem) return '/w/$workspaceId/${item.routeName}';
  return '/w/$workspaceId'; // dashboard / report → workspace home
}

class _SidebarShell extends ConsumerStatefulWidget {
  const _SidebarShell({
    required this.visible,
    required this.selectedIndex,
    required this.location,
    required this.brandLabel,
    required this.brandMark,
    required this.notificationsLocation,
    required this.child,
  });

  final List<WorkspaceDescriptor> visible;
  final int selectedIndex;
  final String location;
  final String brandLabel;
  final String brandMark;
  final String? notificationsLocation;
  final Widget child;

  @override
  ConsumerState<_SidebarShell> createState() => _SidebarShellState();
}

class _SidebarShellState extends ConsumerState<_SidebarShell> {
  final _filterCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  bool _itemMatches(WorkspaceItem i, String q) =>
      i.resolvedLabel().toLowerCase().contains(q);

  bool _workspaceHasMatch(WorkspaceDescriptor w, String q) {
    if (w.label.toLowerCase().contains(q)) return true;
    for (final s in w.sections) {
      if (s.label.toLowerCase().contains(q)) return true;
      if (s.items.any((i) => _itemMatches(i, q))) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final expandedSet = ref.watch(sidebarExpandedProvider);
    final q = _query.trim().toLowerCase();
    final filtering = q.isNotEmpty;

    final shown = [
      for (final w in widget.visible)
        if (!filtering || _workspaceHasMatch(w, q)) w,
    ];
    final selectedWorkspace = widget.visible[widget.selectedIndex];

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 248,
            color: cs.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Brand(extended: true, label: widget.brandLabel, mark: widget.brandMark),
                const SizedBox(height: MercantisSpacing.lg),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: MercantisSpacing.lg),
                  child: _SearchButton(extended: true),
                ),
                const SizedBox(height: MercantisSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: MercantisSpacing.lg),
                  child: _SidebarFilterField(
                    controller: _filterCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    onClear: () => setState(() {
                      _filterCtrl.clear();
                      _query = '';
                    }),
                  ),
                ),
                const SizedBox(height: MercantisSpacing.xs),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(MercantisSpacing.lg),
                            child: Text('No matches',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                              vertical: MercantisSpacing.sm),
                          children: [
                            for (final w in shown)
                              _SidebarWorkspaceTile(
                                workspace: w,
                                selected: identical(w, selectedWorkspace),
                                location: widget.location,
                                query: q,
                                // While filtering, force matched workspaces open
                                // so the matching items are visible; otherwise use
                                // the persisted per-workspace expansion.
                                expanded:
                                    filtering || expandedSet.contains(w.id),
                                showToggle: !filtering && w.sections.isNotEmpty,
                                onToggle: () => ref
                                    .read(sidebarExpandedProvider.notifier)
                                    .toggle(w.id),
                              ),
                          ],
                        ),
                ),
                if (widget.notificationsLocation != null) ...[
                  Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: MercantisSpacing.sm,
                        vertical: MercantisSpacing.xs),
                    child: _NotificationBell(
                      location: widget.notificationsLocation!,
                      labelled: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          VerticalDivider(thickness: 1, width: 1, color: cs.outlineVariant),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _SidebarFilterField extends StatelessWidget {
  const _SidebarFilterField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: MercantisRadius.rMd,
      borderSide: BorderSide(color: cs.outlineVariant),
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Filter navigation',
        prefixIcon: const Icon(Icons.filter_list, size: 18),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 36, minHeight: 36),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Clear filter',
                visualDensity: VisualDensity.compact,
                onPressed: onClear,
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        filled: true,
        fillColor: cs.surfaceContainerLow,
        border: border,
        enabledBorder: border,
      ),
    );
  }
}

class _SidebarWorkspaceTile extends StatelessWidget {
  const _SidebarWorkspaceTile({
    required this.workspace,
    required this.selected,
    required this.location,
    required this.query,
    required this.expanded,
    required this.showToggle,
    required this.onToggle,
  });

  final WorkspaceDescriptor workspace;
  final bool selected;
  final String location;

  /// Lowercased filter query; empty when not filtering.
  final String query;
  final bool expanded;
  final bool showToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = workspace.accentColor ?? cs.primary;
    // A workspace-label match reveals all of its items; an item-level match
    // narrows to just the matching items.
    final wsLabelMatch =
        query.isNotEmpty && workspace.label.toLowerCase().contains(query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (showToggle)
                      InkWell(
                        borderRadius: MercantisRadius.rSm,
                        onTap: onToggle,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          for (final section in workspace.sections)
            ..._sectionRows(context, section, wsLabelMatch),
      ],
    );
  }

  List<Widget> _sectionRows(
      BuildContext context, WorkspaceSection section, bool wsLabelMatch) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sectionLabelMatch =
        query.isNotEmpty && section.label.toLowerCase().contains(query);
    final items = [
      for (final i in section.items)
        if (query.isEmpty ||
            wsLabelMatch ||
            sectionLabelMatch ||
            i.resolvedLabel().toLowerCase().contains(query))
          i,
    ];
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
            46, MercantisSpacing.sm, 12, MercantisSpacing.xs),
        child: Text(
          section.label.toUpperCase(),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.5),
        ),
      ),
      for (final item in items)
        _SidebarItemRow(
          workspaceId: workspace.id,
          item: item,
          active: location == _sidebarItemPath(workspace.id, item),
        ),
    ];
  }
}

class _SidebarItemRow extends StatelessWidget {
  const _SidebarItemRow({
    required this.workspaceId,
    required this.item,
    required this.active,
  });

  final String workspaceId;
  final WorkspaceItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: active ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: MercantisRadius.rSm,
        child: InkWell(
          borderRadius: MercantisRadius.rSm,
          onTap: () => context.go(_sidebarItemPath(workspaceId, item)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(46, 8, 10, 8),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon,
                      size: 16,
                      color: active ? cs.primary : cs.onSurfaceVariant),
                  const SizedBox(width: MercantisSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    item.resolvedLabel(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active ? cs.onSurface : cs.onSurfaceVariant,
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
