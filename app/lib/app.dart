import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'shell_router.dart';

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
