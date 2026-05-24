import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import '../providers/core_providers.dart';

class FormBuilderView extends ConsumerStatefulWidget {
  const FormBuilderView({super.key, required this.docTypeName});
  final String docTypeName;

  @override
  ConsumerState<FormBuilderView> createState() => _FormBuilderViewState();
}

class _FormBuilderViewState extends ConsumerState<FormBuilderView> {
  ResolvedFieldDefinition? _selected;

  @override
  Widget build(BuildContext context) {
    final metaAsync = ref.watch(resolvedMetaProvider(widget.docTypeName));
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    return Scaffold(
      appBar: AppBar(
        title: Text('Form Builder — ${widget.docTypeName}'),
        actions: [
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: metaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (meta) => wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 220,
                    child: _Palette(
                        onAdd: (ft) => _addField(ft)),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _Canvas(
                      meta: meta,
                      selected: _selected,
                      onSelect: (f) => setState(() => _selected = f),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 280,
                    child: _Inspector(field: _selected),
                  ),
                ],
              )
            : _Canvas(
                meta: meta,
                selected: _selected,
                onSelect: (f) => setState(() => _selected = f),
              ),
      ),
    );
  }

  void _addField(FieldType ft) {
    // Mutate via DocumentEngine in a full implementation
  }
}

const _paletteGroups = [
  ('Basic', [FieldType.data, FieldType.text, FieldType.longText, FieldType.integer, FieldType.float]),
  ('Choice', [FieldType.select, FieldType.check]),
  ('Date / Time', [FieldType.date, FieldType.datetime, FieldType.time]),
  ('Link', [FieldType.link, FieldType.dynamicLink]),
  ('Layout', [FieldType.sectionBreak, FieldType.columnBreak, FieldType.heading, FieldType.html]),
  ('Table', [FieldType.table, FieldType.tableMultiselect]),
  ('Media', [FieldType.attach, FieldType.attachImage, FieldType.color, FieldType.signature, FieldType.barcode]),
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
          child: Text('Fields',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final group in _paletteGroups) ...[  
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 6, horizontal: 4),
                  child: Text(
                    group.$1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                for (final ft in group.$2)
                  Draggable<FieldType>(
                    data: ft,
                    feedback: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Text(ft.name),
                      ),
                    ),
                    child: InkWell(
                      onTap: () => onAdd(ft),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.drag_indicator,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Text(ft.name,
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
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
  const _Canvas(
      {required this.meta, required this.selected, required this.onSelect});
  final ResolvedMeta? meta;
  final ResolvedFieldDefinition? selected;
  final ValueChanged<ResolvedFieldDefinition?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child:
              Text('Canvas', style: Theme.of(context).textTheme.labelLarge),
        ),
        const Divider(height: 1),
        Expanded(
          child: meta == null
              ? const Center(child: Text('No metadata'))
              : ReorderableListView(
                  padding: const EdgeInsets.all(16),
                  onReorder: (_, __) {},
                  children: [
                    for (final f in meta!.fields)
                      GestureDetector(
                        key: ValueKey(f.fieldKey),
                        onTap: () => onSelect(f),
                        child: _CanvasTile(
                          field: f,
                          isSelected:
                              selected?.fieldKey == f.fieldKey,
                        ),
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
  final ResolvedFieldDefinition field;
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
        color: isSelected
            ? cs.primaryContainer.withOpacity(0.15)
            : cs.surface,
      ),
      child: ListTile(
        leading: const Icon(Icons.drag_indicator, color: Colors.grey),
        title: Text(field.label ?? field.fieldKey),
        subtitle: Text(field.fieldType.name,
            style: Theme.of(context).textTheme.bodySmall),
        trailing: (field.isMandatory ?? false)
            ? const Tooltip(
                message: 'Required',
                child: Icon(Icons.star, size: 14, color: Colors.red))
            : null,
      ),
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({required this.field});
  final ResolvedFieldDefinition? field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Inspector',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        const Divider(height: 1),
        field == null
            ? const Expanded(
                child: Center(
                    child: Text('Select a field',
                        style: TextStyle(color: Colors.grey))))
            : Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _Row('Key', field!.fieldKey),
                    _Row('Label', field!.label ?? '—'),
                    _Row('Type', field!.fieldType.name),
                    _Row('Required',
                        (field!.isMandatory ?? false).toString()),
                    _Row('Read Only',
                        (field!.readOnly ?? false).toString()),
                    if (field!.options != null)
                      _Row('Options', field!.options!),
                    if (field!.defaultValue != null)
                      _Row('Default', field!.defaultValue!),
                    if (field!.conditionExpression != null)
                      _Row('Condition', field!.conditionExpression!),
                  ],
                ),
              ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  )),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 16),
        ],
      ),
    );
  }
}
