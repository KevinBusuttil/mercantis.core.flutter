import 'dart:convert';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:test/test.dart';

/// Covers ADR-044: declarative print formats + plain-text/PDF rendering.
void main() {
  ChildRow row(String table, int i, Map<String, dynamic> payload) => ChildRow(
        id: 'c$i',
        parentId: 'INV-1',
        parentDocType: 'Sales Invoice',
        tableName: table,
        rowIndex: i,
        payload: payload,
      );

  Document invoice() => Document(
        id: 'INV-1',
        docType: 'Sales Invoice',
        payload: {'customer': 'Bob', 'grand_total': 150},
        children: {
          'items': [
            row('items', 0, {'item': 'Widget', 'qty': 2}),
            row('items', 1, {'item': 'Gadget', 'qty': 1}),
          ],
        },
      );

  const letterHead = LetterHead(
      id: 'lh', name: 'LH', header: 'ACME Corp', footer: 'Thank you');

  const format = PrintFormat(
    id: 'inv',
    name: 'Invoice',
    docType: 'Sales Invoice',
    letterHeadId: 'lh',
    sections: [
      HeadingSection('Invoice {id}'),
      ParagraphSection('Bill to {customer}.'),
      FieldsSection(keys: ['customer', 'grand_total'], labels: {'grand_total': 'Total'}),
      TableSection(tableKey: 'items', columns: ['item', 'qty']),
      KeyValueSection(label: 'Total', value: '{grand_total}'),
    ],
  );

  group('PrintTemplate', () {
    test('substitute resolves fields, system columns, leaves unknowns literal',
        () {
      final doc = invoice();
      expect(PrintTemplate.substitute('Hi {customer}', doc), 'Hi Bob');
      expect(PrintTemplate.substitute('Ref {id}', doc), 'Ref INV-1');
      expect(PrintTemplate.substitute('? {nope}', doc), '? {nope}');
    });

    test('defaultLabel humanises snake_case and camelCase', () {
      expect(PrintTemplate.defaultLabel('grand_total'), 'Grand total');
      expect(PrintTemplate.defaultLabel('grandTotal'), 'Grand Total');
    });

    test('format renders scalars, whole doubles, bools, lists', () {
      expect(PrintTemplate.format(2.0), '2');
      expect(PrintTemplate.format(1.5), '1.5');
      expect(PrintTemplate.format(true), 'true');
      expect(PrintTemplate.format([1, 2]), '1, 2');
      expect(PrintTemplate.format(null), '');
    });
  });

  group('PlainTextPrintRenderer', () {
    test('renders every section type with the letter head', () async {
      final result = await const PlainTextPrintRenderer().render(
        PrintRenderContext(
            format: format, document: invoice(), letterHead: letterHead),
      );
      final text = utf8.decode(result.bytes);

      expect(result.mimeType, 'text/plain; charset=utf-8');
      expect(result.suggestedFileName, 'inv-INV-1.txt');
      expect(text, contains('ACME Corp')); // letter head
      expect(text, contains('Invoice INV-1')); // heading substitution
      expect(text, contains('Bill to Bob.')); // paragraph
      expect(text, contains('Customer  Bob')); // fields grid
      expect(text, contains('Total')); // overridden field label
      expect(text, contains('Item')); // table header (humanised)
      expect(text, contains('Widget')); // table row
      expect(text, contains('Gadget'));
      expect(text, contains('Total: 150')); // keyValue
      expect(text, contains('Thank you')); // footer
    });

    test('a table section with no rows renders nothing', () async {
      const fmt = PrintFormat(
        id: 'empty',
        name: 'Empty',
        docType: 'Sales Invoice',
        sections: [TableSection(tableKey: 'missing')],
      );
      final result = await const PlainTextPrintRenderer().render(
        PrintRenderContext(
            format: fmt, document: invoice(), letterHead: null),
      );
      expect(utf8.decode(result.bytes).trim(), isEmpty);
    });
  });

  group('PdfPrintRenderer', () {
    test('produces a valid PDF byte stream', () async {
      final result = await const PdfPrintRenderer().render(
        PrintRenderContext(
            format: format, document: invoice(), letterHead: letterHead),
      );
      expect(result.mimeType, 'application/pdf');
      expect(result.suggestedFileName, 'inv-INV-1.pdf');
      expect(result.bytes.length, greaterThan(100));
      expect(String.fromCharCodes(result.bytes.take(5)), '%PDF-');
    });
  });

  group('PrintService', () {
    PrintService service() => PrintService()
      ..registerLetterHead(letterHead)
      ..registerFormat(format);

    test('renders a registered format', () async {
      final result = await service().render(
        formatId: 'inv',
        document: invoice(),
        kind: PrintOutputKind.plainText,
      );
      expect(utf8.decode(result.bytes), contains('ACME Corp'));
    });

    test('formatsForDocType + registeredFormatIds', () {
      final svc = service();
      expect(svc.registeredFormatIds(), ['inv']);
      expect(svc.formatsForDocType('Sales Invoice').single.id, 'inv');
      expect(svc.formatsForDocType('Other'), isEmpty);
    });

    test('unknown format throws', () {
      expect(
        () => service().render(
            formatId: 'nope',
            document: invoice(),
            kind: PrintOutputKind.plainText),
        throwsA(isA<PrintServiceException>()),
      );
    });

    test('docType mismatch throws', () {
      final doc = Document(id: 'X', docType: 'Other');
      expect(
        () => service().render(
            formatId: 'inv', document: doc, kind: PrintOutputKind.plainText),
        throwsA(isA<PrintServiceException>()),
      );
    });

    test('no renderer for the requested kind throws', () {
      final svc = PrintService(renderers: const [PlainTextPrintRenderer()])
        ..registerFormat(format);
      expect(
        () => svc.render(
            formatId: 'inv', document: invoice(), kind: PrintOutputKind.pdf),
        throwsA(isA<PrintServiceException>()),
      );
    });
  });

  test('PrintFormat JSON round-trips all section kinds', () {
    final restored = PrintFormat.fromJson(format.toJson());
    expect(restored.id, 'inv');
    expect(restored.letterHeadId, 'lh');
    expect(restored.sections, hasLength(5));
    expect(restored.sections[0], isA<HeadingSection>());
    expect((restored.sections[0] as HeadingSection).text, 'Invoice {id}');
    expect(restored.sections[2], isA<FieldsSection>());
    expect((restored.sections[2] as FieldsSection).labels['grand_total'], 'Total');
    expect((restored.sections[3] as TableSection).tableKey, 'items');
  });
}
