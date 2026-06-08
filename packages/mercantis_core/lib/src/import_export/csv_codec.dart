import 'import_export_format.dart';

/// Minimal CSV reader/writer (ADR-046). RFC-4180-ish: `,` separator, `"`
/// quoting, `""` for embedded quotes, CRLF or LF line endings on read, LF on
/// write. Deliberately dependency-free — the surface we need (encode/decode
/// `Map<String, String>` rows) is small enough to keep the dependency graph
/// clean.
class CsvCodec {
  const CsvCodec._();

  /// Render a header + rows as RFC-4180 CSV (LF line endings). [headers]
  /// defines column order; missing cells render empty.
  static String encode({
    required List<String> headers,
    required List<Map<String, String>> rows,
  }) {
    final out = StringBuffer();
    out.write(headers.map(escape).join(','));
    out.write('\n');
    for (final row in rows) {
      out.write(headers.map((h) => escape(row[h] ?? '')).join(','));
      out.write('\n');
    }
    return out.toString();
  }

  /// Escape one CSV cell — quoted when it contains a separator, quote, CR, or
  /// LF.
  static String escape(String raw) {
    if (raw.isEmpty) return '';
    final needsQuote = raw.contains(',') ||
        raw.contains('"') ||
        raw.contains('\n') ||
        raw.contains('\r');
    if (!needsQuote) return raw;
    return '"${raw.replaceAll('"', '""')}"';
  }

  /// Parse [text] as RFC-4180 CSV. The first row is treated as the header;
  /// each subsequent row becomes a `header -> cell` map. Throws
  /// [ImportExportException] on quote/row mismatches.
  static DecodedTable decode(String text) {
    final rawRows = _parseRows(text);
    if (rawRows.isEmpty) return const DecodedTable(headers: [], rows: []);
    final header = rawRows.first;
    final dataRows = <Map<String, String>>[];
    for (final cells in rawRows.skip(1)) {
      final row = <String, String>{};
      for (var i = 0; i < header.length && i < cells.length; i++) {
        row[header[i]] = cells[i];
      }
      dataRows.add(row);
    }
    return DecodedTable(headers: header, rows: dataRows);
  }

  static List<List<String>> _parseRows(String text) {
    final rows = <List<String>>[];
    var currentRow = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    var line = 1;

    // split('') yields UTF-16 code units; surrogate halves reassemble verbatim
    // into cells since we only branch on ASCII delimiters.
    final chars = text.split('');
    final n = chars.length;
    var i = 0;
    while (i < n) {
      final ch = chars[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < n && chars[i + 1] == '"') {
            cell.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        if (ch == '\n') line++;
        cell.write(ch);
        i++;
        continue;
      }
      switch (ch) {
        case '"':
          if (cell.isNotEmpty) {
            throw ImportExportException.malformedCsv(
                line, 'quote inside unquoted cell');
          }
          inQuotes = true;
          break;
        case ',':
          currentRow.add(cell.toString());
          cell.clear();
          break;
        case '\r':
          break; // swallow; the LF closes the row
        case '\n':
          currentRow.add(cell.toString());
          rows.add(currentRow);
          currentRow = [];
          cell.clear();
          line++;
          break;
        default:
          cell.write(ch);
      }
      i++;
    }

    if (inQuotes) {
      throw ImportExportException.malformedCsv(line, 'unterminated quoted cell');
    }
    if (cell.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(cell.toString());
      rows.add(currentRow);
    }
    return rows;
  }
}

/// The parsed result of [CsvCodec.decode].
class DecodedTable {
  final List<String> headers;
  final List<Map<String, String>> rows;

  const DecodedTable({required this.headers, required this.rows});
}
