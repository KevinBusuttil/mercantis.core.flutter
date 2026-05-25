import 'package:flutter/material.dart';
import '../theme/tokens/radius.dart';
import '../theme/tokens/spacing.dart';

class ErpDataColumn {
  const ErpDataColumn({
    required this.label,
    this.flex = 1,
    this.numeric = false,
    this.width,
  });

  final String label;
  final int flex;
  final bool numeric;
  final double? width;
}

class ErpDataRow {
  const ErpDataRow({required this.cells, this.onTap, this.selected = false});
  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool selected;
}

/// Touch-friendly dense table for ERP grids (items, ledger lines, etc.).
/// Renders as a card with header + scrollable body.
class ErpDataTable extends StatelessWidget {
  const ErpDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.rowHeight = 48,
    this.headerHeight = 40,
  });

  final List<ErpDataColumn> columns;
  final List<ErpDataRow> rows;
  final double rowHeight;
  final double headerHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget buildHeader() {
      return Container(
        height: headerHeight,
        color: cs.surfaceContainerLow,
        padding: const EdgeInsets.symmetric(horizontal: MercantisSpacing.md),
        child: Row(
          children: [
            for (final c in columns)
              _cell(
                column: c,
                child: Text(
                  c.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: MercantisRadius.rLg,
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildHeader(),
          for (var i = 0; i < rows.length; i++)
            InkWell(
              onTap: rows[i].onTap,
              child: Container(
                height: rowHeight,
                color: rows[i].selected ? cs.primaryContainer.withValues(alpha: 0.3) : null,
                padding: const EdgeInsets.symmetric(horizontal: MercantisSpacing.md),
                child: Row(
                  children: [
                    for (var j = 0; j < columns.length; j++)
                      _cell(
                        column: columns[j],
                        child: DefaultTextStyle(
                          style: theme.textTheme.bodyMedium ?? const TextStyle(),
                          child: j < rows[i].cells.length
                              ? rows[i].cells[j]
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell({required ErpDataColumn column, required Widget child}) {
    final aligned = Align(
      alignment: column.numeric ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    if (column.width != null) {
      return SizedBox(width: column.width, child: aligned);
    }
    return Expanded(flex: column.flex, child: aligned);
  }
}
