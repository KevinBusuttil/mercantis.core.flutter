import 'package:flutter/material.dart';

/// The Atlas floating action button. A thin wrapper over Material's
/// [FloatingActionButton] that picks the compact vs. extended form from whether
/// a [label] is supplied, and otherwise defers entirely to the app's
/// `floatingActionButtonTheme` (a flatter elevation than the M3 default, so the
/// FAB matches the elevation-0 Atlas chrome instead of floating heavily).
///
/// Giving every screen one FAB entry point means the label/icon conventions and
/// weight stay consistent as the hub adopts Atlas — callers stop hand-rolling
/// `FloatingActionButton.extended(...)` per screen.
class AtlasFloatingActionButton extends StatelessWidget {
  const AtlasFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;

  /// When non-null the FAB renders in its extended (pill) form with the label
  /// beside the icon; when null it's a compact circular FAB (use [tooltip] to
  /// keep it labelled for accessibility).
  final String? label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon),
        label: Text(label!),
      );
    }
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: tooltip ?? label,
      child: Icon(icon),
    );
  }
}
