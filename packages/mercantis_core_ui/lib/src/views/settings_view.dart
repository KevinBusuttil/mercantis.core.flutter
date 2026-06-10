import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/preferences_providers.dart';

/// Reusable app-settings surface for the Mercantis shell. Apps can route to it
/// directly or embed its sections. Currently exposes appearance (theme mode)
/// and an optional about block; structured to grow (locale, density, etc.).
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key, this.appName, this.appVersion});

  /// Shown in the About section when provided.
  final String? appName;
  final String? appVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Appearance', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final m in ThemeMode.values)
            RadioListTile<ThemeMode>(
              value: m,
              groupValue: mode,
              onChanged: (v) {
                if (v != null) {
                  ref.read(themeModeProvider.notifier).setMode(v);
                }
              },
              title: Text(_modeLabel(m)),
              secondary: Icon(_modeIcon(m)),
              contentPadding: EdgeInsets.zero,
            ),
          if (appName != null || appVersion != null) ...[
            const Divider(height: 32),
            Text('About', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: Text(appName ?? 'Mercantis'),
              subtitle:
                  appVersion == null ? null : Text('Version $appVersion'),
            ),
          ],
        ],
      ),
    );
  }

  static String _modeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => 'System default',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  static IconData _modeIcon(ThemeMode m) => switch (m) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };
}
