import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Business-language presentation changes words only: the command bar keeps
/// exactly the same lifecycle gating whatever the labels say.
void main() {
  const owner = LifecycleLabels(
    submit: 'Post invoice',
    submitted: 'Posted',
    cancel: 'Reverse',
    amend: 'Correct',
  );

  Future<void> pump(WidgetTester tester, int docStatus,
      {bool isDirty = false, LifecycleLabels labels = owner}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CommandBarView(
          docTypeName: 'Sales Invoice',
          documentName: 'SINV-1',
          isDirty: isDirty,
          isSaving: false,
          isSubmittable: true,
          docStatus: docStatus,
          onSave: () {},
          onSubmit: () {},
          onCancel: () {},
          onAmend: () {},
          labels: labels,
        ),
      ),
    ));
  }

  testWidgets('draft shows the owner submit label, not Submit',
      (tester) async {
    await pump(tester, 0);
    expect(find.widgetWithText(FilledButton, 'Post invoice'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
  });

  testWidgets('dirty draft still shows Save only — gating unchanged',
      (tester) async {
    await pump(tester, 0, isDirty: true);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.text('Post invoice'), findsNothing);
  });

  testWidgets('submitted shows the Posted chip and Reverse', (tester) async {
    await pump(tester, 1);
    expect(find.text('Posted'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reverse'), findsOneWidget);
  });

  testWidgets('cancelled offers Correct (amend)', (tester) async {
    await pump(tester, 2);
    expect(find.widgetWithText(OutlinedButton, 'Correct'), findsOneWidget);
  });

  test('engine labels are the defaults', () {
    expect(LifecycleLabels.engine.submit, 'Submit');
    expect(LifecycleLabels.engine.statusLabel(1), 'Submitted');
    expect(owner.statusLabel(1), 'Posted');
    expect(owner.statusLabel(0), 'Draft');
  });

  testWidgets('empty list pane shows guidance, not a bare "No documents"',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DocumentListPane(
          title: 'Invoices',
          rows: [],
          emptyTitle: 'No invoices yet',
          emptyMessage: 'Create one, or convert an accepted quote.',
        ),
      ),
    ));
    expect(find.text('No invoices yet'), findsOneWidget);
    expect(find.text('Create one, or convert an accepted quote.'),
        findsOneWidget);
  });
}
