import 'package:flutter/material.dart';
import 'tokens/brand_colors.dart';
import 'tokens/radius.dart';
import 'tokens/typography.dart';

class MercantisTheme {
  MercantisTheme._();

  static ThemeData light() => _buildTheme(
        ColorScheme.fromSeed(
          seedColor: MercantisBrandColors.primary,
          brightness: Brightness.light,
        ),
      );

  static ThemeData dark() => _buildTheme(
        ColorScheme.fromSeed(
          seedColor: MercantisBrandColors.primary,
          brightness: Brightness.dark,
        ),
      );

  static ThemeData _buildTheme(ColorScheme cs) {
    final textTheme = MercantisTypography.build(cs);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      textTheme: textTheme,
      scaffoldBackgroundColor: cs.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: MercantisRadius.rLg,
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(borderRadius: MercantisRadius.rSm),
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1, space: 1),
      chipTheme: const ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rPill),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: MercantisRadius.rMd),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: MercantisRadius.rMd),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: cs.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: MercantisRadius.rMd),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      // Atlas nav language: a calm primary-tinted indicator pill with the
      // selected icon/label in the primary colour — the same treatment the
      // expanded sidebar uses — so the bottom-nav, rail and sidebar read as
      // one system rather than three different M3 defaults.
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.primary.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: cs.primary),
        unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium
            ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.primary.withValues(alpha: 0.12),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? cs.primary
                : cs.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => (textTheme.labelSmall ?? const TextStyle()).copyWith(
            color: states.contains(WidgetState.selected)
                ? cs.primary
                : cs.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      // Tabs (record detail, reports) share the primary indicator + strong
      // selected label so tabbed surfaces match the rest of the Atlas chrome.
      tabBarTheme: TabBarThemeData(
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: cs.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: cs.outlineVariant,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: cs.onSurfaceVariant,
        shape: const RoundedRectangleBorder(borderRadius: MercantisRadius.rMd),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rLg),
      ),
    );
  }
}
