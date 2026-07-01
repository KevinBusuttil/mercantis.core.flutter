enum FieldType {
  data,
  text,
  smallText,
  longText,
  integer,
  float,
  currency,
  percent,
  check,
  date,
  dateTime,
  time,
  select,
  link,
  dynamicLink,
  table,
  tableMultiSelect,
  attach,
  attachImage,
  heading,
  sectionBreak,
  columnBreak,
  formula,
  code,
  signature,
  color,
  duration,
  autocomplete,
  password,
  rating,
  barcode,
  geolocation,
}

enum FieldOperation { read, write }

class FieldPermission {
  final List<String> readRoles;
  final List<String> writeRoles;

  const FieldPermission({this.readRoles = const [], this.writeRoles = const []});

  factory FieldPermission.fromJson(Map<String, dynamic> json) => FieldPermission(
        readRoles: (json['readRoles'] as List<dynamic>?)?.cast<String>() ?? const [],
        writeRoles: (json['writeRoles'] as List<dynamic>?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'readRoles': readRoles,
        'writeRoles': writeRoles,
      };
}

class ValidationRule {
  final String expression;
  final String message;

  const ValidationRule({required this.expression, required this.message});

  factory ValidationRule.fromJson(Map<String, dynamic> json) => ValidationRule(
        expression: json['expression'] as String,
        message: json['message'] as String,
      );

  Map<String, dynamic> toJson() => {'expression': expression, 'message': message};
}

class FieldDefinition {
  final String key;
  final FieldType type;
  final String label;
  final bool required;
  final bool unique;
  final bool readOnly;
  final bool hidden;
  final String? options;
  final String? defaultValue;
  final String? visibilityExpression;
  final String? readOnlyExpression;
  final String? formulaExpression;

  /// Declarative "fetch from linked document" source (C8 / ERPNext `fetch_from`).
  /// Form: `"<linkFieldKey>.<sourceFieldKey>"` — on save the engine reads the
  /// document referenced by [linkFieldKey] and copies its `sourceFieldKey` value
  /// into this field (e.g. a line item's `item_name` from `item.item_name`).
  /// Null means the field isn't auto-fetched.
  final String? fetchFrom;

  final FieldPermission? permissions;
  final bool allowOnSubmit;
  final String? section;
  final String? description;
  final List<ValidationRule> validationRules;
  final int? precision;
  final String? linkDocType;
  final String? tableDocType;

  /// Short helper sentence shown beneath the field in the form to explain what
  /// it's for (e.g. "Used on invoices and the customer portal"). Port of Swift
  /// `FieldDefinition.helpText`.
  final String? helpText;

  /// Example/ghost text shown inside an empty editor (e.g. "name@business.com").
  /// Ignored by controls that have no placeholder slot. Port of Swift
  /// `FieldDefinition.placeholder`.
  final String? placeholder;

  const FieldDefinition({
    required this.key,
    required this.type,
    required this.label,
    this.required = false,
    this.unique = false,
    this.readOnly = false,
    this.hidden = false,
    this.options,
    this.defaultValue,
    this.visibilityExpression,
    this.readOnlyExpression,
    this.formulaExpression,
    this.fetchFrom,
    this.permissions,
    this.allowOnSubmit = false,
    this.section,
    this.description,
    this.validationRules = const [],
    this.precision,
    this.linkDocType,
    this.tableDocType,
    this.helpText,
    this.placeholder,
  });

  factory FieldDefinition.fromJson(Map<String, dynamic> json) => FieldDefinition(
        key: json['key'] as String,
        type: FieldType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => FieldType.data,
        ),
        label: json['label'] as String,
        required: (json['required'] as bool?) ?? false,
        unique: (json['unique'] as bool?) ?? false,
        readOnly: (json['readOnly'] as bool?) ?? false,
        hidden: (json['hidden'] as bool?) ?? false,
        options: json['options'] as String?,
        defaultValue: json['defaultValue'] as String?,
        visibilityExpression: json['visibilityExpression'] as String?,
        readOnlyExpression: json['readOnlyExpression'] as String?,
        formulaExpression: json['formulaExpression'] as String?,
        fetchFrom: json['fetchFrom'] as String?,
        permissions: json['permissions'] != null
            ? FieldPermission.fromJson(json['permissions'] as Map<String, dynamic>)
            : null,
        allowOnSubmit: (json['allowOnSubmit'] as bool?) ?? false,
        section: json['section'] as String?,
        description: json['description'] as String?,
        validationRules: (json['validationRules'] as List<dynamic>?)
                ?.map((r) => ValidationRule.fromJson(r as Map<String, dynamic>))
                .toList() ??
            const [],
        precision: json['precision'] as int?,
        linkDocType: json['linkDocType'] as String?,
        tableDocType: json['tableDocType'] as String?,
        helpText: json['helpText'] as String?,
        placeholder: json['placeholder'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type.name,
        'label': label,
        'required': required,
        'unique': unique,
        'readOnly': readOnly,
        'hidden': hidden,
        if (options != null) 'options': options,
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (visibilityExpression != null) 'visibilityExpression': visibilityExpression,
        if (readOnlyExpression != null) 'readOnlyExpression': readOnlyExpression,
        if (formulaExpression != null) 'formulaExpression': formulaExpression,
        if (fetchFrom != null) 'fetchFrom': fetchFrom,
        if (permissions != null) 'permissions': permissions!.toJson(),
        'allowOnSubmit': allowOnSubmit,
        if (section != null) 'section': section,
        if (description != null) 'description': description,
        'validationRules': validationRules.map((r) => r.toJson()).toList(),
        if (precision != null) 'precision': precision,
        if (linkDocType != null) 'linkDocType': linkDocType,
        if (tableDocType != null) 'tableDocType': tableDocType,
        if (helpText != null) 'helpText': helpText,
        if (placeholder != null) 'placeholder': placeholder,
      };

  FieldDefinition copyWith({
    String? key, FieldType? type, String? label, bool? required, bool? unique,
    bool? readOnly, bool? hidden, String? options, String? defaultValue,
    String? visibilityExpression, String? readOnlyExpression, String? formulaExpression,
    String? fetchFrom,
    FieldPermission? permissions, bool? allowOnSubmit, String? section,
    String? description, List<ValidationRule>? validationRules, int? precision,
    String? linkDocType, String? tableDocType, String? helpText, String? placeholder,
  }) =>
      FieldDefinition(
        key: key ?? this.key,
        type: type ?? this.type,
        label: label ?? this.label,
        required: required ?? this.required,
        unique: unique ?? this.unique,
        readOnly: readOnly ?? this.readOnly,
        hidden: hidden ?? this.hidden,
        options: options ?? this.options,
        defaultValue: defaultValue ?? this.defaultValue,
        visibilityExpression: visibilityExpression ?? this.visibilityExpression,
        readOnlyExpression: readOnlyExpression ?? this.readOnlyExpression,
        formulaExpression: formulaExpression ?? this.formulaExpression,
        fetchFrom: fetchFrom ?? this.fetchFrom,
        permissions: permissions ?? this.permissions,
        allowOnSubmit: allowOnSubmit ?? this.allowOnSubmit,
        section: section ?? this.section,
        description: description ?? this.description,
        validationRules: validationRules ?? this.validationRules,
        precision: precision ?? this.precision,
        linkDocType: linkDocType ?? this.linkDocType,
        tableDocType: tableDocType ?? this.tableDocType,
        helpText: helpText ?? this.helpText,
        placeholder: placeholder ?? this.placeholder,
      );
}
