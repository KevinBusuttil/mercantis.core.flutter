import 'package:flutter/material.dart';
import 'package:mercantis_core/mercantis_core.dart';

/// Cheap, local, DB-free validation used for immediate inline feedback on a
/// form field: required-but-empty and obvious type mismatches. The full
/// [ValidationPipeline] still runs on Save for link integrity, uniqueness, and
/// cross-field rules. Port of Swift `GenericFormView.localValidationError`.
///
/// Returns a human message, or null when the field is currently valid.
String? localFieldValidationError(
  FieldDefinition field,
  Object? value, {
  required bool isReadOnly,
}) {
  // Layout separators, formulas, and child tables aren't directly editable.
  switch (field.type) {
    case FieldType.heading:
    case FieldType.sectionBreak:
    case FieldType.columnBreak:
    case FieldType.formula:
    case FieldType.table:
    case FieldType.tableMultiSelect:
      return null;
    default:
      break;
  }
  if (isReadOnly || field.readOnly) return null;

  final empty = _isValueEmpty(value);
  if (field.required && empty) return "'${field.label}' is required.";
  if (empty) return null; // optional + empty is fine

  switch (field.type) {
    case FieldType.integer:
    case FieldType.float:
    case FieldType.currency:
    case FieldType.percent:
      if (!_isNumeric(value)) return "'${field.label}' must be a valid number.";
      break;
    default:
      break;
  }
  return null;
}

bool _isValueEmpty(Object? value) {
  if (value == null) return true;
  if (value is String) return value.trim().isEmpty;
  if (value is Iterable) return value.isEmpty;
  return false;
}

bool _isNumeric(Object? value) {
  if (value is num) return true;
  if (value is String) return double.tryParse(value.trim()) != null;
  return false;
}

/// A master-data record type that must exist before a document can reference it
/// — e.g. a Sales Invoice needs at least one Customer and one Item.
class MissingPrerequisite {
  const MissingPrerequisite({required this.targetDocType, required this.displayName});
  final String targetDocType;
  final String displayName;
}

/// Works out which master records a DocType depends on that don't exist yet, so
/// the form can nudge "add a Customer and an Item first" instead of letting a
/// new user fill a whole document and hit a wall of required-field errors on
/// Save. Looks at the DocType's required link fields plus the required link
/// columns of its child tables. Port of Swift `FormPrerequisites`.
class FormPrerequisites {
  const FormPrerequisites._();

  static bool _isLink(FieldDefinition f) =>
      f.type == FieldType.link || f.type == FieldType.dynamicLink;

  /// Ordered, de-duped list of the master DocTypes this DocType requires — its
  /// required link fields plus the required link columns of its child tables.
  /// Emptiness/name resolution (which may be async) is layered on top by the
  /// caller; see [missing] for the synchronous, fully-resolved variant.
  static List<String> candidateTargets({
    required DocType docType,
    required DocType? Function(String docTypeId) childDocType,
  }) {
    final out = <String>[];
    final seen = <String>{};

    void consider(String? target) {
      if (target == null || target.isEmpty || !seen.add(target)) return;
      out.add(target);
    }

    for (final field in docType.fields) {
      if (field.required && _isLink(field)) consider(field.linkDocType);
    }
    // Required link columns inside child tables (e.g. a line's `item`): you
    // can't add a single row until that master has at least one record.
    for (final field in docType.fields) {
      if (field.type != FieldType.table) continue;
      final child = field.tableDocType == null
          ? null
          : childDocType(field.tableDocType!);
      if (child == null) continue;
      for (final column in child.fields) {
        if (column.required && _isLink(column)) consider(column.linkDocType);
      }
    }
    return out;
  }

  static List<MissingPrerequisite> missing({
    required DocType docType,
    required DocType? Function(String docTypeId) childDocType,
    required bool Function(String docTypeId) isTargetEmpty,
    required String? Function(String docTypeId) displayName,
  }) {
    final targets = candidateTargets(docType: docType, childDocType: childDocType);
    return [
      for (final t in targets)
        if (isTargetEmpty(t))
          MissingPrerequisite(targetDocType: t, displayName: displayName(t) ?? t),
    ];
  }

  /// "Customer", "Customer and Item", "Customer, Item and Currency".
  static String phrase(List<String> names) {
    switch (names.length) {
      case 0:
        return '';
      case 1:
        return names[0];
      case 2:
        return '${names[0]} and ${names[1]}';
      default:
        return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    }
  }
}

/// Inline error (if any) plus the field's help text, shown beneath a form
/// control. Renders nothing when both are absent. Port of Swift
/// `GenericFormView.fieldFootnotes`.
class FieldFootnote extends StatelessWidget {
  const FieldFootnote({super.key, this.helpText, this.error});

  final String? helpText;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final help = helpText?.trim();
    final err = error?.trim();
    final hasHelp = help != null && help.isNotEmpty;
    final hasError = err != null && err.isNotEmpty;
    if (!hasHelp && !hasError) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasError)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    size: 14, color: theme.colorScheme.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    err,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          if (hasHelp)
            Padding(
              padding: EdgeInsets.only(top: hasError ? 2 : 0),
              child: Text(
                help,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// Non-blocking banner shown above a create/edit form when the document depends
/// on master data that doesn't exist yet. Purely informational — it points the
/// user at what to set up first rather than blocking the form. Port of Swift
/// `PrerequisiteBanner`.
class PrerequisiteBanner extends StatelessWidget {
  const PrerequisiteBanner({
    super.key,
    required this.docTypeName,
    required this.missing,
  });

  final String docTypeName;
  final List<MissingPrerequisite> missing;

  @override
  Widget build(BuildContext context) {
    if (missing.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final names = FormPrerequisites.phrase([for (final m in missing) m.displayName]);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Set up your basics first',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Before you can save a $docTypeName, add at least one $names. '
                  'You can do that from the matching workspace in the sidebar.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
