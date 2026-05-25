import 'package:flutter/material.dart';
import '../theme/tokens/radius.dart';
import '../theme/tokens/spacing.dart';

class TimelineEntry {
  const TimelineEntry({
    required this.title,
    required this.timestamp,
    this.subtitle,
    this.actor,
    this.icon,
    this.tone,
  });

  final String title;
  final String timestamp;
  final String? subtitle;
  final String? actor;
  final IconData? icon;
  final Color? tone;
}

class DocumentTimelinePanel extends StatelessWidget {
  const DocumentTimelinePanel({
    super.key,
    this.title = 'Timeline',
    required this.entries,
    this.emptyMessage = 'No activity yet',
  });

  final String title;
  final List<TimelineEntry> entries;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surface,
      child: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: MercantisSpacing.lg),
          if (entries.isEmpty)
            Text(emptyMessage, style: theme.textTheme.bodySmall)
          else
            for (var i = 0; i < entries.length; i++)
              _Entry(
                entry: entries[i],
                isLast: i == entries.length - 1,
              ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry, required this.isLast});
  final TimelineEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = entry.tone ?? cs.primary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.15),
                  borderRadius: MercantisRadius.rPill,
                ),
                alignment: Alignment.center,
                child: Icon(entry.icon ?? Icons.circle, size: 14, color: tone),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: cs.outlineVariant),
                ),
            ],
          ),
          const SizedBox(width: MercantisSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : MercantisSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(entry.subtitle!, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (entry.actor != null) entry.actor!,
                      entry.timestamp,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
