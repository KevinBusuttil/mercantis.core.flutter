import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../providers/core_providers.dart';
import '../theme/tokens/spacing.dart';

/// End-user "Customize fields" surface.
///
/// Lists existing custom fields for [docTypeName] and lets the user add,
/// edit and remove them with a small-business-friendly UX:
///   - Label is the only free-text input; the persistent field key is
///     derived from it (e.g. "VAT Number" → `vat_number`) and locked on
///     edit so existing record payloads keep matching.
///   - A "Place after" picker offers every existing field (base or
///     custom) plus "End of form".
///   - Type is restricted to the common set (text / long text / number /
///     money / yes-no / date / choice list). Type can't be changed on
///     edit (would orphan stored values).
///
/// Designed to be shown via `showModalBottomSheet` on phones and as a
/// `Dialog` on tablet / desktop — see [showCustomizeFieldsDialog].
class CustomizeFieldsSheet extends ConsumerStatefulWidget {
  const CustomizeFieldsSheet({
    super.key,
    required this.docTypeName,
  });

  final String docTypeName;

  @override
  ConsumerState<CustomizeFieldsSheet> createState() =>
      _CustomizeFieldsSheetState();
}

class _CustomizeFieldsSheetState extends ConsumerState<CustomizeFieldsSheet> {
  _EditorState? _editor;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final dbAsync = ref.watch(mercantisDatabaseProvider);
    final metaAsync = ref.watch(resolvedMetaProvider(widget.docTypeName));

    return SafeArea(
      child: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            const Divider(height: 1),
            Flexible(
              child: dbAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(MercantisSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(MercantisSpacing.xl),
                  child: Center(child: Text('Error: $e')),
                ),
                data: (database) => metaAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(MercantisSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(MercantisSpacing.xl),
                    child: Center(child: Text('Error: $e')),
                  ),
                  data: (meta) {
                    if (meta == null) {
                      return _empty(
                          'DocType "${widget.docTypeName}" is not registered.');
                    }
                    return _body(context, database, meta);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MercantisSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              Icons.tune,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: MercantisSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customize ${widget.docTypeName}',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  'Add your own fields without touching the original record.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    MercantisDatabase database,
    ResolvedMeta meta,
  ) {
    final allFieldEntries = [
      for (final f in meta.fields)
        _BaseFieldEntry(key: f.key, label: f.label),
    ];

    return FutureBuilder<List<CustomField>>(
      future: CustomField.forDocType(database.db, widget.docTypeName),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(MercantisSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(MercantisSpacing.xl),
            child: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        final customFields = snapshot.data ?? const <CustomField>[];

        if (_editor != null) {
          return _editorBody(
            context,
            database: database,
            customFields: customFields,
            allFieldEntries: allFieldEntries,
          );
        }
        return _listBody(context, customFields, database);
      },
    );
  }

  Widget _empty(String message) => Padding(
        padding: const EdgeInsets.all(MercantisSpacing.xl),
        child: Center(child: Text(message)),
      );

  // -- List of existing custom fields -------------------------------------

  Widget _listBody(
    BuildContext context,
    List<CustomField> customFields,
    MercantisDatabase database,
  ) {
    if (customFields.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: MercantisSpacing.xxl,
          horizontal: MercantisSpacing.xl,
        ),
        child: Column(
          children: [
            const Icon(Icons.dashboard_customize_outlined,
                size: 48, color: Colors.grey),
            const SizedBox(height: MercantisSpacing.md),
            const Text(
              'No custom fields yet',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: MercantisSpacing.xs),
            Text(
              'Tap "Add Field" to add the first one. '
              'It will appear on every ${widget.docTypeName} record.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: MercantisSpacing.lg),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Field'),
              onPressed: () => _openEditorForAdd(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: MercantisSpacing.md),
              Text(_errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MercantisSpacing.lg,
            vertical: MercantisSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                '${customFields.length} custom field'
                '${customFields.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Field'),
                onPressed: () => _openEditorForAdd(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: MercantisSpacing.sm),
            itemCount: customFields.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final field = customFields[index];
              return _CustomFieldTile(
                field: field,
                onEdit: () => _openEditorForEdit(field),
                onRemove: () => _confirmRemove(context, database, field),
              );
            },
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    MercantisDatabase database,
    CustomField field,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${field.fieldDefinition.label}"?'),
        content: const Text(
          'Records that already have a value for this field will keep it, '
          'but the field will no longer appear on the form.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await CustomField.delete(database.db, field.id);
      _onCustomFieldsChanged();
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
  }

  // -- Editor (add / edit) -------------------------------------------------

  void _openEditorForAdd() {
    setState(() {
      _errorMessage = null;
      _editor = _EditorState(
        mode: _EditorMode.add,
        draft: _Draft.empty(),
      );
    });
  }

  void _openEditorForEdit(CustomField field) {
    setState(() {
      _errorMessage = null;
      _editor = _EditorState(
        mode: _EditorMode.edit,
        editingId: field.id,
        draft: _Draft.fromField(field),
      );
    });
  }

  Widget _editorBody(
    BuildContext context, {
    required MercantisDatabase database,
    required List<CustomField> customFields,
    required List<_BaseFieldEntry> allFieldEntries,
  }) {
    final draft = _editor!.draft;
    final isEdit = _editor!.mode == _EditorMode.edit;

    final reservedKeys = <String>{
      for (final entry in allFieldEntries) entry.key,
      for (final f in customFields) f.fieldDefinition.key,
    };
    // When editing, the field's own key is allowed.
    final currentKey = isEdit
        ? customFields
            .firstWhere(
              (f) => f.id == _editor!.editingId,
              orElse: () => CustomField(
                id: '',
                docTypeId: widget.docTypeName,
                fieldDefinition: const FieldDefinition(
                    key: '', type: FieldType.data, label: ''),
              ),
            )
            .fieldDefinition
            .key
        : null;

    // "Place after" candidates: base fields + other custom fields.
    final positionCandidates = <_BaseFieldEntry>[
      for (final entry in allFieldEntries)
        if (entry.key != currentKey) entry,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(MercantisSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEdit ? 'Edit field' : 'New field',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: MercantisSpacing.md),

          // Label
          TextFormField(
            initialValue: draft.label,
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'e.g. VAT Number',
            ),
            onChanged: (v) => setState(() => _editor =
                _editor!.copyWith(draft: draft.copyWith(label: v))),
          ),
          const SizedBox(height: MercantisSpacing.sm),

          // Derived key (read-only)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MercantisSpacing.xs),
            child: Row(
              children: [
                const Icon(Icons.code, size: 14, color: Colors.grey),
                const SizedBox(width: MercantisSpacing.xs),
                Text(
                  'Field key: ',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  isEdit
                      ? (currentKey ?? '—')
                      : (_deriveKey(draft.label).isEmpty
                          ? '—'
                          : _deriveKey(draft.label)),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
                if (isEdit) ...[
                  const SizedBox(width: MercantisSpacing.xs),
                  Text(
                    '(locked)',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),

          // Type
          DropdownButtonFormField<_CustomizableType>(
            value: draft.type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: _CustomizableType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          Icon(t.icon, size: 16),
                          const SizedBox(width: 8),
                          Text(t.label),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: isEdit
                ? null
                : (t) {
                    if (t == null) return;
                    setState(() => _editor =
                        _editor!.copyWith(draft: draft.copyWith(type: t)));
                  },
          ),
          if (isEdit)
            Padding(
              padding: const EdgeInsets.only(top: MercantisSpacing.xs),
              child: Text(
                "Type can't be changed after creating the field — remove and re-add to switch type.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          if (draft.type == _CustomizableType.choice) ...[
            const SizedBox(height: MercantisSpacing.md),
            TextFormField(
              initialValue: draft.optionsText,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Choices',
                hintText: 'One choice per line',
              ),
              onChanged: (v) => setState(() => _editor =
                  _editor!.copyWith(draft: draft.copyWith(optionsText: v))),
            ),
          ],

          const SizedBox(height: MercantisSpacing.md),

          // Position
          DropdownButtonFormField<String?>(
            value: draft.insertAfter,
            decoration: const InputDecoration(labelText: 'Place after'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('End of form'),
              ),
              ...positionCandidates.map(
                (e) => DropdownMenuItem<String?>(
                  value: e.key,
                  child: Text(e.label),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _editor =
                _editor!.copyWith(draft: draft.copyWith(insertAfter: v, clearInsertAfter: v == null))),
          ),
          const SizedBox(height: MercantisSpacing.md),

          // Required
          SwitchListTile(
            title: const Text('Required'),
            contentPadding: EdgeInsets.zero,
            value: draft.required,
            onChanged: (v) => setState(() => _editor =
                _editor!.copyWith(draft: draft.copyWith(required: v))),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: MercantisSpacing.md),
            Text(_errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],

          const SizedBox(height: MercantisSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _editor = null;
                  _errorMessage = null;
                }),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: MercantisSpacing.sm),
              FilledButton(
                onPressed: draft.isCommitReady(isEdit: isEdit, currentKey: currentKey)
                    ? () => _commit(database, customFields, reservedKeys, currentKey)
                    : null,
                child: Text(isEdit ? 'Save Changes' : 'Add Field'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _commit(
    MercantisDatabase database,
    List<CustomField> existing,
    Set<String> reservedKeys,
    String? currentKey,
  ) async {
    final draft = _editor!.draft;
    final isEdit = _editor!.mode == _EditorMode.edit;
    final key = isEdit ? (currentKey ?? '') : _deriveKey(draft.label);

    if (key.isEmpty) {
      setState(() => _errorMessage = 'Please enter a label.');
      return;
    }
    if (!isEdit && reservedKeys.contains(key)) {
      setState(() => _errorMessage =
          '"$key" clashes with another field on this form. Pick a different label.');
      return;
    }

    final definition = FieldDefinition(
      key: key,
      type: draft.type.fieldType,
      label: draft.label.trim(),
      required: draft.required,
      options: draft.type == _CustomizableType.choice
          ? draft.optionsText
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .join('\n')
          : null,
    );

    final field = CustomField(
      id: isEdit ? (_editor!.editingId ?? '') : '',
      docTypeId: widget.docTypeName,
      fieldDefinition: definition,
      insertAfter: draft.insertAfter,
    );

    try {
      await CustomField.save(database.db, field);
      _onCustomFieldsChanged();
      setState(() {
        _editor = null;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
  }

  void _onCustomFieldsChanged() {
    // Drop the cached ResolvedMeta so the form picks up the new schema.
    final composer = ref.read(metaComposerProvider).valueOrNull;
    composer?.invalidate(widget.docTypeName);
    ref.invalidate(resolvedMetaProvider(widget.docTypeName));
    // Re-run the FutureBuilder above by triggering a rebuild.
    if (mounted) setState(() {});
  }

  // -- Helpers -------------------------------------------------------------

  /// "VAT Number" → "vat_number". Diacritic-folded, snake-cased, leading
  /// digits stripped so the result is a usable identifier.
  static String _deriveKey(String label) {
    final folded = _stripDiacritics(label);
    final buf = StringBuffer();
    var lastWasSeparator = false;
    for (final rune in folded.runes) {
      final ch = String.fromCharCode(rune);
      if (_isAlphaNum(ch)) {
        buf.write(ch.toLowerCase());
        lastWasSeparator = false;
      } else if (buf.isNotEmpty && !lastWasSeparator) {
        buf.write('_');
        lastWasSeparator = true;
      }
    }
    var s = buf.toString();
    while (s.endsWith('_')) {
      s = s.substring(0, s.length - 1);
    }
    while (s.isNotEmpty && (RegExp(r'^[0-9_]').hasMatch(s[0]))) {
      s = s.substring(1);
    }
    return s;
  }

  static bool _isAlphaNum(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 48 && c <= 57) ||
        (c >= 65 && c <= 90) ||
        (c >= 97 && c <= 122);
  }

  static const _diacriticMap = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ñ': 'n', 'ç': 'c', 'ß': 'ss',
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
    'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
    'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
    'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
    'Ñ': 'N', 'Ç': 'C',
  };

  static String _stripDiacritics(String input) {
    final out = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      out.write(_diacriticMap[ch] ?? ch);
    }
    return out.toString();
  }
}

// =======================================================================
// Helpers (internal)
// =======================================================================

class _BaseFieldEntry {
  const _BaseFieldEntry({required this.key, required this.label});
  final String key;
  final String label;
}

class _CustomFieldTile extends StatelessWidget {
  const _CustomFieldTile({
    required this.field,
    required this.onEdit,
    required this.onRemove,
  });

  final CustomField field;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = _CustomizableType.fromFieldType(field.fieldDefinition.type);
    final position = (field.insertAfter == null || field.insertAfter!.isEmpty)
        ? 'End of form'
        : 'After ${field.insertAfter}';

    return ListTile(
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(t.icon,
            size: 18, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(field.fieldDefinition.label,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${t.label} · $position'
        '${field.fieldDefinition.required ? ' · Required' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

enum _EditorMode { add, edit }

class _EditorState {
  const _EditorState({required this.mode, required this.draft, this.editingId});
  final _EditorMode mode;
  final _Draft draft;
  final String? editingId;

  _EditorState copyWith({_EditorMode? mode, _Draft? draft, String? editingId}) =>
      _EditorState(
        mode: mode ?? this.mode,
        draft: draft ?? this.draft,
        editingId: editingId ?? this.editingId,
      );
}

class _Draft {
  const _Draft({
    required this.label,
    required this.type,
    required this.required,
    required this.optionsText,
    this.insertAfter,
  });

  factory _Draft.empty() => const _Draft(
        label: '',
        type: _CustomizableType.text,
        required: false,
        optionsText: '',
      );

  factory _Draft.fromField(CustomField field) {
    final fd = field.fieldDefinition;
    return _Draft(
      label: fd.label,
      type: _CustomizableType.fromFieldType(fd.type),
      required: fd.required,
      optionsText: fd.options ?? '',
      insertAfter: field.insertAfter,
    );
  }

  final String label;
  final _CustomizableType type;
  final bool required;
  final String optionsText;
  final String? insertAfter;

  _Draft copyWith({
    String? label,
    _CustomizableType? type,
    bool? required,
    String? optionsText,
    String? insertAfter,
    bool clearInsertAfter = false,
  }) =>
      _Draft(
        label: label ?? this.label,
        type: type ?? this.type,
        required: required ?? this.required,
        optionsText: optionsText ?? this.optionsText,
        insertAfter: clearInsertAfter ? null : (insertAfter ?? this.insertAfter),
      );

  bool isCommitReady({required bool isEdit, String? currentKey}) {
    if (isEdit) return currentKey != null && currentKey.isNotEmpty;
    return _CustomizeFieldsSheetState._deriveKey(label).isNotEmpty;
  }
}

/// User-facing subset of [FieldType]. Power-user types (link, table,
/// attach, formula, …) are intentionally excluded — each needs a much
/// richer authoring UI.
enum _CustomizableType {
  text(label: 'Text', icon: Icons.text_fields, fieldType: FieldType.data),
  longText(
      label: 'Long text',
      icon: Icons.notes,
      fieldType: FieldType.longText),
  integer(
      label: 'Number (whole)',
      icon: Icons.numbers,
      fieldType: FieldType.integer),
  decimal(
      label: 'Number (decimal)',
      icon: Icons.exposure_zero,
      fieldType: FieldType.float),
  currency(
      label: 'Money',
      icon: Icons.payments_outlined,
      fieldType: FieldType.currency),
  yesNo(label: 'Yes / No', icon: Icons.check_box, fieldType: FieldType.check),
  date(label: 'Date', icon: Icons.calendar_today, fieldType: FieldType.date),
  choice(
      label: 'Choice list',
      icon: Icons.list_alt,
      fieldType: FieldType.select);

  const _CustomizableType({
    required this.label,
    required this.icon,
    required this.fieldType,
  });

  final String label;
  final IconData icon;
  final FieldType fieldType;

  static _CustomizableType fromFieldType(FieldType t) {
    switch (t) {
      case FieldType.data:
      case FieldType.text:
      case FieldType.smallText:
        return _CustomizableType.text;
      case FieldType.longText:
        return _CustomizableType.longText;
      case FieldType.integer:
        return _CustomizableType.integer;
      case FieldType.float:
      case FieldType.percent:
        return _CustomizableType.decimal;
      case FieldType.currency:
        return _CustomizableType.currency;
      case FieldType.check:
        return _CustomizableType.yesNo;
      case FieldType.date:
      case FieldType.dateTime:
        return _CustomizableType.date;
      case FieldType.select:
      case FieldType.autocomplete:
        return _CustomizableType.choice;
      default:
        return _CustomizableType.text;
    }
  }
}

// =======================================================================
// Presentation helpers
// =======================================================================

/// Show the customize sheet — as a `Dialog` on tablet/desktop where
/// there's room, and a draggable bottom sheet on phones.
Future<void> showCustomizeFieldsDialog(
  BuildContext context, {
  required String docTypeName,
}) async {
  final width = MediaQuery.of(context).size.width;
  if (width >= 600) {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: CustomizeFieldsSheet(docTypeName: docTypeName),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          child: CustomizeFieldsSheet(docTypeName: docTypeName),
        ),
      ),
    );
  }
}
