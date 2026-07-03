import 'package:flutter/material.dart';

import '../tokens/spacing.dart';

/// Opens the Atlas option list as a modal bottom sheet and resolves to the
/// chosen option (or null if dismissed). The one place a `select`-style Atlas
/// row surfaces its choices, so every selector sheet looks the same.
Future<String?> showAtlasOptionSheet(
  BuildContext context, {
  required String title,
  required List<String> options,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (_) =>
        AtlasOptionSheet(title: title, options: options, selected: selected),
  );
}

/// Bottom-sheet list of [options]; pops the chosen value on tap and ticks the
/// currently [selected] one.
class AtlasOptionSheet extends StatelessWidget {
  const AtlasOptionSheet({
    super.key,
    required this.title,
    required this.options,
    this.selected,
  });
  final String title;
  final List<String> options;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MercantisSpacing.lg, 0,
                MercantisSpacing.lg, MercantisSpacing.sm),
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    title: Text(o),
                    trailing: o == selected
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(o),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
