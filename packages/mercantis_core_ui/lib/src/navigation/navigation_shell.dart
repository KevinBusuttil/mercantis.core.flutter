import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.path);
  final String label;
  final Widget icon;
  final Widget selectedIcon;
  final String path;
}

const _destinations = [
  _Dest('Home', Icon(Icons.home_outlined), Icon(Icons.home), '/home'),
  _Dest('Documents', Icon(Icons.description_outlined), Icon(Icons.description), '/home'),
  _Dest('Settings', Icon(Icons.settings_outlined), Icon(Icons.settings), '/settings'),
];

class NavigationShell extends ConsumerWidget {
  const NavigationShell({super.key, required this.child});
  final Widget child;

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _destinations.length; i++) {
      if (loc.startsWith(_destinations[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final selected = _selectedIndex(context);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: (i) => context.go(_destinations[i].path),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: FlutterLogo(size: 32),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon,
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => context.go(_destinations[i].path),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: d.icon,
              selectedIcon: d.selectedIcon,
              label: d.label,
            ),
        ],
      ),
    );
  }
}
