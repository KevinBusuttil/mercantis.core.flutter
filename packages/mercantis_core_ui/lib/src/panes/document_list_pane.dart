import 'package:flutter/material.dart';
import '../theme/tokens/radius.dart';
import '../theme/tokens/spacing.dart';
import '../widgets/status_chip.dart';

class DocumentListPaneRow {
  const DocumentListPaneRow({
    required this.id,
    required this.title,
    this.subtitle,
    this.amount,
    this.statusLabel,
    this.statusTone,
    this.timestamp,
    this.leading,
    this.metadata = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? amount;
  final String? statusLabel;
  final StatusTone? statusTone;
  final String? timestamp;
  final Widget? leading;
  final List<String> metadata;
}

class DocumentListPane extends StatelessWidget {
  const DocumentListPane({
    super.key,
    required this.title,
    required this.rows,
    this.subtitle,
    this.filterChips = const [],
    this.searchHint = 'Search',
    this.onSearchChanged,
    this.onRowTap,
    this.selectedId,
    this.onNew,
    this.newLabel,
    this.trailingActions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> filterChips;
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;
  final List<DocumentListPaneRow> rows;
  final void Function(DocumentListPaneRow)? onRowTap;
  final String? selectedId;
  final VoidCallback? onNew;
  final String? newLabel;
  final List<Widget> trailingActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MercantisSpacing.lg,
              MercantisSpacing.lg,
              MercantisSpacing.lg,
              MercantisSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleLarge),
                    ),
                    ...trailingActions,
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: MercantisSpacing.md),
                TextField(
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: searchHint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                if (filterChips.isNotEmpty) ...[
                  const SizedBox(height: MercantisSpacing.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final c in filterChips) ...[
                        c,
                        const SizedBox(width: MercantisSpacing.xs),
                      ],
                    ]),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child:
                        Text('No documents', style: theme.textTheme.bodySmall),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        vertical: MercantisSpacing.xs),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final selected = row.id == selectedId;
                      return _Row(
                          row: row, selected: selected, onTap: onRowTap);
                    },
                  ),
          ),
          if (onNew != null)
            Padding(
              padding: const EdgeInsets.all(MercantisSpacing.lg),
              child: FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add, size: 18),
                label: Text(newLabel ?? 'New'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.selected, required this.onTap});
  final DocumentListPaneRow row;
  final bool selected;
  final void Function(DocumentListPaneRow)? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Workspace accent (when the surrounding shell paints one onto the
    // theme's primary) doubles as the selection tint, mirroring the
    // sidebar treatment so it's visually obvious which list row drives
    // the detail pane.
    final accent = cs.primary;
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.10) : Colors.transparent,
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(row),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MercantisSpacing.lg,
              vertical: MercantisSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Leading accent bar — 3 px stripe that signals the
                // active row at a glance. Always present so non-selected
                // rows still align horizontally with the selected one.
                Container(
                  width: 3,
                  margin: const EdgeInsets.only(
                    right: MercantisSpacing.md,
                    top: 2,
                    bottom: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                if (row.leading != null) ...[
                  row.leading!,
                  const SizedBox(width: MercantisSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: selected ? accent : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (row.amount != null)
                            Text(
                              row.amount!,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      if (row.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          row.subtitle!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (row.statusLabel != null ||
                          row.timestamp != null ||
                          row.metadata.isNotEmpty) ...[
                        const SizedBox(height: MercantisSpacing.sm),
                        Wrap(
                          spacing: MercantisSpacing.sm,
                          runSpacing: MercantisSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (row.statusLabel != null)
                              StatusChip(
                                label: row.statusLabel!,
                                tone: row.statusTone ?? StatusTone.neutral,
                                dense: true,
                              ),
                            for (final m in row.metadata)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: MercantisRadius.rPill,
                                ),
                                child: Text(
                                  m,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            if (row.timestamp != null)
                              Text(row.timestamp!,
                                  style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
