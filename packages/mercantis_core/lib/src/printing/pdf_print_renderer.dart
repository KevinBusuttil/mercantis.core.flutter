import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../document_engine/document.dart';
import 'print_format.dart';
import 'print_renderer.dart';

/// PDF renderer (ADR-044) backed by the pure-Dart `pdf` package, so it works on
/// every platform without a Flutter dependency. Uses the built-in Helvetica
/// core font (no font assets required) and `MultiPage` for automatic
/// pagination of long documents.
class PdfPrintRenderer implements PrintRenderer {
  final PdfPageFormat pageFormat;

  const PdfPrintRenderer({this.pageFormat = PdfPageFormat.letter});

  @override
  PrintOutputKind get outputKind => PrintOutputKind.pdf;

  @override
  Future<PrintRenderResult> render(PrintRenderContext context) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => _buildBody(context),
      ),
    );
    final bytes = await doc.save();
    final safeId = context.document.id.replaceAll('/', '-');
    return PrintRenderResult(
      bytes: bytes,
      mimeType: 'application/pdf',
      suggestedFileName: '${context.format.id}-$safeId.pdf',
    );
  }

  List<pw.Widget> _buildBody(PrintRenderContext context) {
    final document = context.document;
    final widgets = <pw.Widget>[];

    final letterHead = context.letterHead;
    if (letterHead != null) {
      widgets.add(pw.Text(
        PrintTemplate.substitute(letterHead.header, document),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ));
      widgets.add(pw.Divider());
    }

    for (final section in context.format.sections) {
      final widget = _renderSection(section, document);
      if (widget != null) {
        widgets.add(widget);
        widgets.add(pw.SizedBox(height: 8));
      }
    }

    final footer = letterHead?.footer;
    if (footer != null) {
      widgets.add(pw.Divider());
      widgets.add(pw.Text(PrintTemplate.substitute(footer, document)));
    }
    return widgets;
  }

  pw.Widget? _renderSection(PrintSection section, Document document) {
    switch (section) {
      case HeadingSection(:final text):
        return pw.Text(
          PrintTemplate.substitute(text, document),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        );

      case ParagraphSection(:final text):
        return pw.Text(PrintTemplate.substitute(text, document));

      case FieldsSection(:final keys, :final labels):
        if (keys.isEmpty) return null;
        return pw.Table(
          columnWidths: const {
            0: pw.IntrinsicColumnWidth(),
            1: pw.FlexColumnWidth(),
          },
          children: [
            for (final key in keys)
              pw.TableRow(children: [
                _cell(labels[key] ?? PrintTemplate.defaultLabel(key),
                    bold: true),
                _cell(PrintTemplate.lookupString(key, document)),
              ]),
          ],
        );

      case TableSection(:final tableKey, :final columns, :final labels):
        return _renderTable(tableKey, columns, labels, document);

      case KeyValueSection(:final label, :final value):
        final l = PrintTemplate.substitute(label, document);
        final v = PrintTemplate.substitute(value, document);
        return pw.Text('$l: $v');
    }
  }

  pw.Widget? _renderTable(
    String tableKey,
    List<String> explicitColumns,
    Map<String, String> labels,
    Document document,
  ) {
    final rows = document.children[tableKey] ?? const [];
    if (rows.isEmpty) return null;

    final List<String> columns;
    if (explicitColumns.isNotEmpty) {
      columns = explicitColumns;
    } else {
      final seen = <String>{};
      final inOrder = <String>[];
      for (final row in rows) {
        for (final k in row.payload.keys) {
          if (seen.add(k)) inOrder.add(k);
        }
      }
      columns = inOrder;
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      children: [
        pw.TableRow(children: [
          for (final c in columns)
            _cell(labels[c] ?? PrintTemplate.defaultLabel(c), bold: true),
        ]),
        for (final row in rows)
          pw.TableRow(children: [
            for (final c in columns)
              _cell(PrintTemplate.format(row.payload[c])),
          ]),
      ],
    );
  }

  pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
        ),
      );
}
