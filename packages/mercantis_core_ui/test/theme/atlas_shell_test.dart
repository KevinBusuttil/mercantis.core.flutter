import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Phase 4b: the shell header/tabs primitives. AtlasHeader wraps the themed
/// AppBar (title + optional subtitle + actions + optional bottom), and AtlasTabs
/// builds themed Tabs from plain labels and drives its controller. These lock
/// the APIs the record workspace (and later the hub) render their chrome with.
void main() {
  testWidgets('AtlasHeader shows title, subtitle and actions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AtlasHeader(
          title: 'SO-0001',
          subtitle: 'Draft',
          actions: [
            IconButton(icon: const Icon(Icons.tune), onPressed: () {}),
          ],
        ),
        body: const SizedBox.shrink(),
      ),
    ));
    expect(find.text('SO-0001'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
  });

  testWidgets('AtlasHeader.preferredSize grows by the bottom height',
      (tester) async {
    // Capture a controller to feed AtlasTabs as the header bottom.
    late TabController controller;
    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 2,
        child: Builder(builder: (context) {
          controller = DefaultTabController.of(context);
          final tabs = AtlasTabs(
            controller: controller,
            labels: const ['One', 'Two'],
          );
          final withBottom = AtlasHeader(title: 'T', bottom: tabs);
          final withoutBottom = const AtlasHeader(title: 'T');
          // The bottom (tab bar) adds exactly its own preferred height.
          expect(withBottom.preferredSize.height,
              withoutBottom.preferredSize.height + tabs.preferredSize.height);
          return Scaffold(appBar: withBottom, body: const SizedBox.shrink());
        }),
      ),
    ));
    expect(find.widgetWithText(Tab, 'One'), findsOneWidget);
  });

  testWidgets('AtlasHeader shows a search action (before other actions) that '
      'fires onSearch, and omits it when null', (tester) async {
    var searched = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AtlasHeader(
          title: 'SO-0001',
          onSearch: () => searched = true,
          actions: [IconButton(icon: const Icon(Icons.tune), onPressed: () {})],
        ),
        body: const SizedBox.shrink(),
      ),
    ));
    expect(find.byIcon(Icons.search), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search));
    expect(searched, isTrue);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(appBar: AtlasHeader(title: 'T'), body: SizedBox.shrink()),
    ));
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets('AtlasTabs renders Tabs from labels and drives its controller',
      (tester) async {
    await tester.pumpWidget(const _TabsHarness(labels: ['Alpha', 'Beta', 'Gamma']));

    expect(find.widgetWithText(Tab, 'Alpha'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Beta'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Gamma'), findsOneWidget);

    final state =
        tester.state<_TabsHarnessState>(find.byType(_TabsHarness));
    expect(state.controller.index, 0);

    await tester.tap(find.widgetWithText(Tab, 'Gamma'));
    await tester.pumpAndSettle();
    expect(state.controller.index, 2);
  });
}

class _TabsHarness extends StatefulWidget {
  const _TabsHarness({required this.labels});
  final List<String> labels;

  @override
  State<_TabsHarness> createState() => _TabsHarnessState();
}

class _TabsHarnessState extends State<_TabsHarness>
    with SingleTickerProviderStateMixin {
  late final TabController controller =
      TabController(length: widget.labels.length, vsync: this);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AtlasHeader(
          title: 'Tabs',
          bottom: AtlasTabs(controller: controller, labels: widget.labels),
        ),
        body: TabBarView(
          controller: controller,
          children: [for (final l in widget.labels) Text('body-$l')],
        ),
      ),
    );
  }
}
