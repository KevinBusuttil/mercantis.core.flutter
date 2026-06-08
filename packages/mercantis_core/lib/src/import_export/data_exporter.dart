import 'dart:convert';

import '../document_engine/document.dart';
import '../document_engine/document_engine.dart';
import '../document_engine/list_filter.dart';
import '../metadata/doc_type.dart';
import '../metadata/metadata_registry.dart';
import 'csv_codec.dart';
import 'import_export_format.dart';

/// Bulk export (ADR-046). Walks every document of a DocType (or a
/// predicate-narrowed subset) and serialises to CSV or JSON. Row-level access
/// is intentionally bypassed — bulk export is an admin operation.
class DataExporter {
  final DocumentEngine _engine;
  final MetadataRegistry _registry;

  DataExporter(this._engine, this._registry);

  /// Export documents of [docType] in [format]. Optional [predicates] narrow
  /// the export to a subset; when null, every document is included.
  Future<String> export({
    required String docType,
    required ImportExportFormat format,
    List<ListFilter>? predicates,
  }) async {
    final meta = await _registry.get(docType);
    if (meta == null) {
      throw ImportExportException.docTypeNotRegistered(docType);
    }
    // No userRoles → no row-access filtering (full export). `list` sorts on
    // payload fields only, so order by the document id column in Dart for a
    // deterministic export.
    final documents = await _engine.list(docType, predicates: predicates);
    documents.sort((a, b) => a.id.compareTo(b.id));
    switch (format) {
      case ImportExportFormat.csv:
        return _exportCsv(documents, meta);
      case ImportExportFormat.json:
        // `list` doesn't hydrate children; re-fetch so the JSON envelope
        // round-trips child tables.
        final full = <Document>[
          for (final d in documents) (await _engine.fetch(docType, d.id)) ?? d,
        ];
        return _exportJson(docType, full);
    }
  }

  // CSV — flat rows. Header order: id, company, docstatus, then each declared
  // field key in declaration order. Children aren't exported in CSV (they
  // don't fit a flat row); callers needing them should use JSON.
  String _exportCsv(List<Document> documents, DocType meta) {
    final fieldKeys = meta.fields.map((f) => f.key).toList();
    final headers = ['id', 'company', 'docstatus', ...fieldKeys];

    final rows = documents.map((doc) {
      final row = <String, String>{
        'id': doc.id,
        'company': doc.company ?? '',
        'docstatus': doc.docStatus.toString(),
      };
      for (final key in fieldKeys) {
        row[key] = _stringify(doc.payload[key]);
      }
      return row;
    }).toList();

    return CsvCodec.encode(headers: headers, rows: rows);
  }

  String _stringify(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'true' : 'false';
    if (value is DateTime) return value.toIso8601String();
    if (value is List) {
      // Best-effort flatten for CSV; the JSON path keeps full structure.
      return value.map(_stringify).join(';');
    }
    return value.toString();
  }

  // JSON envelope: { "docType": "...", "documents": [ {...} ] }. Children are
  // serialised as `tableName -> [rowPayload, ...]` so they round-trip.
  String _exportJson(String docType, List<Document> documents) {
    final envelope = {
      'docType': docType,
      'documents': documents.map(_documentToJson).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  Map<String, dynamic> _documentToJson(Document doc) => {
        'id': doc.id,
        'docType': doc.docType,
        'company': doc.company,
        'docStatus': doc.docStatus,
        'amendedFrom': doc.amendedFrom,
        'createdAt': doc.createdAt.toIso8601String(),
        'modifiedAt': doc.modifiedAt?.toIso8601String(),
        'payload': doc.payload,
        'children': {
          for (final entry in doc.children.entries)
            entry.key: entry.value.map((c) => c.payload).toList(),
        },
      };
}
