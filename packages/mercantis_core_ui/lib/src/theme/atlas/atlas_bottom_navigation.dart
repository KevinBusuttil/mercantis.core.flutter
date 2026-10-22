import 'package:flutter/material.dart';

import 'atlas_nav_destination.dart';

/// Themed bottom navigation bar for the phone shell. Wraps Material's
/// [NavigationBar] and tints the selection pill with the active workspace's
/// [accentColor], matching [AtlasNavigationRail] so a module keeps its colour as
/// the layout collapses from rail to bottom bar. Otherwise defers to the app's
/// `NavigationBarTheme`.
class AtlasBottomNavigation extends StatelessWidget {
  const AtlasBottomNavigation({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.accentColor,
  });

  final List<AtlasNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Selection-pill tint; falls back to the theme primary when null.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = accentColor ?? cs.primary;
    // Five labels share a phone's width, so their text scales only a little
    // (as platform tab bars do): beyond that they break mid-word. Long-press
    // shows each label in a tooltip; screen readers read it as normal.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        indicatorColor: accent.withValues(alpha: 0.16),
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
              tooltip: d.tooltip,
            ),
        ],
      ),
    );
  }
}
