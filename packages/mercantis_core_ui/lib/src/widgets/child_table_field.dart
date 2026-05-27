import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../shell/breakpoints.dart';

/// Shared horizontal padding between header label cells and data cells.
/// Header and rows MUST use the same value — Swift PR #125 was a regression
/// caused by header using 10pt and rows using 8pt, leaving every column
/// visibly misaligned. One source of truth eliminates the drift.
const double kChildTableCellHPadding = 8.0;

const double _kIndexCellWidth = 36;
const double _kTrailingCellWidth = 44;

/// Full-width child-table grid for `FieldType.table` /
/// `FieldType.tableMultiSelect` fields on [GenericFormView].
///
/// Layout follows Swift UX-3 Option C: the grid claims the full sheet
/// width, columns get type-aware minimum widths, header and data rows
/// scroll horizontally in lockstep. Each row carries a trailing ellipsis
/// button that opens a per-row detail editor (Option A) — a dialog on
/// tablet/desktop, a draggable bottom sheet on phone — so fields that
/// don't fit comfortably as cells (longText, secondary attributes) are
/// still reachable.
class ChildTableField extends StatefulWidget {
  const ChildTableField({
    super.key,
    required this.field,
    required this.childDocType,
    required this.rows,
    required this.readOnly,
    required this.onChanged,
  });

  final ResolvedFieldDefinition field;
  final DocType? childDocType;
  final List<Map<String, dynamic>> rows;
  final bool readOnly;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<ChildTableField> createState() => _ChildTableFieldState();
}

class _ChildTableFieldState extends State<ChildTableField> {
  // One controller shared between header and body so they cannot drift
  // mid-scroll.
  final ScrollController _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void _updateRow(int idx, Map<String, dynamic> updated) {
    final next = List<Map<String, dynamic>>.from(widget.rows);
    next[idx] = updated;
    widget.onChanged(next);
  }

  void _removeRow(int idx) {
    final next = List<Map<String, dynamic>>.from(widget.rows)..removeAt(idx);
    widget.onChanged(next);
  }

  void _addRow(DocType childType) {
    final blank = <String, dynamic>{};
    for (final f in childType.fields) {
      if (f.defaultValue != null) blank[f.key] = f.defaultValue;
    }
    final next = List<Map<String, dynamic>>.from(widget.rows)..add(blank);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final childType = widget.childDocType;
    if (childType == null) {
      return _fallbackLabel(theme);
    }

    final fields =
        childType.fields.where((f) => !f.hidden && !_isLayout(f.type)).toList();
    final gridWidth = _totalMinWidth(fields);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Scrollbar(
          controller: _hScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: gridWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderRow(fields: fields),
                  Divider(height: 1, color: theme.dividerColor),
                  if (widget.rows.isEmpty)
                    _EmptyRow(width: gridWidth)
                  else
                    for (var i = 0; i < widget.rows.length; i++) ...[
                      _DataRow(
                        fields: fields,
                        rowIndex: i,
                        row: widget.rows[i],
                        readOnly: widget.readOnly,
                        onChanged: (updated) => _updateRow(i, updated),
                        onOpenEditor: () => _openRowEditor(childType, i),
                      ),
                      if (i < widget.rows.length - 1)
                        Divider(
                          height: 1,
                          color: theme.dividerColor.withValues(alpha: 0.4),
                        ),
                    ],
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
        _FooterBar(
          rowCount: widget.rows.length,
          readOnly: widget.readOnly,
          onAdd: () => _addRow(childType),
        ),
      ],
    );
  }

  Future<void> _openRowEditor(DocType childType, int rowIndex) async {
    final breakpoint = Breakpoint.of(context);
    final isPhone = breakpoint.isPhone;

    final result = await (isPhone
        ? showModalBottomSheet<_RowEditorResult>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (ctx) => DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scroll) => _ChildRowEditor(
                childDocType: childType,
                rowIndex: rowIndex,
                initial: widget.rows[rowIndex],
                readOnly: widget.readOnly,
                scrollController: scroll,
              ),
            ),
          )
        : showDialog<_RowEditorResult>(
            context: context,
            builder: (ctx) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 420,
                  maxWidth: 560,
                  minHeight: 420,
                  maxHeight: 640,
                ),
                child: _ChildRowEditor(
                  childDocType: childType,
                  rowIndex: rowIndex,
                  initial: widget.rows[rowIndex],
                  readOnly: widget.readOnly,
                ),
              ),
            ),
          ));

    if (!mounted || result == null) return;
    if (result.removed) {
      _removeRow(rowIndex);
    } else if (result.updated != null) {
      _updateRow(rowIndex, result.updated!);
    }
  }

  Widget _fallbackLabel(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Child DocType not resolved for "${widget.field.label}". '
              'Wire `childDocTypeProvider` on the form to enable inline editing.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

bool _isLayout(FieldType t) =>
    t == FieldType.sectionBreak ||
    t == FieldType.columnBreak ||
    t == FieldType.heading;

bool _coerceBool(dynamic v) {
  if (v is bool) return v;
  if (v is int) return v == 1;
  return false;
}

double _minWidth(FieldDefinition f) {
  switch (f.type) {
    case FieldType.currency:
    case FieldType.float:
    case FieldType.integer:
    case FieldType.percent:
      return 90;
    case FieldType.check:
      return 70;
    case FieldType.date:
    case FieldType.dateTime:
    case FieldType.time:
      return 130;
    case FieldType.link:
    case FieldType.dynamicLink:
      return 150;
    case FieldType.longText:
    case FieldType.text:
      return 200;
    case FieldType.select:
    case FieldType.autocomplete:
      return 140;
    default:
      final k = f.key.toLowerCase();
      if (k.contains('name') ||
          k.contains('description') ||
          k.contains('notes')) {
        return 200;
      }
      return 120;
  }
}

Alignment _cellAlignment(FieldDefinition f) {
  switch (f.type) {
    case FieldType.currency:
    case FieldType.float:
    case FieldType.integer:
    case FieldType.percent:
      return Alignment.centerRight;
    case FieldType.check:
      return Alignment.center;
    default:
      return Alignment.centerLeft;
  }
}

TextAlign _cellTextAlign(FieldDefinition f) {
  switch (f.type) {
    case FieldType.currency:
    case FieldType.float:
    case FieldType.integer:
    case FieldType.percent:
      return TextAlign.end;
    default:
      return TextAlign.start;
  }
}

double _totalMinWidth(List<FieldDefinition> fields) {
  var total = _kIndexCellWidth + _kTrailingCellWidth;
  for (final f in fields) {
    total += _minWidth(f) + kChildTableCellHPadding * 2;
  }
  return total;
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.fields});
  final List<FieldDefinition> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: _kIndexCellWidth,
            child: Center(child: Text('#', style: labelStyle)),
          ),
          for (final f in fields)
            Expanded(
              flex: _minWidth(f).round(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: kChildTableCellHPadding,
                ),
                alignment: _cellAlignment(f),
                child: Text(
                  f.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
            ),
          const SizedBox(width: _kTrailingCellWidth),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.fields,
    required this.rowIndex,
    required this.row,
    required this.readOnly,
    required this.onChanged,
    required this.onOpenEditor,
  });

  final List<FieldDefinition> fields;
  final int rowIndex;
  final Map<String, dynamic> row;
  final bool readOnly;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onOpenEditor;

  void _setCell(String key, dynamic value) {
    final next = Map<String, dynamic>.from(row);
    next[key] = value;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = rowIndex.isEven
        ? Colors.transparent
        : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4);
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _kIndexCellWidth,
            child: Center(
              child: Text(
                '${rowIndex + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          for (final f in fields)
            Expanded(
              flex: _minWidth(f).round(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kChildTableCellHPadding,
                ),
                child: _cell(context, f),
              ),
            ),
          SizedBox(
            width: _kTrailingCellWidth,
            child: IconButton(
              tooltip: 'Edit row',
              icon: const Icon(Icons.more_vert, size: 18),
              onPressed: onOpenEditor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, FieldDefinition f) {
    final value = row[f.key];
    switch (f.type) {
      case FieldType.check:
        return Align(
          alignment: Alignment.center,
          child: Switch(
            value: _coerceBool(value),
            onChanged: readOnly ? null : (v) => _setCell(f.key, v),
          ),
        );
      case FieldType.integer:
        return _CellTextField(
          value: (value as int?)?.toString() ?? '',
          textAlign: TextAlign.end,
          readOnly: readOnly,
          keyboardType: TextInputType.number,
          hint: f.label,
          onChanged: (s) => _setCell(f.key, int.tryParse(s)),
        );
      case FieldType.float:
      case FieldType.currency:
      case FieldType.percent:
        return _CellTextField(
          value: (value as num?)?.toString() ?? '',
          textAlign: TextAlign.end,
          readOnly: readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hint: f.label,
          onChanged: (s) => _setCell(f.key, double.tryParse(s)),
        );
      case FieldType.date:
        return _CellDateField(
          value: value as String?,
          readOnly: readOnly,
          onChanged: (s) => _setCell(f.key, s),
        );
      case FieldType.link:
      case FieldType.dynamicLink:
        // Links inline as plain text in cells; the per-row editor opens
        // the full link picker.
        return _CellTextField(
          value: value?.toString() ?? '',
          textAlign: TextAlign.start,
          readOnly: readOnly,
          hint: f.label,
          onChanged: (s) => _setCell(f.key, s),
        );
      default:
        return _CellTextField(
          value: value?.toString() ?? '',
          textAlign: _cellTextAlign(f),
          readOnly: readOnly,
          hint: f.label,
          onChanged: (s) => _setCell(f.key, s),
        );
    }
  }
}

class _CellTextField extends StatefulWidget {
  const _CellTextField({
    required this.value,
    required this.textAlign,
    required this.readOnly,
    required this.onChanged,
    this.keyboardType,
    this.hint,
  });

  final String value;
  final TextAlign textAlign;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final String? hint;

  @override
  State<_CellTextField> createState() => _CellTextFieldState();
}

class _CellTextFieldState extends State<_CellTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_CellTextField old) {
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
    // SizedBox(width: infinity) so the fill colour of the input chrome
    // spans the whole column cell — without it the rounded background
    // hugs the text and leaves a visible gap when content is short.
    return SizedBox(
      width: double.infinity,
      child: TextField(
        controller: _controller,
        readOnly: widget.readOnly,
        keyboardType: widget.keyboardType,
        textAlign: widget.textAlign,
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.readOnly ? null : widget.onChanged,
      ),
    );
  }
}

class _CellDateField extends StatelessWidget {
  const _CellDateField({
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });
  final String? value;
  final bool readOnly;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(value ?? '');
    final label = parsed != null
        ? DateFormat('yyyy-MM-dd').format(parsed)
        : (value?.isNotEmpty == true ? value! : 'Pick…');
    return InkWell(
      onTap: readOnly
          ? null
          : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: parsed ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                onChanged(DateFormat('yyyy-MM-dd').format(picked));
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            'No rows yet.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}

class _FooterBar extends StatelessWidget {
  const _FooterBar({
    required this.rowCount,
    required this.readOnly,
    required this.onAdd,
  });
  final int rowCount;
  final bool readOnly;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          if (!readOnly)
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('Add Row'),
            ),
          const Spacer(),
          Text(
            '$rowCount ${rowCount == 1 ? "row" : "rows"}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowEditorResult {
  const _RowEditorResult.updated(this.updated) : removed = false;
  const _RowEditorResult.removed()
      : updated = null,
        removed = true;
  final Map<String, dynamic>? updated;
  final bool removed;
}

class _ChildRowEditor extends StatefulWidget {
  const _ChildRowEditor({
    required this.childDocType,
    required this.rowIndex,
    required this.initial,
    required this.readOnly,
    this.scrollController,
  });

  final DocType childDocType;
  final int rowIndex;
  final Map<String, dynamic> initial;
  final bool readOnly;
  final ScrollController? scrollController;

  @override
  State<_ChildRowEditor> createState() => _ChildRowEditorState();
}

class _ChildRowEditorState extends State<_ChildRowEditor> {
  late final Map<String, dynamic> _draft =
      Map<String, dynamic>.from(widget.initial);

  String _summary() {
    for (final f in widget.childDocType.fields) {
      final v = _draft[f.key];
      if (v is String && v.isNotEmpty) return v;
      if (v is num) return v.toString();
    }
    return '';
  }

  Future<void> _confirmRemove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove row?'),
        content: const Text('This will discard the row from the child table.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
              backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(const _RowEditorResult.removed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = widget.childDocType.fields
        .where((f) => !f.hidden && !_isLayout(f.type))
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Edit ${widget.childDocType.name} · #${widget.rowIndex + 1}',
                style: theme.textTheme.titleSmall,
              ),
              if (_summary().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _summary(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              for (final f in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _editorControl(context, f),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (!widget.readOnly)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _confirmRemove,
                  child: const Text('Remove row'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_RowEditorResult.updated(_draft)),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editorControl(BuildContext context, FieldDefinition f) {
    final value = _draft[f.key];
    final decoration = InputDecoration(labelText: f.label);
    switch (f.type) {
      case FieldType.check:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _coerceBool(value),
          onChanged:
              widget.readOnly ? null : (v) => setState(() => _draft[f.key] = v),
        );
      case FieldType.integer:
        return TextFormField(
          initialValue: (value as int?)?.toString() ?? '',
          decoration: decoration,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.end,
          readOnly: widget.readOnly,
          onChanged: (s) => _draft[f.key] = int.tryParse(s),
        );
      case FieldType.float:
      case FieldType.currency:
      case FieldType.percent:
        return TextFormField(
          initialValue: (value as num?)?.toString() ?? '',
          decoration: decoration.copyWith(
            suffixText: f.type == FieldType.percent ? '%' : null,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.end,
          readOnly: widget.readOnly,
          onChanged: (s) => _draft[f.key] = double.tryParse(s),
        );
      case FieldType.date:
        return TextFormField(
          key: ValueKey('date_${f.key}_${value ?? ""}'),
          initialValue: value as String? ?? '',
          decoration: decoration.copyWith(
            suffixIcon: widget.readOnly
                ? null
                : IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final parsed = DateTime.tryParse(value ?? '');
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: parsed ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _draft[f.key] =
                            DateFormat('yyyy-MM-dd').format(picked));
                      }
                    },
                  ),
          ),
          readOnly: widget.readOnly,
          onChanged: (s) => _draft[f.key] = s,
        );
      case FieldType.longText:
        return TextFormField(
          initialValue: value as String? ?? '',
          decoration: decoration,
          maxLines: 5,
          readOnly: widget.readOnly,
          onChanged: (s) => _draft[f.key] = s,
        );
      case FieldType.select:
        final opts =
            (f.options ?? '').split('\n').where((o) => o.isNotEmpty).toList();
        return DropdownButtonFormField<String>(
          value: value as String?,
          decoration: decoration,
          items: opts
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged:
              widget.readOnly ? null : (v) => setState(() => _draft[f.key] = v),
        );
      default:
        return TextFormField(
          initialValue: value?.toString() ?? '',
          decoration: decoration,
          readOnly: widget.readOnly,
          onChanged: (s) => _draft[f.key] = s,
        );
    }
  }
}
