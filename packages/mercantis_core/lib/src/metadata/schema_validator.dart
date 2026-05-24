import 'doc_type.dart';
import 'field_definition.dart';

class SchemaError {
  final String field;
  final String message;
  const SchemaError({required this.field, required this.message});

  @override
  String toString() => 'SchemaError($field): $message';
}

class SchemaValidator {
  List<SchemaError> validate(DocType docType) {
    final errors = <SchemaError>[];
    final keys = <String>{};

    if (docType.id.isEmpty) {
      errors.add(const SchemaError(field: 'id', message: 'DocType id must not be empty'));
    }
    if (docType.name.isEmpty) {
      errors.add(const SchemaError(field: 'name', message: 'DocType name must not be empty'));
    }

    for (final field in docType.fields) {
      if (field.key.isEmpty) {
        errors.add(const SchemaError(field: '', message: 'Field key must not be empty'));
        continue;
      }
      if (keys.contains(field.key)) {
        errors.add(SchemaError(field: field.key, message: 'Duplicate field key: ${field.key}'));
      }
      keys.add(field.key);

      if (field.type == FieldType.link &&
          (field.linkDocType == null || field.linkDocType!.isEmpty)) {
        errors.add(SchemaError(
          field: field.key,
          message: 'Link field ${field.key} must specify linkDocType',
        ));
      }
      if (field.type == FieldType.table &&
          (field.tableDocType == null || field.tableDocType!.isEmpty)) {
        errors.add(SchemaError(
          field: field.key,
          message: 'Table field ${field.key} must specify tableDocType',
        ));
      }
    }

    return errors;
  }

  bool isValid(DocType docType) => validate(docType).isEmpty;
}
