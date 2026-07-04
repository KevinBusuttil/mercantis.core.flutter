import 'dart:convert';
import 'dart:typed_data';

import '../document_engine/document.dart';
import 'print_format.dart';
import 'print_renderer.dart';

/// HTML renderer (ADR-044). Produces a single self-contained HTML document —
/// inline CSS, no external assets — suitable for in-app preview, browser
/// print-to-PDF, or emailing. Section semantics mirror
/// [PlainTextPrintRenderer] so the two stay in lock-step (the plain-text
/// renderer remains the deterministic oracle); this one adds structure + style.
///
/// All document-derived text is HTML-escaped, so field values that contain
/// `<`, `>`, `&` or `"` render literally rather than injecting markup.
class HtmlPrintRenderer implements PrintRenderer {
  const HtmlPrintRenderer();

  @override
  PrintOutputKind get outputKind => PrintOutputKind.html;

  @override
  Future<PrintRenderResult> render(PrintRenderContext context) async {
    final document = context.document;
    final body = StringBuffer();

    final letterHead = context.letterHead;
    if (letterHead != null) {
      body.writeln(
        '<header class="letterhead">'
        '${_esc(PrintTemplate.substitute(letterHead.header, document))}'
        '</header>',
      );
    }

    body.writeln('<main>');
    for (final section in context.format.sections) {
      final html = _renderSection(section, document);
      if (html.isNotEmpty) body.writeln(html);
    }
    body.writeln('</main>');

    final footer = letterHead?.footer;
    if (footer != null) {
      body.writeln(
        '<footer class="letterfoot">'
        '${_esc(PrintTemplate.substitute(footer, document))}'
        '</footer>',
      );
    }

    final title = _esc('${context.format.name} · ${document.id}');
    final html = '<!DOCTYPE html>\n'
        '<html lang="en">\n'
        '<head>\n'
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        '<title>$title</title>\n'
        '<style>\n$_css</style>\n'
        '</head>\n'
        '<body>\n$body</body>\n'
        '</html>\n';

    final safeId = document.id.replaceAll('/', '-');
    return PrintRenderResult(
      bytes: Uint8List.fromList(utf8.encode(html)),
      mimeType: 'text/html; charset=utf-8',
      suggestedFileName: '${context.format.id}-$safeId.html',
    );
  }

  String _renderSection(PrintSection section, Document document) {
    switch (section) {
      case HeadingSection(:final text):
        return '<h1>${_esc(PrintTemplate.substitute(text, document))}</h1>';

      case ParagraphSection(:final text):
        return '<p>${_esc(PrintTemplate.substitute(text, document))}</p>';

      case FieldsSection(:final keys, :final labels):
        if (keys.isEmpty) return '';
        final rows = StringBuffer();
        for (final key in keys) {
          final label = labels[key] ?? PrintTemplate.defaultLabel(key);
          final value = PrintTemplate.lookupString(key, document);
          rows.writeln(
              '<tr><th>${_esc(label)}</th><td>${_esc(value)}</td></tr>');
        }
        return '<table class="fields"><tbody>\n$rows</tbody></table>';

      case TableSection(:final tableKey, :final columns, :final labels):
        return _renderTable(tableKey, columns, labels, document);

      case KeyValueSection(:final label, :final value):
        final l = _esc(PrintTemplate.substitute(label, document));
        final v = _esc(PrintTemplate.substitute(value, document));
        return '<div class="kv">'
            '<span class="kv-label">$l</span>'
            '<span class="kv-value">$v</span>'
            '</div>';
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

    // Resolve columns — explicit if given, else the union of keys seen, in the
    // order first encountered (identical to the plain-text renderer).
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

    final head = StringBuffer();
    for (final c in columns) {
      head.write('<th>${_esc(labels[c] ?? PrintTemplate.defaultLabel(c))}</th>');
    }

    final bodyRows = StringBuffer();
    for (final row in rows) {
      bodyRows.write('<tr>');
      for (final c in columns) {
        bodyRows.write('<td>${_esc(PrintTemplate.format(row.payload[c]))}</td>');
      }
      bodyRows.writeln('</tr>');
    }

    return '<table class="grid">'
        '<thead><tr>$head</tr></thead>\n'
        '<tbody>\n$bodyRows</tbody>'
        '</table>';
  }

  /// Minimal HTML escaping. `&` is replaced first so the entities introduced by
  /// the later replacements aren't double-escaped.
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static const _css = '''
* { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  color: #1a1a1a;
  margin: 0;
  padding: 32px;
  font-size: 13px;
  line-height: 1.5;
}
main, .letterhead, .letterfoot { max-width: 720px; margin-left: auto; margin-right: auto; }
.letterhead {
  border-bottom: 2px solid #222;
  padding-bottom: 12px;
  margin-bottom: 20px;
  color: #555;
  font-size: 12px;
  white-space: pre-wrap;
}
.letterfoot {
  border-top: 1px solid #ccc;
  padding-top: 12px;
  margin-top: 24px;
  color: #555;
  font-size: 12px;
  white-space: pre-wrap;
}
h1 { font-size: 20px; margin: 0 0 16px; }
p { margin: 0 0 12px; }
table { border-collapse: collapse; width: 100%; margin: 0 0 16px; }
table.fields th {
  text-align: left;
  color: #555;
  font-weight: 600;
  width: 40%;
  padding: 4px 8px 4px 0;
  vertical-align: top;
}
table.fields td { padding: 4px 0; }
table.grid th, table.grid td {
  border: 1px solid #ddd;
  padding: 6px 8px;
  text-align: left;
}
table.grid thead th { background: #f5f5f5; }
.kv {
  display: flex;
  justify-content: space-between;
  padding: 4px 0;
  border-top: 1px solid #eee;
}
.kv-label { color: #555; }
.kv-value { font-weight: 600; }
@media print { body { padding: 0; } }
''';
}
