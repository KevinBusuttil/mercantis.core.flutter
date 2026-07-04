import 'package:flutter/widgets.dart';

/// A single navigation target shared by [AtlasNavigationRail] and
/// [AtlasBottomNavigation] — an icon (plus a selected variant) and a label.
/// Kept a plain data class so the same descriptor list feeds either surface as
/// the layout changes across breakpoints.
class AtlasNavDestination {
  const AtlasNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
