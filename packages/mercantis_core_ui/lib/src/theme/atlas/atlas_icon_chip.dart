import 'package:flutter/material.dart';

import '../tokens/radius.dart';
import 'atlas_colors.dart';

/// The tinted rounded-square that carries a leading glyph — the single source
/// for the icon chip that was previously re-implemented inline across the
/// field rows and the dashboard cards (KPI/list/quick-action) with drifting
/// sizes and alphas. Defaults match the original field-row chip (36×36, medium
/// radius, 18px glyph, primary tint); dashboard cards pass their own size /
/// radius / accent.
class AtlasIconChip extends StatelessWidget {
  const AtlasIconChip({
    super.key,
    required this.icon,
    this.accent,
    this.size = 36,
    this.radius = MercantisRadius.rMd,
    this.iconSize = 18,
    this.backgroundAlpha = 0.12,
  });

  final IconData icon;

  /// Foreground/background hue. Null uses the Atlas primary (and its canonical
  /// soft tint for the fill).
  final Color? accent;
  final double size;
  final BorderRadius radius;
  final double iconSize;
  final double backgroundAlpha;

  @override
  Widget build(BuildContext context) {
    final atlas = AtlasColors.of(context);
    final fg = accent ?? atlas.primary;
    final bg =
        accent == null ? atlas.primarySoft : accent!.withValues(alpha: backgroundAlpha);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Icon(icon, size: iconSize, color: fg),
    );
  }
}
