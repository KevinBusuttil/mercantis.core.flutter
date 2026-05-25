import 'package:flutter/material.dart';
import '../theme/tokens/radius.dart';
import '../theme/tokens/spacing.dart';
import '../workspace/quick_action.dart';

class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.action,
    required this.onTap,
    this.accentColor,
  });

  final QuickAction action;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = action.color ?? accentColor ?? cs.primary;

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
          padding: const EdgeInsets.all(MercantisSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: MercantisRadius.rMd,
                ),
                child: Icon(action.icon, color: accent, size: 22),
              ),
              const SizedBox(height: MercantisSpacing.md),
              Text(
                action.label,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (action.description != null) ...[
                const SizedBox(height: 2),
                Text(
                  action.description!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
