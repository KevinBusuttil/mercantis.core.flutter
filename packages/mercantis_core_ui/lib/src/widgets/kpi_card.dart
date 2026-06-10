import 'package:flutter/material.dart';
import '../theme/tokens/radius.dart';
import '../theme/tokens/spacing.dart';

enum KpiTrend { up, down, flat }

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.accentColor,
    this.trend,
    this.trendLabel,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? accentColor;
  final KpiTrend? trend;
  final String? trendLabel;
  final VoidCallback? onTap;

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
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: MercantisRadius.rSm,
                      ),
                      child: Icon(icon, color: accent, size: 18),
                    ),
                  if (icon != null) const SizedBox(width: MercantisSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MercantisSpacing.md),
              Text(
                value,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              if (trend != null || subtitle != null) ...[
                const SizedBox(height: MercantisSpacing.xs),
                Row(
                  children: [
                    if (trend != null) ...[
                      Icon(_trendIcon(trend!), size: 14, color: _trendColor(trend!, cs)),
                      const SizedBox(width: 4),
                      Text(
                        trendLabel ?? _trendDefaultLabel(trend!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _trendColor(trend!, cs),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text('  ·  ', style: theme.textTheme.bodySmall),
                    ],
                    if (subtitle != null)
                      Expanded(
                        child: Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static IconData _trendIcon(KpiTrend t) => switch (t) {
        KpiTrend.up => Icons.trending_up,
        KpiTrend.down => Icons.trending_down,
        KpiTrend.flat => Icons.trending_flat,
      };

  static Color _trendColor(KpiTrend t, ColorScheme cs) => switch (t) {
        KpiTrend.up => const Color(0xFF22C55E),
        KpiTrend.down => const Color(0xFFEF4444),
        KpiTrend.flat => cs.onSurfaceVariant,
      };

  static String _trendDefaultLabel(KpiTrend t) => switch (t) {
        KpiTrend.up => 'Up',
        KpiTrend.down => 'Down',
        KpiTrend.flat => 'Flat',
      };
}
