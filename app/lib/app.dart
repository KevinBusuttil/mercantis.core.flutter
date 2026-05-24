import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

class MercantisCoreApp extends ConsumerWidget {
  const MercantisCoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(mercantisDatabaseProvider);
    final router = ref.watch(shellRouterProvider);

    return dbAsync.when(
      loading: () => const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Database error: $e')),
        ),
      ),
      data: (_) => MaterialApp.router(
        title: 'Mercantis Core',
        theme: MercantisTheme.light(),
        darkTheme: MercantisTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

// Boot sequence: registers built-in DocTypes then starts the app.
class _Bootstrapper extends ConsumerWidget {
  const _Bootstrapper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installerAsync = ref.watch(appInstallerProvider);
    return installerAsync.when(
      loading: () => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlutterLogo(size: 64),
                SizedBox(height: 24),
                CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      error: (e, _) => MaterialApp(
        home: Scaffold(body: Center(child: Text('Boot error: $e'))),
      ),
      data: (_) => child,
    );
  }
}
