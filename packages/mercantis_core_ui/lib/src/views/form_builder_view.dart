import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../providers/core_providers.dart';

/// Custom fields currently saved for a DocType (used to recover each custom
/// field's id when editing/deleting).
final _customFieldsProvider =
    FutureProvider.family<List<CustomField>, String>((ref, docType) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return CustomField.forDocType(db.db, docType);
});

/// One editable row in the builder. Base (non-custom) fields are shown locked;
/// custom fields can be renamed, toggled required, reordered and deleted, then
/// persisted as [CustomField]s.
class _Draft {
  _Draft({
    required this.key,
    required this.label,
    required this.type,
    required this.isCustom,
    this.required = false,
    this.options,
    this.source,
  });

  String key;
  String label;
  FieldType type;
  bool required;
  String? options;
  final bool isCustom;

  /// The full original [FieldDefinition] for an existing custom field, so a
  /// re-save preserves props the builder doesn't edit (defaults, options…).
  final FieldDefinition? source;
}

class FormBuilderView extends ConsumerStatefulWidget {
  const FormBuilderView({super.key, required this.docTypeName});
  final String docTypeName;

  @override
  ConsumerState<FormBuilderView> createState() => _FormBuilderViewState();
}

class _FormBuilderViewState extends ConsumerState<FormBuilderView> {
  final List<_Draft> _drafts = [];
  String? _selectedKey;
  bool _loaded = false;
  bool _dirty = false;
  bool _saving = false;
  int _seq = 0;

  void _seed(ResolvedMeta meta, List<CustomField> customs) {
    final byKey = {for (final c in customs) c.fieldDefinition.key: c};
    _drafts
      ..clear()
      ..addAll([
        for (final f in meta.fields)
          _Draft(
            key: f.key,
            label: f.label,
            type: f.type,
            required: f.required,
            options: f.options,
            isCustom: f.isCustomField,
            source: byKey[f.key]?.fieldDefinition,
          ),
      ]);
    _selectedKey = null;
    _dirty = false;
  }

  void _addField(FieldType ft) {
    final existing = _drafts.map((d) => d.key).toSet();
    var key = 'cf_${ft.name}_${_seq++}';
    while (existing.contains(key)) {
      key = 'cf_${ft.name}_${_seq++}';
    }
    setState(() {
      _drafts.add(_Draft(
        key: key,
        label: 'New ${ft.name}',
        type: ft,
        isCustom: true,
      ));
      _selectedKey = key;
      _dirty = true;
    });
  }

  void _delete(_Draft d) {
    if (!d.isCustom) return;
    setState(() {
      _drafts.removeWhere((x) => x.key == d.key);
      if (_selectedKey == d.key) _selectedKey = null;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = (await ref.read(mercantisDatabaseProvider.future)).db;
      // Rebuild the custom-field set so the persisted rowid order matches the
      // canvas: drop every existing custom field, then re-insert the current
      // drafts in order. Inserting in canvas order assigns ascending rowids, so
      // `insertAfter` chains (incl. custom→custom) replay correctly on reload.
      for (final c in await CustomField.forDocType(db, widget.docTypeName)) {
        await CustomField.delete(db, c.id);
      }
      String? prevKey;
      for (final d in _drafts) {
        if (d.isCustom) {
          final fd = d.source != null
              ? d.source!.copyWith(label: d.label, required: d.required)
              : FieldDefinition(
                  key: d.key,
                  label: d.label,
                  type: d.type,
                  required: d.required,
                  options: d.options,
                );
          await CustomField.save(
            db,
            CustomField(
              id: '', // empty → fresh row appended in canvas order
              docTypeId: widget.docTypeName,
              insertAfter: prevKey,
              fieldDefinition: fd,
            ),
          );
        }
        prevKey = d.key;
      }
      // Drop caches so the resolved schema reflects the new fields.
      ref.read(metaComposerProvider).valueOrNull?.invalidate(widget.docTypeName);
      ref.invalidate(resolvedMetaProvider(widget.docTypeName));
      ref.invalidate(_customFieldsProvider(widget.docTypeName));
      if (!mounted) return;
      setState(() {
        _saving = false;
        _loaded = false; // re-seed from the freshly resolved meta
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Form saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final metaAsync = ref.watch(resolvedMetaProvider(widget.docTypeName));
    final customsAsync = ref.watch(_customFieldsProvider(widget.docTypeName));
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    // Seed the editable model once both async sources are ready.
    final meta = metaAsync.valueOrNull;
    final customs = customsAsync.valueOrNull;
    if (!_loaded && meta != null && customs != null) {
      _seed(meta, customs);
      _loaded = true;
    }

    _Draft? selected;
    if (_selectedKey != null) {
      for (final d in _drafts) {
        if (d.key == _selectedKey) {
          selected = d;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Form Builder — ${widget.docTypeName}'),
        actions: [
          FilledButton.icon(
            onPressed: (_dirty && !_saving) ? _save : null,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Save'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: metaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (_) {
          final canvas = _Canvas(
            drafts: _drafts,
            selectedKey: _selectedKey,
            onSelect: (k) => setState(() => _selectedKey = k),
            onReorder: _reorder,
          );
          if (!wide) return canvas;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 220, child: _Palette(onAdd: _addField)),
              const VerticalDivider(width: 1),
              Expanded(child: canvas),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 300,
                child: _Inspector(
                  field: selected,
                  onLabel: (v) => setState(() {
                    selected!.label = v;
                    _dirty = true;
                  }),
                  onRequired: (v) => setState(() {
                    selected!.required = v;
                    _dirty = true;
                  }),
                  onDelete: selected == null ? null : () => _delete(selected!),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final d = _drafts.removeAt(oldIndex);
      _drafts.insert(newIndex, d);
      _dirty = true;
    });
  }
}

const _paletteGroups = [
  ('Basic', [
    FieldType.data,
    FieldType.text,
    FieldType.longText,
    FieldType.integer,
    FieldType.float,
    FieldType.currency,
  ]),
  ('Choice', [FieldType.select, FieldType.check]),
  ('Date / Time', [FieldType.date, FieldType.dateTime, FieldType.time]),
];

class _Palette extends StatelessWidget {
  const _Palette({required this.onAdd});
  final ValueChanged<FieldType> onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Add field', style: Theme.of(context).textTheme.labelLarge),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final group in _paletteGroups) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Text(
                    group.$1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                for (final ft in group.$2)
                  InkWell(
                    onTap: () => onAdd(ft),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.add, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(ft.name, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Canvas extends StatelessWidget {
  const _Canvas({
    required this.drafts,
    required this.selectedKey,
    required this.onSelect,
    required this.onReorder,
  });
  final List<_Draft> drafts;
  final String? selectedKey;
  final ValueChanged<String> onSelect;
  final void Function(int, int) onReorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Canvas', style: Theme.of(context).textTheme.labelLarge),
        ),
        const Divider(height: 1),
        Expanded(
          child: drafts.isEmpty
              ? const Center(child: Text('No fields'))
              : ReorderableListView(
                  padding: const EdgeInsets.all(16),
                  onReorder: onReorder,
                  children: [
                    for (final f in drafts)
                      GestureDetector(
                        key: ValueKey(f.key),
                        onTap: () => onSelect(f.key),
                        child: _CanvasTile(field: f, isSelected: selectedKey == f.key),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CanvasTile extends StatelessWidget {
  const _CanvasTile({required this.field, required this.isSelected});
  final _Draft field;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? cs.primary : cs.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isSelected ? cs.primaryContainer.withValues(alpha: 0.15) : cs.surface,
      ),
      child: ListTile(
        leading: const Icon(Icons.drag_indicator, color: Colors.grey),
        title: Text(field.label),
        subtitle: Text(
          '${field.type.name}${field.isCustom ? ' · custom' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: field.required
            ? const Tooltip(message: 'Required', child: Icon(Icons.star, size: 14, color: Colors.red))
            : null,
      ),
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.field,
    required this.onLabel,
    required this.onRequired,
    required this.onDelete,
  });
  final _Draft? field;
  final ValueChanged<String> onLabel;
  final ValueChanged<bool> onRequired;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final f = field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Inspector', style: Theme.of(context).textTheme.labelLarge),
        ),
        const Divider(height: 1),
        if (f == null)
          const Expanded(
            child: Center(child: Text('Select a field', style: TextStyle(color: Colors.grey))),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _ro(context, 'Key', f.key),
                _ro(context, 'Type', f.type.name),
                const SizedBox(height: 8),
                if (f.isCustom) ...[
                  TextFormField(
                    key: ValueKey('label_${f.key}'),
                    initialValue: f.label,
                    decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder()),
                    onChanged: onLabel,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Required'),
                    value: f.required,
                    onChanged: onRequired,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete field'),
                  ),
                ] else ...[
                  _ro(context, 'Label', f.label),
                  _ro(context, 'Required', f.required.toString()),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Base fields are defined in code and read-only here.',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _ro(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
