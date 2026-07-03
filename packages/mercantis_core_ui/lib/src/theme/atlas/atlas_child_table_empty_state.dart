import 'package:flutter/material.dart';

import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import 'atlas_colors.dart';

/// The empty state for a child table (line items, taxes, allocations, …) — a
/// compact, business-worded placeholder with a clear add action, replacing the
/// generic "No rows yet." + "Add Row". Sized to sit *inside* a form section
/// (smaller than the full-page [EmptyState]).
///
/// The caller derives [title] / [addLabel] from the table's own label so the
/// copy reads in business terms ("No Items yet" · "Add Item") without this
/// component hard-coding any doctype.
class AtlasChildTableEmptyState extends StatelessWidget {
  const AtlasChildTableEmptyState({
    super.key,
    required this.title,
    this.message,
    this.addLabel,
    this.onAdd,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String? message;

  /// The add-action label (e.g. "Add Item"). The button shows only when both
  /// [addLabel] and [onAdd] are set (i.e. an editable table).
  final String? addLabel;
  final VoidCallback? onAdd;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atlas = AtlasColors.of(context);
    final showAdd = addLabel != null && onAdd != null;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MercantisSpacing.lg,
        vertical: MercantisSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: atlas.primarySoft,
              borderRadius: MercantisRadius.rMd,
            ),
            child: Icon(icon, size: 22, color: atlas.primary),
          ),
          const SizedBox(height: MercantisSpacing.md),
          Text(
            title,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          if ((message ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              style: theme.textTheme.bodySmall?.copyWith(color: atlas.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
          if (showAdd) ...[
            const SizedBox(height: MercantisSpacing.md),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(addLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
