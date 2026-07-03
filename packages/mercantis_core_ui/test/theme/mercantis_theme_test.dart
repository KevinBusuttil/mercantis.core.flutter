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
  }
}
