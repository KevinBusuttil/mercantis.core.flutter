import 'package:flutter/material.dart';

import '../tokens/spacing.dart';
import 'atlas_colors.dart';

/// A sticky footer for a bottom sheet / dialog with up to three slots:
/// a destructive action on the left, and a secondary + primary pair on the
/// right. The primary is the strongest affordance (a filled button); the
/// destructive uses the error colour. One shared bar so every Atlas sheet
/// footer has the same layout, spacing and emphasis instead of three
/// hand-rolled variants.
class AtlasBottomActionBar extends StatelessWidget {
  const AtlasBottomActionBar({
    super.key,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.destructiveLabel,
    this.onDestructive,
    this.busy = false,
  });

  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? destructiveLabel;
  final VoidCallback? onDestructive;

  /// When true the primary shows a spinner and all actions are disabled — for
  /// an in-flight save.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final atlas = AtlasColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MercantisSpacing.lg,
        vertical: 10,
      ),
      child: Row(
        children: [
          if (destructiveLabel != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: atlas.danger),
              onPressed: busy ? null : onDestructive,
              child: Text(destructiveLabel!),
            ),
          const Spacer(),
          if (secondaryLabel != null) ...[
            TextButton(
              onPressed: busy ? null : onSecondary,
              child: Text(secondaryLabel!),
            ),
            const SizedBox(width: MercantisSpacing.sm),
          ],
          if (primaryLabel != null)
            FilledButton(
              onPressed: busy ? null : onPrimary,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(primaryLabel!),
            ),
        ],
      ),
    );
  }
}
