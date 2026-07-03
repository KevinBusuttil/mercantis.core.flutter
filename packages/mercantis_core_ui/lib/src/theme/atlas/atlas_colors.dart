import 'package:flutter/material.dart';

import '../tokens/brand_colors.dart';

/// Semantic colour tokens for the Neuradix Atlas design system — the single
/// named source for surface, text, border and status colours so widgets stop
/// hand-tuning raw `ColorScheme` roles with drifting alphas (the audit found
/// `primary@0.10` vs `0.12`, `outlineVariant@0.7` vs `0.8` scattered inline).
///
/// Values are *derived* from the ambient [ColorScheme] (which itself adapts to
/// light/dark via `ColorScheme.fromSeed`), so there is no competing palette and
/// dark mode keeps working for free. Registered on [ThemeData.extensions] for
/// smooth lerping and future authored overrides, but [of] falls back to
/// deriving from the ambient scheme when the extension isn't registered, so it
/// is safe to read from any `MaterialApp` (including bare-theme tests).
@immutable
class AtlasColors extends ThemeExtension<AtlasColors> {
  const AtlasColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.primary,
    required this.primarySoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.borderSoft,
    required this.borderSubtle,
    required this.success,
    required this.warning,
    required this.danger,
    required this.disabled,
  });

  /// The neutral page backdrop behind cards.
  final Color background;

  /// A card / field-row fill (the calm near-white surface).
  final Color surface;

  /// A slightly recessed surface (e.g. a stepper track, muted chip).
  final Color surfaceMuted;

  /// A raised surface (e.g. the pinned totals summary card).
  final Color surfaceElevated;

  final Color primary;

  /// The primary accent at a soft tint — icon chips, selected pills, the grand
  /// total block. One canonical alpha instead of the drifting inline values.
  final Color primarySoft;

  final Color textPrimary;
  final Color textSecondary;

  /// The quietest readable text — placeholders, disabled-ish captions.
  final Color textMuted;

  /// The default hairline border on cards and field rows.
  final Color borderSoft;

  /// An even lighter divider (nested content, subtle separators).
  final Color borderSubtle;

  final Color success;
  final Color warning;
  final Color danger;
  final Color disabled;

  /// Derives the token set from a [ColorScheme]. This is the one place the
  /// Atlas colour vocabulary maps onto Material 3 roles.
  factory AtlasColors.fromColorScheme(ColorScheme cs) => AtlasColors(
        background: cs.surface,
        surface: cs.surfaceContainerLowest,
        surfaceMuted: cs.surfaceContainerHigh,
        surfaceElevated: cs.surfaceContainer,
        primary: cs.primary,
        primarySoft: cs.primary.withValues(alpha: 0.12),
        textPrimary: cs.onSurface,
        textSecondary: cs.onSurfaceVariant,
        textMuted: cs.onSurfaceVariant.withValues(alpha: 0.75),
        borderSoft: cs.outlineVariant.withValues(alpha: 0.7),
        borderSubtle: cs.outlineVariant.withValues(alpha: 0.4),
        success: MercantisBrandColors.statusApproved,
        warning: MercantisBrandColors.statusPending,
        danger: cs.error,
        disabled: cs.onSurfaceVariant.withValues(alpha: 0.38),
      );

  /// Reads the registered extension, or derives from the ambient scheme when it
  /// isn't registered — so callers never need to null-check.
  static AtlasColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AtlasColors>() ??
        AtlasColors.fromColorScheme(theme.colorScheme);
  }

  @override
  AtlasColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceElevated,
    Color? primary,
    Color? primarySoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? borderSoft,
    Color? borderSubtle,
    Color? success,
    Color? warning,
    Color? danger,
    Color? disabled,
  }) =>
      AtlasColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceMuted: surfaceMuted ?? this.surfaceMuted,
        surfaceElevated: surfaceElevated ?? this.surfaceElevated,
        primary: primary ?? this.primary,
        primarySoft: primarySoft ?? this.primarySoft,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        borderSoft: borderSoft ?? this.borderSoft,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        disabled: disabled ?? this.disabled,
      );

  @override
  AtlasColors lerp(ThemeExtension<AtlasColors>? other, double t) {
    if (other is! AtlasColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AtlasColors(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      primary: c(primary, other.primary),
      primarySoft: c(primarySoft, other.primarySoft),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      borderSoft: c(borderSoft, other.borderSoft),
      borderSubtle: c(borderSubtle, other.borderSubtle),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      disabled: c(disabled, other.disabled),
    );
  }
}
