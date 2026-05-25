import 'package:flutter/material.dart';

class MercantisTypography {
  const MercantisTypography._();

  static TextTheme build(ColorScheme cs) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: cs.onSurface,
      ),
      displayMedium: TextStyle(
        fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: cs.onSurface,
      ),
      displaySmall: TextStyle(
        fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: cs.onSurface,
      ),
      headlineLarge: TextStyle(
        fontSize: 24, fontWeight: FontWeight.w700, color: cs.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 16, height: 1.35, color: cs.onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14, height: 1.35, color: cs.onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 12, height: 1.3, color: cs.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.4,
      ),
      labelSmall: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 0.5,
      ),
    );
  }
}
