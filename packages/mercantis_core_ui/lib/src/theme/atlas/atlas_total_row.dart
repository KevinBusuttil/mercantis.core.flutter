import 'package:flutter/material.dart';

import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'atlas_colors.dart';

/// A read-only "money" row for a form summary — label on the left, value on the
/// right in tabular figures. The [emphasize] variant (a document's grand total)
/// uses a tinted block in the accent colour so the bottom line reads at a
/// glance, per the Atlas "strong totals" rule.
class AtlasTotalRow extends StatelessWidget {
  const AtlasTotalRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atlas = AtlasColors.of(context);
    final valueStyle =
        (emphasize ? theme.textTheme.titleMedium : theme.textTheme.titleSmall)
            ?.copyWith(
      color: emphasize ? atlas.primary : atlas.textPrimary,
      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
      fontFeatures: MercantisTypography.tabularFigures,
    );
    final labelStyle =
        (emphasize ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
            ?.copyWith(
      color: emphasize ? atlas.primary : atlas.textSecondary,
      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
    );
    return Container(
      decoration: BoxDecoration(
        color: emphasize ? atlas.primary.withValues(alpha: 0.10) : atlas.surface,
        borderRadius: MercantisRadius.rMd,
        border: Border.all(
          color: emphasize
              ? atlas.primary.withValues(alpha: 0.28)
              : atlas.borderSoft,
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: MercantisSpacing.md, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          const SizedBox(width: MercantisSpacing.sm),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}
