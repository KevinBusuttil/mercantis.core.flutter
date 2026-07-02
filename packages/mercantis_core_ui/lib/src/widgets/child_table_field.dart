import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../shell/breakpoints.dart';
import '../theme/atlas/atlas_field_row.dart';
import 'link_picker_field.dart';

/// Shared across rows so the expression parse-cache is reused. Evaluates
/// per-row `formulaExpression`s (e.g. `amount = qty * rate`) live as cells edit.
final _rowFormulaEvaluator = ExpressionEvaluator();

/// Recomputes every formula field in [row] (in place) from its
/// `formulaExpression`, evaluated against the row's own values — e.g. a child
/// table's `amount = qty * rate`. A formula that can't evaluate yet (a missing
/// operand) leaves its field untouched. Public so it can be unit-tested.
void applyRowFormulas(
  Iterable<FieldDefinition> fields,
  Map<String, dynamic> row, {
  ExpressionEvaluator? evaluator,
}) {
  final ev = evaluator ?? _rowFormulaEvaluator;
  for (final f in fields) {
    final expr = f.formulaExpression;
    if (expr == null || expr.isEmpty) continue;
    try {
      row[f.key] = ev.evaluateValue(expr, EvaluationContext(fields: row));
    } catch (_) {
      // Operand not ready (e.g. rate still blank) — leave as-is.
    }
  }
}

/// Marker passed down to every shared input wrapper inside a
/// child-table data cell. The cell consumer reads it through
/// [ChildTableContext.isInline] and suppresses the field's external
/// `labelText` — the column header already carries the label, and a
/// floating Material label would eat horizontal space and collapse the
/// cell into unreadable per-character columns.
///
/// Mirrors the Swift fix in `mercantisInput()` from PR #121: strip the
/// platform-default label/chrome inside child-table cells.
class ChildTableContext extends InheritedWidget {
  const ChildTableContext({
    super.key,
    required this.inline,
    required super.child,
  });

  /// `true` while building a widget inside a child-table data cell.
  final bool inline;

  static bool isInline(BuildContext context) {
    final ctx = context.dependOnInheritedWidgetOfExactType<ChildTableContext>();
    return ctx?.inline ?? false;
  }

  @override
  bool updateShouldNotify(ChildTableContext oldWidget) =>
      inline != oldWidget.inline;
}

/// Shared horizontal padding between header label cells and data cells.
/// Header and rows MUST use the same value — Swift PR #125 was a regression
/// caused by header using 10pt and rows using 8pt, leaving every column
/// visibly misaligned. One source of truth eliminates the drift.
const double kChildTableCellHPadding = 8.0;

const double _kIndexCellWidth = 36;
const double _kTrailingCellWidth = 44;

/// Below this available (pane) width the horizontal-scroll grid is unusable —
/// phones and tablet-portrait can't show enough columns without cramping —
/// so rows collapse to stacked summary cards that open the per-row editor on
/// tap. At or above it the grid expands to fill the pane (desktop and
/// tablet-landscape). Measured on the field's own constraints, not the screen,
/// so it does the right thing inside a narrow split pane too.
const double _kCardModeMaxWidth = 720;

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
/// [FieldDefinition.defaultValue] is always a String; coerce it to the column's
/// runtime type so a newly added child row starts with proper typed values
/// (numbers/booleans), not strings — both for display casts and so the row
/// flows into ledger derivation as numbers. Falls back to the raw string when
/// it can't be parsed.
dynamic coerceChildDefault(FieldType type, String raw) {
  switch (type) {
    case FieldType.integer:
      return int.tryParse(raw) ?? raw;
    case FieldType.float:
    case FieldType.currency:
    case FieldType.percent:
      return num.tryParse(raw) ?? raw;
    case FieldType.check:
      return raw == '1' || raw.toLowerCase() == 'true';
    default:
      return raw;
  }
}

class ChildTableField extends StatefulWidget {
  const ChildTableField({
    super.key,
    required this.field,
    required this.childDocType,
    required this.rows,
    required this.readOnly,
    required this.onChanged,
    this.linkSearchProvider,
    this.linkTargetResolver,
  });

  final ResolvedFieldDefinition field;
  final DocType? childDocType;
  final List<Map<String, dynamic>> rows;
  final bool readOnly;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  /// Threaded through to link-type columns so a row's link cell (e.g. a line's
  /// Item) is a real picker, not a raw-id text box. Both optional — the picker
  /// falls back to `engine.list(targetDocType)` and a title-key heuristic.
  final LinkSearchProvider? linkSearchProvider;
  final DocType? Function(String docTypeId)? linkTargetResolver;

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
      final d = f.defaultValue;
      if (d != null) blank[f.key] = coerceChildDefault(f.type, d);
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
    final minGridWidth = _totalMinWidth(fields);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            // Narrow panes (phones, tablet-portrait) can't show a usable
            // horizontal-scroll grid — fall back to stacked summary cards
            // that open the per-row editor on tap.
            if (available.isFinite && available < _kCardModeMaxWidth) {
              return _buildCards(childType, fields);
            }
            // Wide panes: the grid fills the available width so columns
            // breathe and no space is wasted. Only when the columns' own
            // minimums already overflow the pane do we keep the horizontal
            // scroll (dense tables on tablet-landscape).
            final gridWidth = available.isFinite && available > minGridWidth
                ? available
                : minGridWidth;
            return _buildGrid(theme, fields, childType, gridWidth);
          },
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

  Widget _buildGrid(
    ThemeData theme,
    List<FieldDefinition> fields,
    DocType childType,
    double gridWidth,
  ) {
    return Scrollbar(
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
                    linkSearchProvider: widget.linkSearchProvider,
                    linkTargetResolver: widget.linkTargetResolver,
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
    );
  }

  Widget _buildCards(DocType childType, List<FieldDefinition> fields) {
    if (widget.rows.isEmpty) {
      return const _EmptyRow(width: double.infinity);
    }
    final amount = _amountField(fields);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        for (var i = 0; i < widget.rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RowCard(
              fields: fields,
              amountField: amount,
              rowIndex: i,
              row: widget.rows[i],
              onTap: () => _openRowEditor(childType, i),
            ),
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
                linkSearchProvider: widget.linkSearchProvider,
                linkTargetResolver: widget.linkTargetResolver,
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
                  linkSearchProvider: widget.linkSearchProvider,
                  linkTargetResolver: widget.linkTargetResolver,
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

/// A key that reads like a line quantity — used to give float qty fields the
/// same − / + stepper the integer counts get in the line-item editor.
bool _looksLikeQuantity(String key) {
  final k = key.toLowerCase();
  return k == 'qty' ||
      k.contains('qty') ||
      k.contains('quantity') ||
      k.contains('count') ||
      k.contains('units');
}

bool _isNumeric(FieldType t) =>
    t == FieldType.integer ||
    t == FieldType.float ||
    t == FieldType.currency ||
    t == FieldType.percent;

/// The currency column to feature on the right edge of a summary card:
/// prefer one whose key reads like a line total (`amount`, `total`), else the
/// last currency column, else null. Kept generic so it works for any child
/// DocType (quotation items, delivery lines, journal entries, …).
FieldDefinition? _amountField(List<FieldDefinition> fields) {
  FieldDefinition? lastCurrency;
  for (final f in fields) {
    if (f.type != FieldType.currency) continue;
    lastCurrency = f;
    final k = f.key.toLowerCase();
    if (k.contains('amount') || k.contains('total')) return f;
  }
  return lastCurrency;
}

/// Human title for a summary card — the first non-empty text/link/select
/// value in the row, falling back to the 1-based row number.
String _rowTitle(List<FieldDefinition> fields, Map<String, dynamic> row,
    int index) {
  for (final f in fields) {
    switch (f.type) {
      case FieldType.link:
      case FieldType.dynamicLink:
      case FieldType.data:
      case FieldType.text:
      case FieldType.select:
      case FieldType.autocomplete:
        final v = row[f.key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      default:
        break;
    }
  }
  return 'Row ${index + 1}';
}

/// The compact "Qty 3 · Rate 12.00" driver line under a card title: the row's
/// numeric fields (excluding the featured amount) shown as `Label value`.
String _rowDrivers(List<FieldDefinition> fields, Map<String, dynamic> row,
    FieldDefinition? amount) {
  final parts = <String>[];
  for (final f in fields) {
    if (amount != null && f.key == amount.key) continue;
    if (!_isNumeric(f.type)) continue;
    final v = row[f.key];
    if (v == null) continue;
    parts.add('${f.label} ${_fmtNum(v)}');
    if (parts.length == 3) break;
  }
  return parts.join('  ·  ');
}

/// Trim `3.0` → `3` for driver counts; keep other decimals as-is.
String _fmtNum(dynamic v) {
  if (v is num) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
  return v.toString();
}

/// Featured currency amount, always two decimals (`36` → `36.00`).
String _fmtAmount(num v) => v.toStringAsFixed(2);

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
    this.linkSearchProvider,
    this.linkTargetResolver,
  });

  final List<FieldDefinition> fields;
  final int rowIndex;
  final Map<String, dynamic> row;
  final bool readOnly;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onOpenEditor;
  final LinkSearchProvider? linkSearchProvider;
  final DocType? Function(String docTypeId)? linkTargetResolver;

  void _setCell(String key, dynamic value) {
    final next = Map<String, dynamic>.from(row);
    next[key] = value;
    applyRowFormulas(fields, next);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = rowIndex.isEven
        ? Colors.transparent
        : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4);
    // Inline cells advertise themselves via [ChildTableContext] so any
    // shared input wrapper inside the cell (FieldWidget, future custom
    // pickers, etc.) can suppress its external label and field chrome.
    return ChildTableContext(
      inline: true,
      child: Container(
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
          value: value?.toString() ?? '',
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
          value: value?.toString() ?? '',
          textAlign: TextAlign.end,
          readOnly: readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hint: f.label,
          onChanged: (s) => _setCell(f.key, double.tryParse(s)),
        );
      case FieldType.date:
        return _CellDateField(
          value: value?.toString(),
          readOnly: readOnly,
          onChanged: (s) => _setCell(f.key, s),
        );
      case FieldType.link:
      case FieldType.dynamicLink:
        // A real picker in the cell: search + select the target record (e.g. an
        // Item) and store its id, while showing its name. Dense variant so it
        // sits at cell height without a redundant floating label.
        return LinkPickerField(
          label: f.label,
          targetDocType: f.linkDocType ?? f.options ?? '',
          value: value?.toString(),
          required: f.required,
          readOnly: readOnly,
          onChanged: (v) => _setCell(f.key, v),
          searchProvider: linkSearchProvider,
          targetDocTypeResolver: linkTargetResolver,
          dense: true,
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

/// Stacked summary of a single child row for narrow panes (phone /
/// tablet-portrait). Tapping anywhere opens the per-row editor — the same
/// dialog/sheet the grid's trailing "•••" button uses — so every field stays
/// reachable without a cramped horizontal grid.
class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.fields,
    required this.amountField,
    required this.rowIndex,
    required this.row,
    required this.onTap,
  });

  final List<FieldDefinition> fields;
  final FieldDefinition? amountField;
  final int rowIndex;
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _rowTitle(fields, row, rowIndex);
    final drivers = _rowDrivers(fields, row, amountField);
    final amountVal = amountField == null ? null : row[amountField!.key];
    return Material(
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${rowIndex + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (drivers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          drivers,
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
              if (amountVal is num) ...[
                const SizedBox(width: 8),
                Text(
                  _fmtAmount(amountVal),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
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
    this.linkSearchProvider,
    this.linkTargetResolver,
  });

  final DocType childDocType;
  final int rowIndex;
  final Map<String, dynamic> initial;
  final bool readOnly;
  final ScrollController? scrollController;
  final LinkSearchProvider? linkSearchProvider;
  final DocType? Function(String docTypeId)? linkTargetResolver;

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

  /// Assigns [value] to the draft and re-derives every formula field
  /// (e.g. `amount = qty * rate`) so the row stays consistent as it's edited —
  /// mirroring the grid's live recompute (`_DataRow._setCell`) so the
  /// card-mode editor, now the only edit path on narrow panes, can't save a
  /// stale computed value.
  void _setDraft(String key, dynamic value) {
    setState(() {
      _draft[key] = value;
      applyRowFormulas(widget.childDocType.fields, _draft);
    });
  }

  /// Formula fields are derived, so they're never hand-editable in the editor
  /// (they'd be overwritten by the next recompute anyway); a field- or
  /// form-level read-only flag also locks the control.
  bool _isReadOnly(FieldDefinition f) =>
      widget.readOnly ||
      f.readOnly ||
      (f.formulaExpression != null && f.formulaExpression!.isNotEmpty);

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
        // Grab handle — only in the draggable bottom-sheet variant (phone),
        // where scrollController is supplied; the dialog variant omits it.
        if (widget.scrollController != null)
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
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
                onPressed: () {
                  // Belt-and-suspenders: re-derive once more so the saved row
                  // is consistent regardless of which control last edited it.
                  applyRowFormulas(widget.childDocType.fields, _draft);
                  Navigator.of(context).pop(_RowEditorResult.updated(_draft));
                },
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
    final ro = _isReadOnly(f);
    switch (f.type) {
      case FieldType.check:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _coerceBool(value),
          onChanged: ro ? null : (v) => _setDraft(f.key, v),
        );
      case FieldType.integer:
        // Editable integer counts get the Atlas − / + stepper; derived /
        // read-only integers keep the plain (re-keying) read-only field so a
        // recomputed value still refreshes.
        if (!ro) {
          return AtlasQuantityStepper(
            label: f.label,
            required: f.required,
            value: value is num ? value : num.tryParse(value?.toString() ?? ''),
            min: 0,
            onChanged: (v) => _setDraft(f.key, v.toInt()),
          );
        }
        return TextFormField(
          key: ValueKey('int_${f.key}_${ro ? value ?? "" : "edit"}'),
          initialValue: value?.toString() ?? '',
          decoration: decoration,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.end,
          readOnly: ro,
          onChanged: ro ? null : (s) => _setDraft(f.key, int.tryParse(s)),
        );
      case FieldType.float:
      case FieldType.currency:
      case FieldType.percent:
        // A float that reads like a quantity (e.g. a fractional qty) also gets
        // the stepper; money (currency) and percent stay plain numeric fields.
        if (!ro && f.type == FieldType.float && _looksLikeQuantity(f.key)) {
          return AtlasQuantityStepper(
            label: f.label,
            required: f.required,
            value: value is num ? value : num.tryParse(value?.toString() ?? ''),
            min: 0,
            decimals: 2,
            onChanged: (v) => _setDraft(f.key, v.toDouble()),
          );
        }
        return TextFormField(
          key: ValueKey('num_${f.key}_${ro ? value ?? "" : "edit"}'),
          initialValue: value?.toString() ?? '',
          decoration: decoration.copyWith(
            suffixText: f.type == FieldType.percent ? '%' : null,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.end,
          readOnly: ro,
          onChanged: ro ? null : (s) => _setDraft(f.key, double.tryParse(s)),
        );
      case FieldType.date:
        return TextFormField(
          key: ValueKey('date_${f.key}_${value ?? ""}'),
          initialValue: value?.toString() ?? '',
          decoration: decoration.copyWith(
            suffixIcon: ro
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
                        _setDraft(
                            f.key, DateFormat('yyyy-MM-dd').format(picked));
                      }
                    },
                  ),
          ),
          readOnly: ro,
          // Manual typing assigns without a rebuild so the cursor isn't reset
          // mid-entry; formulas are re-derived on the next edit and at Done.
          onChanged: ro ? null : (s) => _draft[f.key] = s,
        );
      case FieldType.longText:
        return TextFormField(
          initialValue: value as String? ?? '',
          decoration: decoration,
          maxLines: 5,
          readOnly: ro,
          onChanged: ro ? null : (s) => _draft[f.key] = s,
        );
      case FieldType.select:
        final opts =
            (f.options ?? '').split('\n').where((o) => o.isNotEmpty).toList();
        return DropdownButtonFormField<String>(
          initialValue: value as String?,
          decoration: decoration,
          items: opts
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: ro ? null : (v) => _setDraft(f.key, v),
        );
      case FieldType.link:
      case FieldType.dynamicLink:
        // Full picker: search + select the target record (e.g. a line's Item).
        return LinkPickerField(
          label: f.label,
          targetDocType: f.linkDocType ?? f.options ?? '',
          value: value as String?,
          required: f.required,
          readOnly: ro,
          onChanged: (v) => _setDraft(f.key, v),
          searchProvider: widget.linkSearchProvider,
          targetDocTypeResolver: widget.linkTargetResolver,
        );
      default:
        return TextFormField(
          initialValue: value?.toString() ?? '',
          decoration: decoration,
          readOnly: ro,
          onChanged: ro ? null : (s) => _draft[f.key] = s,
        );
    }
  }
}
