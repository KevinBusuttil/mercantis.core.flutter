import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const _ws = WorkspaceDescriptor(
  id: 'sales',
  label: 'Sales & Fulfilment',
  icon: Icons.point_of_sale_outlined,
  selectedIcon: Icons.point_of_sale,
  subtitle: 'Quotes to cash',
  sections: [
    WorkspaceSection(label: 'Orders', items: [
      DocTypeWorkspaceItem(docType: 'Sales Order'),
      DocTypeWorkspaceItem(docType: 'Sales Invoice'),
    ]),
  ],
  quickActions: [
    QuickAction(
      id: 'new_so', label: 'New Sales Order',
      icon: Icons.add_shopping_cart, docType: 'Sales Order',
    ),
  ],
);

void main() {
  testWidgets('WorkspaceView renders sections and quick actions',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) =>
          const WorkspaceView(descriptor: _ws)),
        GoRoute(path: '/form/:docType/new', builder: (_, __) =>
          const Scaffold(body: Text('new form'))),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        theme: MercantisTheme.light(),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sales & Fulfilment'), findsOneWidget);
    expect(find.text('Quotes to cash'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Sales Order'), findsOneWidget);
    expect(find.text('Sales Invoice'), findsOneWidget);
    expect(find.text('New Sales Order'), findsOneWidget);
  });
}
