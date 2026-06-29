import 'package:sqflite_common/sqflite.dart';
import '../metadata/doc_type.dart';
import '../metadata/field_definition.dart';
import 'document.dart';

enum DocumentOperation { read, write, create, delete, submit, amend }

class ValidationError {
  final String stage;
  final String? fieldKey;
  final String message;

  const ValidationError({
    required this.stage,
    this.fieldKey,
    required this.message,
  });

  @override
  String toString() => fieldKey != null
      ? '[$stage] $fieldKey: $message'
      : '[$stage] $message';
}

class ValidationResult {
  final List<ValidationError> errors;

  const ValidationResult(this.errors);

  bool get isValid => errors.isEmpty;

  factory ValidationResult.valid() => const ValidationResult([]);
}

abstract class ValidationStage {
  Future<List<ValidationError>> validate(
    Document document,
    DocType docType,
    Database db,
    DocumentOperation operation,
    Set<String> userRoles,
  );
}

class RequiredFieldStage extends ValidationStage {
  @override
  Future<List<ValidationError>> validate(
    Document doc,
    DocType docType,
    Database db,
    DocumentOperation operation,
    Set<String> userRoles,
  ) async {
    if (operation == DocumentOperation.delete) return [];
    final errors = <ValidationError>[];
    for (final field in docType.fields) {
      if (!field.required) continue;
      if (field.type == FieldType.sectionBreak ||
          field.type == FieldType.columnBreak ||
          field.type == FieldType.heading) continue;
      final value = doc.payload[field.key];
      final isEmpty = value == null ||
          value == '' ||
          value == false ||
          value == 0 && field.type == FieldType.check;
      if (isEmpty) {
        errors.add(ValidationError(
          stage: 'RequiredField',
          fieldKey: field.key,
          message: '${field.label} is required',
        ));
      }
    }
    return errors;
  }
}

class UniqueConstraintStage extends ValidationStage {
  @override
  Future<List<ValidationError>> validate(
    Document doc,
    DocType docType,
    Database db,
    DocumentOperation operation,
    Set<String> userRoles,
  ) async {
    if (operation == DocumentOperation.delete) return [];
    final errors = <ValidationError>[];
    for (final field in docType.fields) {
      if (!field.unique) continue;
      final value = doc.payload[field.key];
      if (value == null) continue;
      final rows = await db.rawQuery(
        "SELECT id FROM documents WHERE doctype = ? AND json_extract(payload, '\$.${field.key}') = ? AND id != ?",
        [docType.id, value, doc.id.isEmpty ? '' : doc.id],
      );
      if (rows.isNotEmpty) {
        errors.add(ValidationError(
          stage: 'UniqueConstraint',
          fieldKey: field.key,
          message: '${field.label} must be unique. "$value" already exists.',
        ));
      }
    }
    return errors;
  }
}

class LinkValidationStage extends ValidationStage {
  @override
  Future<List<ValidationError>> validate(
    Document doc,
    DocType docType,
    Database db,
    DocumentOperation operation,
    Set<String> userRoles,
  ) async {
    if (operation == DocumentOperation.delete) return [];
    final errors = <ValidationError>[];
    for (final field in docType.fields) {
      if (field.type != FieldType.link) continue;
      final value = doc.payload[field.key];
      if (value == null || value == '') continue;
      final linkedDocType = field.linkDocType;
      if (linkedDocType == null) continue;
      final rows = await db.query(
        'documents',
        where: 'id = ? AND doctype = ?',
        whereArgs: [value, linkedDocType],
      );
      if (rows.isEmpty) {
        errors.add(ValidationError(
          stage: 'LinkValidation',
          fieldKey: field.key,
          message: '${field.label}: "$value" does not exist in $linkedDocType',
        ));
      }
    }
    return errors;
  }
}

class ValidationPipeline {
  final List<ValidationStage> stages;

  ValidationPipeline()
      : stages = [
          RequiredFieldStage(),
          UniqueConstraintStage(),
          LinkValidationStage(),
        ];

  Future<ValidationResult> run(
    Document document,
    DocType docType,
    Database db,
    DocumentOperation operation,
    Set<String> userRoles, {
    Future<DocType?> Function(String docTypeId)? childDocTypeProvider,
  }) async {
    final errors = <ValidationError>[];
    for (final stage in stages) {
      final stageErrors = await stage.validate(
        document,
        docType,
        db,
        operation,
        userRoles,
      );
      errors.addAll(stageErrors);
    }
    // Recursive child-row validation (C3 / P0.5): when a child-DocType resolver
    // is supplied, validate every table row against its declared child DocType.
    if (childDocTypeProvider != null && operation != DocumentOperation.delete) {
      errors.addAll(await _validateChildren(
          document, docType, db, operation, userRoles, childDocTypeProvider));
    }
    return ValidationResult(errors);
  }

  /// Runs the field-level stages (required, link) against each row of every
  /// `.table` field whose child DocType resolves, plus table-scoped uniqueness.
  /// Errors are re-attributed with a `tableKey[rowIndex].field` path and a
  /// "Row N:" prefix. Tables with no resolvable child DocType are skipped, so
  /// legacy/untyped tables behave exactly as before. Port of Swift
  /// `ChildTableValidationStage`.
  Future<List<ValidationError>> _validateChildren(
    Document doc,
    DocType docType,
    Database db,
    DocumentOperation operation,
    Set<String> userRoles,
    Future<DocType?> Function(String docTypeId) childDocTypeProvider,
  ) async {
    final out = <ValidationError>[];
    // Unique/store-scoped stages are parent-only; child uniqueness is enforced
    // table-locally below.
    final rowStages = <ValidationStage>[
      RequiredFieldStage(),
      LinkValidationStage(),
    ];

    for (final field in docType.fields) {
      if (field.type != FieldType.table &&
          field.type != FieldType.tableMultiSelect) {
        continue;
      }
      final childName = field.tableDocType;
      if (childName == null || childName.isEmpty) continue;
      final childType = await childDocTypeProvider(childName);
      if (childType == null) continue;

      final rows = doc.children[field.key] ?? const <ChildRow>[];
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        final childDoc = Document(
          id: row.id,
          docType: childType.id,
          payload: Map<String, dynamic>.from(row.payload),
        );
        for (final stage in rowStages) {
          final stageErrors =
              await stage.validate(childDoc, childType, db, operation, userRoles);
          for (final e in stageErrors) {
            out.add(ValidationError(
              stage: 'ChildTableValidation',
              fieldKey: e.fieldKey == null
                  ? '${field.key}[$index]'
                  : '${field.key}[$index].${e.fieldKey}',
              message: 'Row ${index + 1}: ${e.message}',
            ));
          }
        }
      }
      out.addAll(_duplicateRowErrors(rows, childType, field.key));
    }
    return out;
  }

  /// Enforces a child DocType's unique indexes across the rows of one table
  /// (duplicate-row detection) — e.g. no duplicate item line when the child
  /// DocType marks `item` unique.
  List<ValidationError> _duplicateRowErrors(
    List<ChildRow> rows,
    DocType childType,
    String tableKey,
  ) {
    final out = <ValidationError>[];
    for (final index in childType.indexes) {
      if (!index.isUnique) continue;
      final seen = <Object?, int>{}; // value -> first row index
      for (var i = 0; i < rows.length; i++) {
        final value = rows[i].payload[index.fieldKey];
        if (value == null) continue;
        final first = seen[value];
        if (first != null) {
          out.add(ValidationError(
            stage: 'ChildTableValidation',
            fieldKey: '$tableKey[$i].${index.fieldKey}',
            message:
                "Row ${i + 1}: duplicates '${index.fieldKey}' from row ${first + 1}.",
          ));
        } else {
          seen[value] = i;
        }
      }
    }
    return out;
  }
}
