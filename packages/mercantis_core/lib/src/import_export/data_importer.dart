import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../document_engine/document.dart';
import '../document_engine/document_engine.dart';
import '../metadata/field_definition.dart';
import '../metadata/metadata_registry.dart';
import 'csv_codec.dart';
import 'import_export_format.dart';

/// Bulk import (ADR-046). Reads CSV/JSON and routes every row through
/// `DocumentEngine.save(...)` so the validation pipeline, naming, and audit log
/// run identically to interactive saves. Per-row failures are recorded in the
/// returned [ImportReport] rather than aborting the whole batch.
class DataImporter {
  final DocumentEngine _engine;
  final MetadataRegistry _registry;

  DataImporter(this._engine, this._registry);

  /// Import [data] into [docType]. [userRoles] are applied to each underlying
  /// save (bulk import defaults to a privileged role).
  Future<ImportReport> import({
    required String docType,
    required String data,
    required ImportExportFormat format,
    ImportConflictPolicy conflictPolicy = ImportConflictPolicy.overwrite,
    Set<String> userRoles = const {'System Manager'},
  }) async {
    final meta = await _registry.get(docType);
    if (meta == null) {
      throw ImportExportException.docTypeNotRegistered(docType);
    }
    switch (format) {
      case ImportExportFormat.csv:
        return _importCsv(docType, data, conflictPolicy, userRoles, meta.fields);
      case ImportExportFormat.json:
        return _importJson(docType, data, conflictPolicy, userRoles);
    }
  }

  // CSV path

  Future<ImportReport> _importCsv(
    String docType,
    String data,
    ImportConflictPolicy policy,
    Set<String> roles,
    List<FieldDefinition> fields,
  ) async {
    final table = CsvCodec.decode(data);
    final fieldByKey = {for (final f in fields) f.key: f};

    final outcomes = <ImportRowOutcome>[];
    for (var index = 0; index < table.rows.length; index++) {
      try {
        final doc =
            _documentFromCsvRow(docType, table.rows[index], fieldByKey);
        outcomes.add(await _saveOrSkip(doc, policy, roles, index));
      } catch (e) {
        outcomes.add(ImportRowOutcome.failed(index, e.toString()));
      }
    }
    return ImportReport(
        docType: docType, rowsRead: table.rows.length, outcomes: outcomes);
  }

  Document _documentFromCsvRow(
    String docType,
    Map<String, String> row,
    Map<String, FieldDefinition> fieldByKey,
  ) {
    final payload = <String, dynamic>{};
    row.forEach((key, raw) {
      if (key == 'id' || key == 'company' || key == 'docstatus') return;
      final def = fieldByKey[key];
      if (def == null) return; // unknown column → ignored
      payload[key] = _coerce(raw, def.type);
    });

    final company = (row['company'] ?? '').isEmpty ? null : row['company'];
    return Document(
      id: row['id'] ?? '',
      docType: docType,
      company: company,
      docStatus: int.tryParse(row['docstatus'] ?? '') ?? 0,
      payload: payload,
    );
  }

  /// Coerce a raw CSV string into a native payload value per the field's type.
  /// Empty cells become null. Types CSV can't carry losslessly (tables,
  /// formulas) are dropped so the rest of the row still imports.
  dynamic _coerce(String raw, FieldType type) {
    if (raw.isEmpty) return null;
    switch (type) {
      case FieldType.integer:
        final v = int.tryParse(raw);
        if (v == null) {
          throw ImportExportException.malformedCsv(
              0, "expected integer, got '$raw'");
        }
        return v;
      case FieldType.float:
      case FieldType.currency:
      case FieldType.percent:
      case FieldType.rating:
        final v = double.tryParse(raw);
        if (v == null) {
          throw ImportExportException.malformedCsv(
              0, "expected number, got '$raw'");
        }
        return v;
      case FieldType.check:
        switch (raw.toLowerCase()) {
          case 'true':
          case 'yes':
          case '1':
            return true;
          case 'false':
          case 'no':
          case '0':
            return false;
          default:
            throw ImportExportException.malformedCsv(
                0, "expected boolean, got '$raw'");
        }
      case FieldType.date:
      case FieldType.dateTime:
        final d = DateTime.tryParse(raw);
        if (d == null) {
          throw ImportExportException.malformedCsv(
              0, "expected ISO 8601 date, got '$raw'");
        }
        return d.toIso8601String();
      case FieldType.table:
      case FieldType.tableMultiSelect:
      case FieldType.formula:
        return null; // can't round-trip through a flat CSV cell
      default:
        return raw; // data/text/select/link/time/etc.
    }
  }

  // JSON path

  Future<ImportReport> _importJson(
    String docType,
    String data,
    ImportConflictPolicy policy,
    Set<String> roles,
  ) async {
    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('expected a top-level object');
      }
      envelope = decoded;
    } catch (e) {
      throw ImportExportException.malformedJson(e.toString());
    }

    final documents = (envelope['documents'] as List<dynamic>?) ?? const [];
    final outcomes = <ImportRowOutcome>[];
    for (var index = 0; index < documents.length; index++) {
      try {
        final doc = _documentFromJson(
            Map<String, dynamic>.from(documents[index] as Map), docType);
        outcomes.add(await _saveOrSkip(doc, policy, roles, index));
      } catch (e) {
        outcomes.add(ImportRowOutcome.failed(index, e.toString()));
      }
    }
    return ImportReport(
        docType: docType, rowsRead: documents.length, outcomes: outcomes);
  }

  Document _documentFromJson(Map<String, dynamic> map, String docType) {
    final id = map['id'] as String? ?? '';
    final children = <String, List<ChildRow>>{};
    final rawChildren = map['children'] as Map<String, dynamic>? ?? const {};
    rawChildren.forEach((table, rows) {
      final list = (rows as List<dynamic>);
      children[table] = [
        for (var i = 0; i < list.length; i++)
          ChildRow(
            id: const Uuid().v4(),
            parentId: id,
            parentDocType: docType,
            tableName: table,
            rowIndex: i,
            payload: Map<String, dynamic>.from(list[i] as Map),
          ),
      ];
    });

    return Document(
      id: id,
      docType: docType, // retarget so callers can re-home an export
      company: map['company'] as String?,
      docStatus: (map['docStatus'] as int?) ?? 0,
      amendedFrom: map['amendedFrom'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? ''),
      modifiedAt: map['modifiedAt'] == null
          ? null
          : DateTime.tryParse(map['modifiedAt'] as String),
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? const {}),
      children: children,
    );
  }

  // Save dispatch

  Future<ImportRowOutcome> _saveOrSkip(
    Document document,
    ImportConflictPolicy policy,
    Set<String> roles,
    int index,
  ) async {
    final existing = document.id.isNotEmpty
        ? await _engine.fetch(document.docType, document.id)
        : null;

    if (existing != null) {
      switch (policy) {
        case ImportConflictPolicy.skipExisting:
          return ImportRowOutcome.skipped(existing.id, 'id already exists');
        case ImportConflictPolicy.fail:
          return ImportRowOutcome.failed(
              index, "id '${existing.id}' already exists");
        case ImportConflictPolicy.overwrite:
          // Carry the existing envelope forward (timestamps, sync) so the
          // optimistic-concurrency check passes; overlay imported content.
          final merged = existing.copyWith(
            company: document.company,
            docStatus: document.docStatus,
            payload: document.payload,
            children:
                document.children.isEmpty ? existing.children : document.children,
          );
          final saved = await _engine.save(merged, roles);
          return ImportRowOutcome.updated(saved.id);
      }
    }
    final saved = await _engine.save(document, roles);
    return ImportRowOutcome.inserted(saved.id);
  }
}
