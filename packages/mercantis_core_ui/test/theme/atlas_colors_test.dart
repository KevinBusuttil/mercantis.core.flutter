import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// AtlasColors is the single semantic colour source: derived from the ambient
/// ColorScheme (so light/dark keep working), readable via a null-safe [of]
/// even when the extension isn't registered.
void main() {
  test('fromColorScheme derives the canonical soft-primary tint', () {
    final cs = const ColorScheme.light();
    final atlas = AtlasColors.fromColorScheme(cs);
    expect(atlas.primary, cs.primary);
    expect(atlas.primarySoft, cs.primary.withValues(alpha: 0.12));
    expect(atlas.borderSoft, cs.outlineVariant.withValues(alpha: 0.7));
    expect(atlas.textMuted, cs.onSurfaceVariant.withValues(alpha: 0.75));
  });

  test('light and dark derive distinct values', () {
    final light = AtlasColors.fromColorScheme(
        ColorScheme.fromSeed(seedColor: const Color(0xFF4A6FA5)));
    final dark = AtlasColors.fromColorScheme(ColorScheme.fromSeed(
        seedColor: const Color(0xFF4A6FA5), brightness: Brightness.dark));
    expect(light.surface, isNot(dark.surface));
    expect(light.textPrimary, isNot(dark.textPrimary));
  });

  test('lerp interpolates and copyWith overrides one field', () {
    final a = AtlasColors.fromColorScheme(const ColorScheme.light());
    final b = a.copyWith(primary: const Color(0xFF000000));
    expect(b.primary, const Color(0xFF000000));
    expect(b.surface, a.surface);
    final mid = a.lerp(b, 0.5);
    expect(mid, isA<AtlasColors>());
  });

  testWidgets('of() falls back to a derived set without registration',
      (tester) async {
    late AtlasColors seen;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        seen = AtlasColors.of(context);
        return const SizedBox();
      }),
    ));
    // No AtlasColors registered on the default theme → derived, not null.
    final cs = Theme.of(tester.element(find.byType(SizedBox))).colorScheme;
    expect(seen.primarySoft, cs.primary.withValues(alpha: 0.12));
  });

  testWidgets('of() returns the registered extension under MercantisTheme',
      (tester) async {
    late AtlasColors seen;
    await tester.pumpWidget(MaterialApp(
      theme: MercantisTheme.light(),
      home: Builder(builder: (context) {
        seen = AtlasColors.of(context);
        return const SizedBox();
      }),
    ));
    expect(seen.primary, MercantisTheme.light().colorScheme.primary);
  });
}
