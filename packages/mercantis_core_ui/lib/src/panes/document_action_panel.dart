import 'package:flutter/material.dart';
import '../theme/tokens/spacing.dart';

class DocumentActionGroup {
  const DocumentActionGroup({required this.label, required this.actions});
  final String label;
  final List<Widget> actions;
}

class DocumentActionPanel extends StatelessWidget {
  const DocumentActionPanel({
    super.key,
    this.title = 'Actions',
    required this.groups,
  });

  final String title;
  final List<DocumentActionGroup> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        child: ListView(
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: MercantisSpacing.lg),
            for (final g in groups) ...[
              Text(
                g.label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: MercantisSpacing.sm),
              for (final a in g.actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: MercantisSpacing.sm),
                  child: SizedBox(width: double.infinity, child: a),
                ),
              const SizedBox(height: MercantisSpacing.lg),
            ],
          ],
        ),
      ),
    );
  }
}
