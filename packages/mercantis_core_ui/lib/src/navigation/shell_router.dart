import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'navigation_shell.dart';
import '../views/doc_type_list_view.dart';
import '../views/generic_list_view.dart';
import '../views/generic_form_view.dart';
import '../views/form_builder_view.dart';

final shellRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) => NavigationShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DocTypeListView(),
          ),
          GoRoute(
            path: '/list/:docType',
            builder: (context, state) =>
                GenericListView(docTypeName: state.pathParameters['docType']!),
          ),
          GoRoute(
            path: '/form/:docType/new',
            builder: (context, state) => GenericFormView(
              docTypeName: state.pathParameters['docType']!,
              documentName: null,
            ),
          ),
          GoRoute(
            path: '/form/:docType/:name',
            builder: (context, state) => GenericFormView(
              docTypeName: state.pathParameters['docType']!,
              documentName: state.pathParameters['name'],
            ),
          ),
          GoRoute(
            path: '/form-builder/:docType',
            builder: (context, state) =>
                FormBuilderView(docTypeName: state.pathParameters['docType']!),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const _SettingsView(),
          ),
        ],
      ),
    ],
  );
});

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings coming soon')),
    );
  }
}
