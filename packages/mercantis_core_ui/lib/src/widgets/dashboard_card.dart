import 'package:flutter/material.dart';
import '../theme/atlas/atlas_icon_chip.dart';
import '../theme/tokens/radius.dart';
import '../theme/tokens/spacing.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.accentColor,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.all(MercantisSpacing.lg),
    required this.child,
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color? accentColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Widget child;

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
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null || icon != null)
                Row(
                  children: [
                    if (icon != null)
                      AtlasIconChip(
                        icon: icon!,
                        accent: accent,
                        size: 36,
                        radius: MercantisRadius.rMd,
                        iconSize: 20,
                      ),
                    if (icon != null && title != null)
                      const SizedBox(width: MercantisSpacing.md),
                    if (title != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title!,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    if (trailing != null) trailing!,
                  ],
                ),
              if (title != null || icon != null)
                const SizedBox(height: MercantisSpacing.md),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
