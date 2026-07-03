import 'package:flutter/material.dart';

/// A titled group of Atlas field rows — the section container for a document
/// form (Customer & Dates, Items, Totals, …). A small uppercase caption sits
/// above a stroked card; the stroke alone carries the grouping since the sheet
/// surface shows through directly (no muted backdrop), matching the HIG sheet
/// pattern. Extracted from the form view so any screen can group Atlas rows the
/// same way.
class AtlasSectionCard extends StatelessWidget {
  const AtlasSectionCard({
    super.key,
    required this.name,
    required this.child,
    this.containsTable = false,
  });

  /// Section caption; hidden when blank.
  final String name;

  /// A child-table section gets tighter padding (the grid supplies its own).
  final bool containsTable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: theme.colorScheme.outline.withValues(alpha: 0.6),
      ),
    );
    final showTitle = name.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              name.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Material(
          color: theme.colorScheme.surface,
          shape: cardShape,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: containsTable
                ? const EdgeInsets.all(4)
                : const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: child,
          ),
        ),
      ],
    );
  }
}
