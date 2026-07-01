import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Increment 4 of the responsive-forms work:
///   * the prerequisites nudge is compact and dismissible;
///   * the command bar no longer repeats the document title (the AppBar owns
///     it), so drafts get a clean action row.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('PrerequisiteBanner', () {
    const missing = [
      MissingPrerequisite(targetDocType: 'Customer', displayName: 'Customer'),
      MissingPrerequisite(targetDocType: 'Currency', displayName: 'Currency'),
    ];

    testWidgets('shows a dismissible nudge when prerequisites are missing',
        (tester) async {
      await tester.pumpWidget(wrap(const PrerequisiteBanner(
        docTypeName: 'Quotation',
        missing: missing,
      )));
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('renders nothing when no prerequisites are missing',
        (tester) async {
      await tester.pumpWidget(wrap(const PrerequisiteBanner(
        docTypeName: 'Quotation',
        missing: [],
      )));
      expect(find.byIcon(Icons.lightbulb_outline), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('dismisses when the close button is tapped', (tester) async {
      await tester.pumpWidget(wrap(const PrerequisiteBanner(
        docTypeName: 'Quotation',
        missing: missing,
      )));
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.byIcon(Icons.lightbulb_outline), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });

  group('CommandBarView', () {
    testWidgets('no longer renders the document title (AppBar owns it)',
        (tester) async {
      await tester.pumpWidget(wrap(CommandBarView(
        docTypeName: 'Quotation',
        documentName: 'QTN-001',
        isDirty: true,
        isSaving: false,
        isSubmittable: false,
        docStatus: 0,
        onSave: () {},
        onSubmit: () {},
      )));
      // The title text is gone from the command bar...
      expect(find.text('QTN-001'), findsNothing);
      expect(find.text('New Quotation'), findsNothing);
      // ...but the dirty-draft Save action still renders.
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('keeps the status chip for a submitted document',
        (tester) async {
      await tester.pumpWidget(wrap(CommandBarView(
        docTypeName: 'Quotation',
        documentName: 'QTN-001',
        isDirty: false,
        isSaving: false,
        isSubmittable: false,
        docStatus: 1,
        onSave: () {},
        onSubmit: () {},
        onCancel: () {},
      )));
      expect(find.text('Submitted'), findsOneWidget);
      // Still no duplicated title.
      expect(find.text('QTN-001'), findsNothing);
    });
  });
}
