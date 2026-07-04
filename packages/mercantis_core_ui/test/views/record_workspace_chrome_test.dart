import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Increment 3 of the responsive-forms work: on wide panes the record chrome
/// keeps Timeline + Attachments in a persistent side panel next to the form
/// (their own sub-tabs) instead of hiding them behind the main Form/Timeline/
/// Attachments tab bar; narrow panes keep the tabs. A new (unsaved) document is
/// used so the panels short-circuit to their placeholders and no providers are
/// touched.
void main() {
  Future<void> pump(WidgetTester tester, Size size,
      {String? documentName}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: RecordWorkspaceChrome(
          docTypeName: 'Quotation',
          documentName: documentName,
          isDirty: false,
          isSaving: false,
          isSubmittable: false,
          docStatus: 0,
          onSave: () {},
          onSubmit: () {},
          child: const Text('FORM_MARKER'),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('narrow: Form/Timeline/Attachments as peer tabs; form visible',
      (tester) async {
    await pump(tester, const Size(700, 900));
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(Tab, 'Form'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Timeline'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Attachments'), findsOneWidget);
    // The form is the default (first) tab, so its body renders.
    expect(find.text('FORM_MARKER'), findsOneWidget);
  });

  testWidgets(
      'wide: no main tab bar; form sits beside the Timeline/Attachments side '
      'panel', (tester) async {
    await pump(tester, const Size(1300, 900));
    expect(tester.takeException(), isNull);
    // No "Form" tab — the form owns the main area, not a tab.
    expect(find.widgetWithText(Tab, 'Form'), findsNothing);
    // The side panel exposes Timeline + Attachments as its own sub-tabs.
    expect(find.widgetWithText(Tab, 'Timeline'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Attachments'), findsOneWidget);
    // The form renders beside the panel (not behind a tab)...
    expect(find.text('FORM_MARKER'), findsOneWidget);
    // ...and the side panel's default (Timeline) tab shows its new-doc
    // placeholder, proving the panel is mounted alongside the form.
    expect(find.text('Save the document to see activity'), findsOneWidget);
  });

  testWidgets(
      'breakpoint follows the record pane width, not the window '
      '(constrained detail pane)', (tester) async {
    // Wide WINDOW, but the record is confined to a ~700px detail pane — as in
    // the /list ResponsiveSplit or the medium rail shell.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 700,
                child: RecordWorkspaceChrome(
                  docTypeName: 'Quotation',
                  documentName: null,
                  isDirty: false,
                  isSaving: false,
                  isSubmittable: false,
                  docStatus: 0,
                  onSave: () {},
                  onSubmit: () {},
                  child: const Text('FORM_MARKER'),
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Pane is 700px (< 1024) though the window is 1400px, so the tabbed layout
    // is used — the breakpoint is local, not window-based.
    expect(find.widgetWithText(Tab, 'Form'), findsOneWidget);
    expect(find.text('FORM_MARKER'), findsOneWidget);
  });

  testWidgets(
      'phone width surfaces a header search action; wider widths do not '
      '(the rail carries search there)', (tester) async {
    // Phone (< 600): no navigation rail, so the header exposes global search.
    await pump(tester, const Size(500, 900));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.search), findsOneWidget);

    // Desktop: the shell rail already has a search button, so the record
    // header does not duplicate it.
    await pump(tester, const Size(1300, 900));
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets('layout switches live when the width crosses the breakpoint',
      (tester) async {
    await pump(tester, const Size(1300, 900));
    expect(find.widgetWithText(Tab, 'Form'), findsNothing);

    // Shrink below the side-panel breakpoint; the tabs come back.
    tester.view.physicalSize = const Size(700, 900);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(Tab, 'Form'), findsOneWidget);
    expect(find.text('FORM_MARKER'), findsOneWidget);
  });
}
