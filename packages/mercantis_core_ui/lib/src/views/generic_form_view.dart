import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../providers/core_providers.dart';
import 'record_workspace_chrome.dart';

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
    final data = Map<String, dynamic>.from(base.data)..addAll(_changes);
    return base.copyWith(data: data);
  }

  Document _emptyDoc() =>
      Document(docType: widget.docTypeName, data: {});

  Future<void> _save(DocumentEngine engine, Document current) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await engine.save(current);
      setState(() => _changes.clear());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _submit(DocumentEngine engine, String name) async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await engine.submit(widget.docTypeName, name);
      ref.invalidate(_fetchDocProvider((widget.docTypeName, name)));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isSaving = false);
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
          final docStatus = doc['docstatus'] as int? ?? 0;

          return RecordWorkspaceChrome(
            docTypeName: widget.docTypeName,
            documentName: doc['name'] as String?,
            isDirty: _isDirty,
            isSaving: _isSaving,
            isSubmittable: isSubmittable,
            docStatus: docStatus,
            onSave: () => _save(engine, doc),
            onSubmit: () {
              final name = doc['name'] as String?;
              if (name != null) _submit(engine, name);
            },
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
    final fields = meta.visibleFields.where((f) =>
        f.fieldType != FieldType.sectionBreak &&
        f.fieldType != FieldType.columnBreak);
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
                value: doc[f.fieldKey],
                readOnly: readOnly,
                onChanged: (v) => onChanged(f.fieldKey, v),
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
          for (final e in doc.data.entries)
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

  String get _label => field.label ?? field.fieldKey;

  @override
  Widget build(BuildContext context) {
    switch (field.fieldType) {
      case FieldType.check:
        return CheckboxListTile(
          title: Text(_label),
          value: (value as int? ?? 0) == 1,
          onChanged: readOnly ? null : (v) => onChanged(v == true ? 1 : 0),
          contentPadding: EdgeInsets.zero,
        );
      case FieldType.integer:
        return TextFormField(
          key: ValueKey('${field.fieldKey}_${value}'),
          initialValue: (value as int?)?.toString() ?? '',
          decoration: InputDecoration(labelText: _label),
          keyboardType: TextInputType.number,
          readOnly: readOnly,
          onChanged: readOnly ? null : (v) => onChanged(int.tryParse(v)),
        );
      case FieldType.float:
      case FieldType.currency:
      case FieldType.percent:
        return TextFormField(
          key: ValueKey('${field.fieldKey}_${value}'),
          initialValue: (value as double?)?.toString() ?? '',
          decoration: InputDecoration(
            labelText: _label,
            suffixText:
                field.fieldType == FieldType.percent ? '%' : null,
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          readOnly: readOnly,
          onChanged: readOnly ? null : (v) => onChanged(double.tryParse(v)),
        );
      case FieldType.select:
        final opts = (field.options ?? '').split('\n').where((o) => o.isNotEmpty).toList();
        return DropdownButtonFormField<String>(
          value: value as String?,
          decoration: InputDecoration(labelText: _label),
          items: opts
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: readOnly ? null : (v) => onChanged(v),
        );
      case FieldType.date:
        return _DateField(
          label: _label,
          value: value as String?,
          readOnly: readOnly,
          onChanged: onChanged,
        );
      case FieldType.link:
        return TextFormField(
          key: ValueKey('${field.fieldKey}_${value}'),
          initialValue: value as String? ?? '',
          decoration: InputDecoration(
            labelText: _label,
            hintText: 'Link to ${field.options ?? ""}',
            suffixIcon: const Icon(Icons.link),
          ),
          readOnly: readOnly,
          onChanged: readOnly ? null : onChanged,
        );
      case FieldType.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            _label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      case FieldType.longText:
      case FieldType.textEditor:
        return TextFormField(
          key: ValueKey('${field.fieldKey}_${value}'),
          initialValue: value as String? ?? '',
          decoration: InputDecoration(labelText: _label),
          maxLines: 5,
          readOnly: readOnly,
          onChanged: readOnly ? null : onChanged,
        );
      default:
        return TextFormField(
          key: ValueKey('${field.fieldKey}_${value}'),
          initialValue: value?.toString() ?? '',
          decoration: InputDecoration(labelText: _label),
          readOnly: readOnly,
          onChanged: readOnly ? null : onChanged,
        );
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('date_${value}'),
      initialValue: value ?? '',
      decoration: InputDecoration(
        labelText: label,
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
