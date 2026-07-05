import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Phase 4d-3: the lifecycle command bar moved to a pinned bottom bar with a
/// phone overflow for host-contributed actions. These lock the *gating* — which
/// buttons appear for each docStatus / isDirty / isSubmittable — since that is
/// posting-critical and must survive the relocation unchanged, plus the new
/// overflow behaviour.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int docStatus,
    bool isDirty = false,
    bool isSaving = false,
    bool isSubmittable = false,
    String? documentName = 'DOC-1',
    String? error,
    List<Widget> extraActions = const [],
    VoidCallback? onCancel,
    VoidCallback? onAmend,
    VoidCallback? onDelete,
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CommandBarView(
          docTypeName: 'Quotation',
          documentName: documentName,
          isDirty: isDirty,
          isSaving: isSaving,
          isSubmittable: isSubmittable,
          docStatus: docStatus,
          onSave: () {},
          onSubmit: () {},
          onCancel: onCancel,
          onAmend: onAmend,
          onDelete: onDelete,
          error: error,
          extraActions: extraActions,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('draft + dirty shows Save only', (tester) async {
    await pump(tester, docStatus: 0, isDirty: true, isSubmittable: true);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
  });

  testWidgets('saved, clean, submittable draft shows Submit only',
      (tester) async {
    await pump(tester,
        docStatus: 0,
        isDirty: false,
        isSubmittable: true,
        documentName: 'DOC-1');
    expect(find.widgetWithText(FilledButton, 'Submit'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('new (unsaved) submittable draft shows neither action',
      (tester) async {
    await pump(tester,
        docStatus: 0,
        isDirty: false,
        isSubmittable: true,
        documentName: null);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('non-submittable clean draft shows no Submit', (tester) async {
    await pump(tester,
        docStatus: 0, isDirty: false, isSubmittable: false);
    expect(find.text('Submit'), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('submitted shows a Submitted chip and a Cancel action',
      (tester) async {
    await pump(tester, docStatus: 1, onCancel: () {});
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
  });

  testWidgets('cancelled shows a Cancelled chip and an Amend action',
      (tester) async {
    await pump(tester, docStatus: 2, onAmend: () {});
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Amend'), findsOneWidget);
  });

  testWidgets('saved draft offers a Delete action when onDelete is wired',
      (tester) async {
    await pump(tester,
        docStatus: 0, documentName: 'DOC-1', onDelete: () {});
    expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
  });

  testWidgets('new (unsaved) draft offers no Delete', (tester) async {
    await pump(tester,
        docStatus: 0, documentName: null, onDelete: () {});
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('submitted document offers no Delete (not a draft)',
      (tester) async {
    await pump(tester,
        docStatus: 1, documentName: 'DOC-1', onDelete: () {}, onCancel: () {});
    expect(find.text('Delete'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
  });

  testWidgets('saving shows a spinner instead of the action buttons',
      (tester) async {
    await pump(tester, docStatus: 0, isDirty: true, isSaving: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('an error renders the error banner message', (tester) async {
    await pump(tester, docStatus: 0, isDirty: true, error: 'Save failed');
    expect(find.text('Save failed'), findsOneWidget);
  });

  testWidgets('wide pane renders extra actions inline', (tester) async {
    await pump(
      tester,
      docStatus: 0,
      isDirty: true,
      size: const Size(1000, 800),
      extraActions: [
        OutlinedButton(onPressed: () {}, child: const Text('Convert')),
      ],
    );
    expect(find.text('Convert'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('phone collapses extra actions into a More overflow sheet',
      (tester) async {
    await pump(
      tester,
      docStatus: 0,
      isDirty: true,
      size: const Size(500, 900),
      extraActions: [
        OutlinedButton(onPressed: () {}, child: const Text('Convert')),
      ],
    );
    // Extra action is not inline; the primary Save stays visible.
    expect(find.text('Convert'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);

    // Opening the overflow surfaces the extra action.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Convert'), findsOneWidget);
  });
}
