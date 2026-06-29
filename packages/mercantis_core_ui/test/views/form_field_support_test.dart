import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// CU2: local inline validation + prerequisite derivation (the pure pieces of
/// the form-UX layer). Mirrors Swift's `localValidationError` / `FormPrerequisites`.
void main() {
  group('localFieldValidationError', () {
    const requiredText =
        FieldDefinition(key: 'name', type: FieldType.data, label: 'Name', required: true);
    const optionalText =
        FieldDefinition(key: 'note', type: FieldType.data, label: 'Note');
    const requiredNumber = FieldDefinition(
        key: 'qty', type: FieldType.float, label: 'Qty', required: true);

    test('required + empty → error', () {
      expect(localFieldValidationError(requiredText, '', isReadOnly: false),
          "'Name' is required.");
      expect(localFieldValidationError(requiredText, null, isReadOnly: false),
          "'Name' is required.");
      expect(localFieldValidationError(requiredText, '   ', isReadOnly: false),
          "'Name' is required.");
    });

    test('required + present → no error', () {
      expect(localFieldValidationError(requiredText, 'Acme', isReadOnly: false),
          isNull);
    });

    test('optional + empty → no error', () {
      expect(
          localFieldValidationError(optionalText, '', isReadOnly: false), isNull);
    });

    test('numeric type rejects a non-numeric string', () {
      expect(localFieldValidationError(requiredNumber, 'abc', isReadOnly: false),
          "'Qty' must be a valid number.");
      expect(
          localFieldValidationError(requiredNumber, 12.5, isReadOnly: false),
          isNull);
      expect(localFieldValidationError(requiredNumber, '12.5', isReadOnly: false),
          isNull);
    });

    test('read-only and layout/formula/table fields never error', () {
      expect(localFieldValidationError(requiredText, '', isReadOnly: true), isNull);
      const heading =
          FieldDefinition(key: 'h', type: FieldType.heading, label: 'H', required: true);
      const formula = FieldDefinition(
          key: 'f', type: FieldType.formula, label: 'F', required: true);
      const table = FieldDefinition(
          key: 'items', type: FieldType.table, label: 'Items', required: true);
      for (final f in [heading, formula, table]) {
        expect(localFieldValidationError(f, null, isReadOnly: false), isNull);
      }
    });
  });

  group('FormPrerequisites', () {
    const invoice = DocType(
      id: 'Sales Invoice',
      name: 'Sales Invoice',
      fields: [
        FieldDefinition(
            key: 'customer',
            type: FieldType.link,
            label: 'Customer',
            required: true,
            linkDocType: 'Customer'),
        FieldDefinition(
            key: 'project',
            type: FieldType.link,
            label: 'Project',
            linkDocType: 'Project'), // optional → not a prerequisite
        FieldDefinition(
            key: 'items',
            type: FieldType.table,
            label: 'Items',
            tableDocType: 'Sales Invoice Item'),
      ],
    );
    const lineItem = DocType(
      id: 'Sales Invoice Item',
      name: 'Sales Invoice Item',
      isChild: true,
      fields: [
        FieldDefinition(
            key: 'item',
            type: FieldType.link,
            label: 'Item',
            required: true,
            linkDocType: 'Item'),
      ],
    );

    DocType? children(String id) => id == 'Sales Invoice Item' ? lineItem : null;

    test('candidateTargets covers required links + required child link columns', () {
      final targets =
          FormPrerequisites.candidateTargets(docType: invoice, childDocType: children);
      expect(targets, ['Customer', 'Item']); // Project (optional) excluded
    });

    test('missing reports only the empty targets, named', () {
      final missing = FormPrerequisites.missing(
        docType: invoice,
        childDocType: children,
        isTargetEmpty: (id) => id == 'Item', // Customer has data, Item doesn't
        displayName: (id) => id,
      );
      expect(missing.map((m) => m.targetDocType), ['Item']);
    });

    test('phrase joins names naturally', () {
      expect(FormPrerequisites.phrase([]), '');
      expect(FormPrerequisites.phrase(['Customer']), 'Customer');
      expect(FormPrerequisites.phrase(['Customer', 'Item']), 'Customer and Item');
      expect(FormPrerequisites.phrase(['Customer', 'Item', 'Currency']),
          'Customer, Item and Currency');
    });
  });
}
