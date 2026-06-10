import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theme mode defaults to system, persists, and re-hydrates', () async {
    SharedPreferences.setMockInitialValues({});

    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    expect(c1.read(themeModeProvider), ThemeMode.system);

    await c1.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    expect(c1.read(themeModeProvider), ThemeMode.dark);

    // A fresh container loads the persisted value via hydrate().
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(c2.read(themeModeProvider), ThemeMode.system);
    await c2.read(themeModeProvider.notifier).hydrate();
    expect(c2.read(themeModeProvider), ThemeMode.dark);
  });
}
