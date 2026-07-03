import 'package:flutter/material.dart';

import '../tokens/spacing.dart';
import 'atlas_colors.dart';

/// Groups a form's money-total rows into one distinct, raised card that reads
/// as the document's bottom line. Designed to be pinned at the foot of the
/// form (a sticky totals bar): a top divider + soft upward shadow lift it off
/// the scrolling field area, and its own tinted surface sets it apart from the
/// ordinary section cards. Content taller than [maxHeightFactor] of the
/// available height scrolls inside the card so it can never swallow the form.
class AtlasSummaryCard extends StatelessWidget {
  const AtlasSummaryCard({
    super.key,
    this.title,
    required this.children,
    this.maxHeightFactor = 0.45,
  });

  /// Small header above the rows (e.g. the totals section name). Hidden when
  /// null/blank.
  final String? title;
  final List<Widget> children;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atlas = AtlasColors.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((title ?? '').trim().isNotEmpty) ...[
          Text(
            title!.trim().toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: atlas.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: MercantisSpacing.sm),
        ],
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: MercantisSpacing.sm),
          children[i],
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight * maxHeightFactor
            : double.infinity;
        return Container(
          decoration: BoxDecoration(
            color: atlas.surfaceElevated,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(
            MercantisSpacing.lg,
            MercantisSpacing.md,
            MercantisSpacing.lg,
            MercantisSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(child: content),
          ),
        );
      },
    );
  }
}
