import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level UI preference: the theme mode. Persisted with `shared_preferences`
/// so it stays app-agnostic (no metadata DocType required) and survives
/// restarts. Apps watch [themeModeProvider] for `MaterialApp.themeMode` and
/// call [hydrate] once at start to load the saved value.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'core.theme_mode';

  @override
  ThemeMode build() => ThemeMode.system;

  /// Load the persisted mode. Call once at app start (before the first frame
  /// matters, but a late call simply repaints with the saved value).
  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    state = _decode(prefs.getString(_key)) ?? ThemeMode.system;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  static ThemeMode? _decode(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
