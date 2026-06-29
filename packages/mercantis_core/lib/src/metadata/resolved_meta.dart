import 'field_definition.dart';
import 'doc_type.dart';

class ResolvedFieldDefinition extends FieldDefinition {
  final bool isCustomField;
  final Map<String, dynamic> propertyOverrides;

  const ResolvedFieldDefinition({
    required super.key,
    required super.type,
    required super.label,
    super.required,
    super.unique,
    super.readOnly,
    super.hidden,
    super.options,
    super.defaultValue,
    super.visibilityExpression,
    super.readOnlyExpression,
    super.formulaExpression,
    super.permissions,
    super.allowOnSubmit,
    super.section,
    super.description,
    super.validationRules,
    super.precision,
    super.linkDocType,
    super.tableDocType,
    super.helpText,
    super.placeholder,
    this.isCustomField = false,
    this.propertyOverrides = const {},
  });

  static ResolvedFieldDefinition fromFieldDefinition(
    FieldDefinition fd, {
    bool isCustomField = false,
    Map<String, dynamic> propertyOverrides = const {},
  }) =>
      ResolvedFieldDefinition(
        key: fd.key,
        type: fd.type,
        label: fd.label,
        required: fd.required,
        unique: fd.unique,
        readOnly: fd.readOnly,
        hidden: fd.hidden,
        options: fd.options,
        defaultValue: fd.defaultValue,
        visibilityExpression: fd.visibilityExpression,
        readOnlyExpression: fd.readOnlyExpression,
        formulaExpression: fd.formulaExpression,
        permissions: fd.permissions,
        allowOnSubmit: fd.allowOnSubmit,
        section: fd.section,
        description: fd.description,
        validationRules: fd.validationRules,
        precision: fd.precision,
        linkDocType: fd.linkDocType,
        tableDocType: fd.tableDocType,
        helpText: fd.helpText,
        placeholder: fd.placeholder,
        isCustomField: isCustomField,
        propertyOverrides: propertyOverrides,
      );
}

class ResolvedMeta {
  final DocType docType;
  final List<ResolvedFieldDefinition> fields;

  const ResolvedMeta({required this.docType, required this.fields});

  ResolvedFieldDefinition? fieldByKey(String key) {
    try {
      return fields.firstWhere((f) => f.key == key);
    } catch (_) {
      return null;
    }
  }

  List<ResolvedFieldDefinition> get visibleFields => fields
      .where((f) =>
          !f.hidden &&
          f.type != FieldType.sectionBreak &&
          f.type != FieldType.columnBreak)
      .toList();

  List<ResolvedFieldDefinition> get tableFields => fields
      .where((f) =>
          f.type == FieldType.table || f.type == FieldType.tableMultiSelect)
      .toList();

  List<ResolvedFieldDefinition> get nonLayoutFields => fields
      .where((f) =>
          f.type != FieldType.sectionBreak &&
          f.type != FieldType.columnBreak &&
          f.type != FieldType.heading)
      .toList();

  List<String> get sections {
    final seen = <String>{};
    final result = <String>[];
    for (final f in fields) {
      final s = f.section ?? '';
      if (!seen.contains(s)) {
        seen.add(s);
        result.add(s);
      }
    }
    return result;
  }

  List<ResolvedFieldDefinition> fieldsInSection(String section) =>
      fields.where((f) => (f.section ?? '') == section).toList();
}
