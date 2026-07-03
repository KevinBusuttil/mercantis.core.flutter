import 'package:flutter/material.dart';
import '../theme/tokens/spacing.dart';

/// The Neuradix Atlas empty state: a calm, centred placeholder for an empty
/// list, table, inbox or search result. A soft tinted circle carries a single
/// icon, above a short title, an optional supporting line, and an optional
/// action. This is the one shared empty state — every list/table/search screen
/// renders through it, so the look stays consistent app-wide.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Soft tinted disc + primary glyph — the Atlas icon-chip language,
              // scaled up for a full-panel placeholder.
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 34, color: cs.primary),
              ),
              const SizedBox(height: MercantisSpacing.lg),
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: MercantisSpacing.sm),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: MercantisSpacing.xl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
