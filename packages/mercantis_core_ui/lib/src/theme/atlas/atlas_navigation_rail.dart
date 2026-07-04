import 'package:flutter/material.dart';

import 'atlas_nav_destination.dart';

/// Themed navigation rail for the compact/medium/expanded shells. Wraps
/// Material's [NavigationRail] and tints the selection indicator (and selected
/// icon) with the active workspace's [accentColor], so each module reads in its
/// own colour instead of a single global primary. Otherwise defers to the app's
/// `NavigationRailTheme`.
class AtlasNavigationRail extends StatelessWidget {
  const AtlasNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.extended = false,
    this.leading,
    this.trailing,
    this.accentColor,
    this.minWidth = 72,
    this.minExtendedWidth = 220,
  });

  final List<AtlasNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool extended;
  final Widget? leading;
  final Widget? trailing;

  /// Selection-indicator tint; falls back to the theme primary when null.
  final Color? accentColor;
  final double minWidth;
  final double minExtendedWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = accentColor ?? cs.primary;
    return NavigationRail(
      extended: extended,
      minWidth: minWidth,
      minExtendedWidth: minExtendedWidth,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      leading: leading,
      trailing: trailing,
      useIndicator: true,
      indicatorColor: accent.withValues(alpha: 0.14),
      selectedIconTheme: IconThemeData(color: accent),
      destinations: [
        for (final d in destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label),
          ),
      ],
    );
  }
}
