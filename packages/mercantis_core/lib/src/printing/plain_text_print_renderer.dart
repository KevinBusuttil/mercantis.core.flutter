import 'dart:convert';
import 'dart:typed_data';

import '../document_engine/document.dart';
import 'print_format.dart';
import 'print_renderer.dart';

/// Plain-text renderer (ADR-044). Always available, cross-platform,
/// deterministic — useful for scripting, CLI export, and as the test oracle for
/// higher-fidelity renderers.
class PlainTextPrintRenderer implements PrintRenderer {
  const PlainTextPrintRenderer();

  @override
  PrintOutputKind get outputKind => PrintOutputKind.plainText;

  @override
  Future<PrintRenderResult> render(PrintRenderContext context) async {
    final document = context.document;
    final lines = <String>[];

    final letterHead = context.letterHead;
    if (letterHead != null) {
      lines.add(PrintTemplate.substitute(letterHead.header, document));
      lines.add('-' * 60);
    }

    for (final section in context.format.sections) {
      final block = _renderSection(section, document);
      if (block.isNotEmpty) {
        if (lines.isNotEmpty) lines.add('');
        lines.add(block);
      }
    }

    final footer = letterHead?.footer;
    if (footer != null) {
      lines.add('');
      lines.add('-' * 60);
      lines.add(PrintTemplate.substitute(footer, document));
    }

    final body = '${lines.join('\n')}\n';
    final safeId = document.id.replaceAll('/', '-');
    return PrintRenderResult(
      bytes: Uint8List.fromList(utf8.encode(body)),
      mimeType: 'text/plain; charset=utf-8',
      suggestedFileName: '${context.format.id}-$safeId.txt',
    );
  }

  String _renderSection(PrintSection section, Document document) {
    switch (section) {
      case HeadingSection(:final text):
        final resolved = PrintTemplate.substitute(text, document);
        return '$resolved\n${'=' * (resolved.length < 4 ? 4 : resolved.length)}';

      case ParagraphSection(:final text):
        return PrintTemplate.substitute(text, document);

      case FieldsSection(:final keys, :final labels):
        final labelWidth = keys
            .map((k) => (labels[k] ?? PrintTemplate.defaultLabel(k)).length)
            .fold<int>(0, (a, b) => a > b ? a : b);
        return keys.map((key) {
          final label = labels[key] ?? PrintTemplate.defaultLabel(key);
          final value = PrintTemplate.lookupString(key, document);
          return '${label.padRight(labelWidth)}  $value';
        }).join('\n');

      case TableSection(:final tableKey, :final columns, :final labels):
        return _renderTable(tableKey, columns, labels, document);

      case KeyValueSection(:final label, :final value):
        final l = PrintTemplate.substitute(label, document);
        final v = PrintTemplate.substitute(value, document);
        return '$l: $v';
    }
  }

  String _renderTable(
    String tableKey,
    List<String> explicitColumns,
    Map<String, String> labels,
    Document document,
  ) {
    final rows = document.children[tableKey] ?? const [];
    if (rows.isEmpty) return '';

    // Resolve columns — explicit if given, else the union of keys seen.
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

    String headerFor(String col) => labels[col] ?? PrintTemplate.defaultLabel(col);

    final widths = <String, int>{for (final c in columns) c: headerFor(c).length};
    for (final row in rows) {
      for (final col in columns) {
        final v = PrintTemplate.format(row.payload[col]);
        if (v.length > widths[col]!) widths[col] = v.length;
      }
    }

    final header =
        columns.map((c) => headerFor(c).padRight(widths[c]!)).join('  ');
    final separator = columns.map((c) => '-' * widths[c]!).join('  ');
    final body = <String>[header, separator];
    for (final row in rows) {
      body.add(columns
          .map((c) => PrintTemplate.format(row.payload[c]).padRight(widths[c]!))
          .join('  '));
    }
    return body.join('\n');
  }
}
