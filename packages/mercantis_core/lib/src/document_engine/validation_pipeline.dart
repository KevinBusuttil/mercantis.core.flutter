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
    Set<String> userRoles,
  ) async {
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
    return ValidationResult(errors);
  }
}
