import 'package:flutter/material.dart';
import '../theme/tokens/spacing.dart';
import '../widgets/status_chip.dart';

class DocumentDetailPane extends StatelessWidget {
  const DocumentDetailPane({
    super.key,
    required this.title,
    this.subtitle,
    this.statusLabel,
    this.statusTone,
    this.actions = const [],
    this.tabs = const [],
    this.tabViews = const [],
    required this.child,
  }) : assert(tabs.length == tabViews.length);

  final String title;
  final String? subtitle;
  final String? statusLabel;
  final StatusTone? statusTone;
  final List<Widget> actions;
  final List<String> tabs;
  final List<Widget> tabViews;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTabs = tabs.isNotEmpty;
    final body = hasTabs
        ? DefaultTabController(
            length: tabs.length,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final t in tabs) Tab(text: t)],
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(children: tabViews),
                ),
              ],
            ),
          )
        : child;

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MercantisSpacing.xl, MercantisSpacing.lg,
              MercantisSpacing.xl, MercantisSpacing.lg,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: theme.textTheme.headlineSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (statusLabel != null) ...[
                            const SizedBox(width: MercantisSpacing.md),
                            StatusChip(
                              label: statusLabel!,
                              tone: statusTone ?? StatusTone.neutral,
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
                if (actions.isNotEmpty)
                  Wrap(
                    spacing: MercantisSpacing.sm,
                    children: actions,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
