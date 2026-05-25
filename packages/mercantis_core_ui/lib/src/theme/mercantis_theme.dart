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
        border: OutlineInputBorder(borderRadius: MercantisRadius.rSm),
        filled: true,
        fillColor: cs.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rPill),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rMd),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rMd),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: cs.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rMd),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        selectedIconTheme: IconThemeData(color: cs.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: cs.onSurface),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => textTheme.labelSmall),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: cs.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rMd),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: MercantisRadius.rLg),
      ),
    );
  }
}
