import 'dart:convert';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:test/test.dart';

/// HU2 — persisting print formats as data: the store, its repository port, and
/// the structural validator.
void main() {
  const invoiceFormat = PrintFormat(
    id: 'inv',
    name: 'Invoice',
    docType: 'Sales Invoice',
    sections: [
      HeadingSection('Invoice {id}'),
      FieldsSection(keys: ['customer']),
    ],
  );

  const quoteFormat = PrintFormat(
    id: 'quo',
    name: 'Quotation',
    docType: 'Quotation',
    sections: [HeadingSection('Quote {id}')],
  );

  PrintFormatStore store() => PrintFormatStore(InMemoryPrintFormatRepository());

  group('PrintFormatStore', () {
    test('saves and reloads formats, filtering by DocType', () async {
      final s = store();
      await s.saveFormat(invoiceFormat);
      await s.saveFormat(quoteFormat);

      final all = await s.formats();
      expect(all.map((f) => f.id).toSet(), {'inv', 'quo'});

      final forInvoice = await s.formatsForDocType('Sales Invoice');
      expect(forInvoice.single.id, 'inv');
      expect(await s.formatsForDocType('Nope'), isEmpty);
    });

    test('save upserts by id (no duplicates)', () async {
      final s = store();
      await s.saveFormat(invoiceFormat);
      await s.saveFormat(const PrintFormat(
        id: 'inv',
        name: 'Invoice v2',
        docType: 'Sales Invoice',
        sections: [HeadingSection('Invoice {id}')],
      ));

      final all = await s.formats();
      expect(all, hasLength(1));
      expect(all.single.name, 'Invoice v2');
    });

    test('deleteFormat removes it', () async {
      final s = store();
      await s.saveFormat(invoiceFormat);
      await s.deleteFormat('inv');
      expect(await s.formats(), isEmpty);
    });

    test('persisted format survives a JSON round-trip', () async {
      // A fresh store over the same repo contents deserializes identically.
      final repo = InMemoryPrintFormatRepository();
      await PrintFormatStore(repo).saveFormat(invoiceFormat);
      final reloaded = (await PrintFormatStore(repo).formats()).single;
      expect(reloaded.toJson(), invoiceFormat.toJson());
    });

    test('saveFormat rejects an invalid format', () async {
      final s = store();
      expect(
        () => s.saveFormat(const PrintFormat(
            id: '', name: '', docType: '', sections: [])),
        throwsA(isA<PrintFormatValidationException>()),
      );
      expect(await s.formats(), isEmpty); // nothing persisted
    });

    test('letter heads save, reload and delete', () async {
      final s = store();
      const lh = LetterHead(id: 'lh', name: 'LH', header: 'ACME');
      await s.saveLetterHead(lh);
      expect((await s.letterHeads()).single.header, 'ACME');
      await s.deleteLetterHead('lh');
      expect(await s.letterHeads(), isEmpty);
    });

    test('hydrate loads formats + letter heads into a PrintService', () async {
      final s = store();
      await s.saveLetterHead(
          const LetterHead(id: 'lh', name: 'LH', header: 'ACME Corp'));
      await s.saveFormat(const PrintFormat(
        id: 'inv',
        name: 'Invoice',
        docType: 'Sales Invoice',
        letterHeadId: 'lh',
        sections: [HeadingSection('Invoice {id}')],
      ));

      final service = PrintService();
      await s.hydrate(service);

      expect(service.registeredFormatIds(), ['inv']);
      final result = await service.render(
        formatId: 'inv',
        document: Document(id: 'INV-9', docType: 'Sales Invoice'),
        kind: PrintOutputKind.plainText,
      );
      final text = utf8.decode(result.bytes);
      expect(text, contains('ACME Corp')); // letter head hydrated
      expect(text, contains('Invoice INV-9')); // format hydrated + rendered
    });
  });

  group('PrintFormatValidator', () {
    test('a well-formed format has no errors', () {
      expect(PrintFormatValidator.validate(invoiceFormat), isEmpty);
    });

    test('flags missing id/name/docType and no sections', () {
      final errors = PrintFormatValidator.validate(
          const PrintFormat(id: '', name: '', docType: '', sections: []));
      expect(errors, hasLength(4));
      expect(errors.join(' '), contains('id is required'));
      expect(errors.join(' '), contains('name is required'));
      expect(errors.join(' '), contains('target a DocType'));
      expect(errors.join(' '), contains('at least one section'));
    });

    test('flags per-section structural problems', () {
      final errors = PrintFormatValidator.validate(const PrintFormat(
        id: 'x',
        name: 'X',
        docType: 'Sales Invoice',
        sections: [
          HeadingSection('   '), // blank heading
          FieldsSection(keys: []), // no fields
          TableSection(tableKey: ''), // no table key
          KeyValueSection(label: '', value: '10'), // no label
        ],
      ));
      expect(errors, hasLength(4));
      expect(errors.join(' '), contains('Heading section 1 is empty'));
      expect(errors.join(' '), contains('Fields section 2 needs'));
      expect(errors.join(' '), contains('Table section 3 needs'));
      expect(errors.join(' '), contains('Key/value section 4 needs'));
    });
  });
}
