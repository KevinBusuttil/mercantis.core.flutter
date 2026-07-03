import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Step 6 of the Atlas rollout: the app-shell nav chrome (bottom-nav, rail,
/// tabs) is themed to one coherent language — a calm primary-tinted indicator
/// with the selected icon/label in the primary colour — instead of three
/// different Material 3 defaults.
void main() {
  for (final entry in {
    'light': MercantisTheme.light(),
    'dark': MercantisTheme.dark(),
  }.entries) {
    final name = entry.key;
    final theme = entry.value;
    final cs = theme.colorScheme;

    test('$name: nav indicators use the soft primary tint, not primaryContainer',
        () {
      expect(theme.navigationBarTheme.indicatorColor,
          cs.primary.withValues(alpha: 0.12));
      expect(theme.navigationRailTheme.indicatorColor,
          cs.primary.withValues(alpha: 0.12));
    });

    test('$name: the selected bottom-nav icon and label are primary', () {
      final selected = <WidgetState>{WidgetState.selected};
      final unselected = <WidgetState>{};

      final selIcon =
          theme.navigationBarTheme.iconTheme?.resolve(selected)?.color;
      final unselIcon =
          theme.navigationBarTheme.iconTheme?.resolve(unselected)?.color;
      expect(selIcon, cs.primary);
      expect(unselIcon, cs.onSurfaceVariant);

      final selLabel =
          theme.navigationBarTheme.labelTextStyle?.resolve(selected);
      expect(selLabel?.color, cs.primary);
      expect(selLabel?.fontWeight, FontWeight.w700);
    });

    test('$name: tabs carry the primary indicator + primary selected label',
        () {
      expect(theme.tabBarTheme.indicatorColor, cs.primary);
      expect(theme.tabBarTheme.labelColor, cs.primary);
      expect(theme.tabBarTheme.unselectedLabelColor, cs.onSurfaceVariant);
    });

    test('$name: registers the AtlasColors extension derived from the scheme',
        () {
      final atlas = theme.extension<AtlasColors>();
      expect(atlas, isNotNull);
      expect(atlas!.primary, cs.primary);
      expect(atlas.primarySoft, cs.primary.withValues(alpha: 0.12));
    });

    test('$name: bottom sheet + FAB carry the Atlas baseline', () {
      // Sheets get 24pt top corners and a quiet drag handle.
      expect(theme.bottomSheetTheme.shape, isA<RoundedRectangleBorder>());
      expect(theme.bottomSheetTheme.dragHandleColor, isNotNull);
      // FAB is flatter than the M3 default (6) to match the elevation-0 chrome.
      expect(theme.floatingActionButtonTheme.elevation, 1);
    });
  }
}
