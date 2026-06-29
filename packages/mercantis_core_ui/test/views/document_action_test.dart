import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The host-action extension point that lets a module (e.g. document
/// conversion) contribute command-bar actions without the generic form
/// depending on it.
void main() {
  Document doc(String type, {int status = 1}) =>
      Document(id: 'X1', docType: type, docStatus: status);
  DocType type(String id) => DocType(id: id, name: id);

  group('DocumentActionRegistry', () {
    DocumentAction action(String id) => DocumentAction(
          id: id,
          label: id,
          invoke: (_, __, ___) async {},
        );

    test('flattens every builder in registration order', () {
      final reg = DocumentActionRegistry()
        ..register((d, t) => t.id == 'Quotation' ? [action('a')] : const [])
        ..register((d, t) => [action('b')]);

      final ids = reg
          .actionsFor(doc('Quotation'), type('Quotation'))
          .map((a) => a.id)
          .toList();
      expect(ids, ['a', 'b']);
    });

    test('a builder can gate on document status', () {
      final reg = DocumentActionRegistry()
        ..register((d, t) => d.docStatus == 1 ? [action('convert')] : const []);

      expect(reg.actionsFor(doc('Sales Order', status: 1), type('Sales Order')),
          hasLength(1));
      expect(reg.actionsFor(doc('Sales Order', status: 0), type('Sales Order')),
          isEmpty);
    });

    test('no builders → no actions', () {
      expect(DocumentActionRegistry().actionsFor(doc('Lead'), type('Lead')),
          isEmpty);
    });
  });

  group('CommandBarView.extraActions', () {
    testWidgets('renders contributed actions after the built-ins', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CommandBarView(
            docTypeName: 'Sales Order',
            documentName: 'SO-1',
            isDirty: false,
            isSaving: false,
            isSubmittable: true,
            docStatus: 1,
            onSave: () {},
            onSubmit: () {},
            extraActions: const [Text('Create Sales Invoice')],
          ),
        ),
      ));

      expect(find.text('Create Sales Invoice'), findsOneWidget);
    });

    testWidgets('hides actions while saving (busy spinner takes over)',
        (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CommandBarView(
            docTypeName: 'Sales Order',
            documentName: 'SO-1',
            isDirty: false,
            isSaving: true,
            isSubmittable: true,
            docStatus: 1,
            onSave: () {},
            onSubmit: () {},
            extraActions: const [Text('Create Sales Invoice')],
          ),
        ),
      ));

      expect(find.text('Create Sales Invoice'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
