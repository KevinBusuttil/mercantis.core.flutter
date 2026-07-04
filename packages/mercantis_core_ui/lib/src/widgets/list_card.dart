import 'package:flutter/material.dart';
import '../theme/atlas/atlas_icon_chip.dart';
import '../theme/tokens/radius.dart';
import '../theme/tokens/spacing.dart';

class ListCardRow {
  const ListCardRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
}

class ListCard extends StatelessWidget {
  const ListCard({
    super.key,
    required this.title,
    required this.rows,
    this.subtitle,
    this.icon,
    this.accentColor,
    this.trailing,
    this.onSeeAll,
    this.emptyLabel = 'Nothing here yet',
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? accentColor;
  final Widget? trailing;
  final VoidCallback? onSeeAll;
  final List<ListCardRow> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = accentColor ?? cs.primary;

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: MercantisRadius.rLg,
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MercantisSpacing.lg, MercantisSpacing.lg,
              MercantisSpacing.sm, MercantisSpacing.sm,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  AtlasIconChip(
                    icon: icon!,
                    accent: accent,
                    size: 32,
                    radius: MercantisRadius.rSm,
                    iconSize: 18,
                  ),
                  const SizedBox(width: MercantisSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (subtitle != null)
                        Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
                if (onSeeAll != null)
                  TextButton(onPressed: onSeeAll, child: const Text('See all')),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(MercantisSpacing.lg),
              child: Text(emptyLabel, style: theme.textTheme.bodySmall),
            )
          else
            ...rows.map((r) => _ListCardRow(row: r)),
          const SizedBox(height: MercantisSpacing.xs),
        ],
      ),
    );
  }
}

class _ListCardRow extends StatelessWidget {
  const _ListCardRow({required this.row});
  final ListCardRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: row.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MercantisSpacing.lg,
          vertical: MercantisSpacing.md,
        ),
        child: Row(
          children: [
            if (row.leading != null) ...[
              row.leading!,
              const SizedBox(width: MercantisSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    row.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (row.subtitle != null)
                    Text(
                      row.subtitle!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (row.trailing != null) ...[
              const SizedBox(width: MercantisSpacing.md),
              row.trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
