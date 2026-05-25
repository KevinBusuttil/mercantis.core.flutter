import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../providers/core_providers.dart';
import 'record_workspace_chrome.dart';

const _userRoles = <String>{'System Manager'};

final _fetchDocProvider =
    FutureProvider.family<Document?, (String, String?)>((ref, args) async {
  final (docTypeName, name) = args;
  if (name == null) return null;
  final engine = await ref.watch(documentEngineProvider.future);
  return engine.fetch(docTypeName, name);
});

class GenericFormView extends ConsumerStatefulWidget {
  const GenericFormView({
    super.key,
    required this.docTypeName,
    required this.documentName,
  });
  final String docTypeName;
  final String? documentName;

  @override
  ConsumerState<GenericFormView> createState() => _GenericFormViewState();
}

class _GenericFormViewState extends ConsumerState<GenericFormView> {
  final Map<String, dynamic> _changes = {};
  bool _isSaving = false;
  String? _error;

  bool get _isDirty => _changes.isNotEmpty;

  Document _apply(Document base) {
    if (_changes.isEmpty) return base;
    final payload = Map<String, dynamic>.from(base.payload)..addAll(_changes);
    return base.copyWith(payload: payload);
  }

  Document _emptyDoc() => Document(id: '', docType: widget.docTypeName);

  Future<void> _save(DocumentEngine engine, Document current) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await engine.save(current, _userRoles);
      setState(() => _changes.clear());
      ref.invalidate(_fetchDocProvider((widget.docTypeName, current.id)));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submit(DocumentEngine engine, Document current) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await engine.submit(current, _userRoles);
      ref.invalidate(_fetchDocProvider((widget.docTypeName, current.id)));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fetchAsync =
        ref.watch(_fetchDocProvider((widget.docTypeName, widget.documentName)));
    final engineAsync = ref.watch(documentEngineProvider);
    final metaAsync =
        ref.watch(resolvedMetaProvider(widget.docTypeName));

    return fetchAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (fetched) => engineAsync.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
        data: (engine) {
          final base = fetched ?? _emptyDoc();
          final doc = _apply(base);
          final isSubmittable =
              metaAsync.valueOrNull?.docType.isSubmittable ?? false;
          final docStatus = doc.docStatus;

          return RecordWorkspaceChrome(
            docTypeName: widget.docTypeName,
            documentName: doc.id.isEmpty ? null : doc.id,
            isDirty: _isDirty,
            isSaving: _isSaving,
            isSubmittable: isSubmittable,
            docStatus: docStatus,
            onSave: () => _save(engine, doc),
            onSubmit: () => _submit(engine, doc),
            error: _error,
            child: metaAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (meta) => meta != null
                  ? _MetaForm(
                      doc: doc,
                      meta: meta,
                      readOnly: docStatus != 0,
                      onChanged: (k, v) =>
                          setState(() => _changes[k] = v),
                    )
                  : _RawForm(doc: doc),
            ),
          );
        },
      ),
    );
  }
}

class _MetaForm extends StatelessWidget {
  const _MetaForm({
    required this.doc,
    required this.meta,
    required this.readOnly,
    required this.onChanged,
  });
  final Document doc;
  final ResolvedMeta meta;
  final bool readOnly;
  final void Function(String key, dynamic value) onChanged;

  @override
  Widget build(BuildContext context) {
    final fields = meta.visibleFields;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FieldWidget(
                field: f,
                value: doc[f.key],
                readOnly: readOnly,
                onChanged: (v) => onChanged(f.key, v),
              ),
            ),
        ],
      ),
    );
  }
}

class _RawForm extends StatelessWidget {
  const _RawForm({required this.doc});
  final Document doc;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (final e in doc.payload.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                initialValue: e.value?.toString() ?? '',
                decoration: InputDecoration(labelText: e.key),
                readOnly: true,
              ),
            ),
        ],
      ),
    );
  }
}

class FieldWidget extends StatelessWidget {
  const FieldWidget({
    super.key,
    required this.field,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });
  final ResolvedFieldDefinition field;
  final dynamic value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  String get _label => field.label;

  /// Builds an `InputDecoration` that appends a red asterisk to the label
  /// when the field is required. Using `label:` (a `Widget`) instead of
  /// `labelText:` lets us inline the marker without giving up Material's
  /// native floating-label behaviour.
  InputDecoration _decoration(
    BuildContext context, {
    String? hintText,
    Widget? suffixIcon,
    String? suffixText,
  }) {
    return InputDecoration(
      label: _RequiredAwareLabel(label: _label, required: field.required),
      hintText: hintText,
      suffixIcon: suffixIcon,
      suffixText: suffixText,
    );
  }

  /// Inline label widget for non-`InputDecoration` controls (heading,
  /// checkbox, etc.) — same red-asterisk treatment.
  Widget _inlineLabel(BuildContext context, {TextStyle? style}) {
    return _RequiredAwareLabel(
      label: _label,
      required: field.required,
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case FieldType.check:
        return CheckboxListTile(
          title: _inlineLabel(context),
          value: (value as int? ?? 0) == 1,
          onChanged: readOnly ? null : (v) => onChanged(v == true ? 1 : 0),
          contentPadding: EdgeInsets.zero,
        );
      case FieldType.integer:
        return _TextFieldEditor(
          value: (value as int?)?.toString() ?? '',
          decoration: _decoration(context),
          keyboardType: TextInputType.number,
          readOnly: readOnly,
          onChanged: (v) => onChanged(int.tryParse(v)),
        );
      case FieldType.float:
      case FieldType.currency:
      case FieldType.percent:
        return _TextFieldEditor(
          value: (value as num?)?.toString() ?? '',
          decoration: _decoration(
            context,
            suffixText: field.type == FieldType.percent ? '%' : null,
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          readOnly: readOnly,
          onChanged: (v) => onChanged(double.tryParse(v)),
        );
      case FieldType.select:
        final opts = (field.options ?? '')
            .split('\n')
            .where((o) => o.isNotEmpty)
            .toList();
        return DropdownButtonFormField<String>(
          value: value as String?,
          decoration: _decoration(context),
          items: opts
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: readOnly ? null : (v) => onChanged(v),
        );
      case FieldType.date:
        return _DateField(
          label: _label,
          required: field.required,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      case FieldType.link:
        return _TextFieldEditor(
          value: value as String? ?? '',
          decoration: _decoration(
            context,
            hintText: 'Link to ${field.options ?? ""}',
            suffixIcon: const Icon(Icons.link),
          ),
          readOnly: readOnly,
          onChanged: onChanged,
        );
      case FieldType.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: _inlineLabel(
            context,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      case FieldType.longText:
      case FieldType.smallText:
      case FieldType.text:
        return _TextFieldEditor(
          value: value as String? ?? '',
          decoration: _decoration(context),
          maxLines: 5,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      default:
        return _TextFieldEditor(
          value: value?.toString() ?? '',
          decoration: _decoration(context),
          readOnly: readOnly,
          onChanged: onChanged,
        );
    }
  }
}

/// Field label that appends a red asterisk when the field is required.
///
/// Hides the asterisk from accessibility (a separate semantic label
/// announces the field as "<label>, required") so screen readers don't
/// hear a punctuation character.
class _RequiredAwareLabel extends StatelessWidget {
  const _RequiredAwareLabel({
    required this.label,
    required this.required,
    this.style,
  });
  final String label;
  final bool required;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final asteriskStyle = base.copyWith(
      color: Theme.of(context).colorScheme.error,
      fontWeight: FontWeight.w600,
    );
    return Semantics(
      label: required ? '$label, required' : label,
      excludeSemantics: true,
      child: RichText(
        text: TextSpan(style: base, children: [
          TextSpan(text: label),
          if (required) TextSpan(text: ' *', style: asteriskStyle),
        ]),
      ),
    );
  }
}

class _TextFieldEditor extends StatefulWidget {
  const _TextFieldEditor({
    required this.value,
    required this.decoration,
    required this.readOnly,
    required this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
  });
  final String value;
  final InputDecoration decoration;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  State<_TextFieldEditor> createState() => _TextFieldEditorState();
}

class _TextFieldEditorState extends State<_TextFieldEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_TextFieldEditor old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      readOnly: widget.readOnly,
      onChanged: widget.readOnly ? null : widget.onChanged,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.required,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });
  final String label;
  final bool required;
  final String? value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('date_$value'),
      initialValue: value ?? '',
      decoration: InputDecoration(
        label: _RequiredAwareLabel(label: label, required: required),
        suffixIcon: readOnly
            ? null
            : IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.tryParse(value ?? '') ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    onChanged(DateFormat('yyyy-MM-dd').format(picked));
                  }
                },
              ),
      ),
      readOnly: readOnly,
      onChanged: readOnly ? null : onChanged,
    );
  }
}
