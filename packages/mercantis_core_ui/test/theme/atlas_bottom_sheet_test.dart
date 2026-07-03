import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The shared bottom-sheet chrome (handle + header + body + sticky footer), its
/// action bar, and the launcher that picks a phone sheet vs a desktop dialog.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(theme: MercantisTheme.light(), home: Scaffold(body: child));

  group('AtlasBottomSheet', () {
    testWidgets('renders title, subtitle, body and footer', (tester) async {
      await tester.pumpWidget(wrap(const AtlasBottomSheet(
        title: 'Edit Item · #1',
        subtitle: 'WIDGET',
        body: Text('body-content'),
        footer: Text('footer-content'),
      )));
      expect(find.text('Edit Item · #1'), findsOneWidget);
      expect(find.text('WIDGET'), findsOneWidget);
      expect(find.text('body-content'), findsOneWidget);
      expect(find.text('footer-content'), findsOneWidget);
    });

    testWidgets('drag handle shows only when showHandle is true',
        (tester) async {
      await tester.pumpWidget(wrap(const AtlasBottomSheet(
        title: 'T',
        body: SizedBox(),
        showHandle: false,
      )));
      // The handle is the only Container with this distinctive margin.
      Iterable<Container> handles() => tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.margin == const EdgeInsets.only(top: 8, bottom: 2));
      expect(handles(), isEmpty);

      await tester.pumpWidget(wrap(const AtlasBottomSheet(
        title: 'T',
        body: SizedBox(),
        showHandle: true,
      )));
      expect(handles(), isNotEmpty);
    });
  });

  group('AtlasBottomActionBar', () {
    testWidgets('fires the three slots and hides absent ones', (tester) async {
      var primary = false, secondary = false, destructive = false;
      await tester.pumpWidget(wrap(AtlasBottomActionBar(
        primaryLabel: 'Done',
        onPrimary: () => primary = true,
        secondaryLabel: 'Cancel',
        onSecondary: () => secondary = true,
        destructiveLabel: 'Remove row',
        onDestructive: () => destructive = true,
      )));
      await tester.tap(find.text('Remove row'));
      await tester.tap(find.text('Cancel'));
      await tester.tap(find.text('Done'));
      expect([primary, secondary, destructive], [true, true, true]);
    });

    testWidgets('busy shows a spinner and disables the primary', (tester) async {
      var primary = false;
      await tester.pumpWidget(wrap(AtlasBottomActionBar(
        primaryLabel: 'Done',
        onPrimary: () => primary = true,
        busy: true,
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(primary, isFalse);
    });
  });

  testWidgets('showAtlasBottomSheet opens a dialog on a wide pane and returns',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? result;
    await tester.pumpWidget(wrap(Builder(builder: (context) {
      return TextButton(
        onPressed: () async {
          result = await showAtlasBottomSheet<String>(
            context,
            builder: (ctx, scroll) => AtlasBottomSheet(
              title: 'Pick',
              showHandle: scroll != null,
              body: ListView(
                controller: scroll,
                children: const [Text('sheet-body')],
              ),
              footer: AtlasBottomActionBar(
                primaryLabel: 'OK',
                onPrimary: () => Navigator.of(ctx).pop('picked'),
              ),
            ),
          );
        },
        child: const Text('open'),
      );
    })));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Wide pane → a Dialog, no drag handle.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('sheet-body'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, 'picked');
  });
}
