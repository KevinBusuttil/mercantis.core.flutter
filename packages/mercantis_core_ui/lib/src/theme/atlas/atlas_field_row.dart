import 'package:flutter/material.dart';

import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import 'atlas_colors.dart';
import 'atlas_icon_chip.dart';
import 'atlas_label.dart';

/// A single form field rendered as a calm, mobile-first **list row** — the core
/// primitive of the Neuradix Atlas design direction. Replaces the heavy
/// outlined input box with: a tinted leading icon to scan by, a small quiet
/// label, and a large readable value; a trailing chevron signals "tap to pick".
///
/// It is presentation only — the value editor / picker is supplied by the
/// caller as [child] (for inline editing) or as [value] + [onTap] (for a
/// tap-to-open selector). Behaviour, validation and `onChanged` stay in the
/// caller, so this is a skin, not a rewrite.
class AtlasFieldRow extends StatelessWidget {
  const AtlasFieldRow({
    super.key,
    this.icon,
    required this.label,
    this.required = false,
    this.value,
    this.placeholder,
    this.child,
    this.onTap,
    this.trailing,
    this.readOnly = false,
  });

  /// Leading glyph shown in a tinted rounded square. Omitted entirely when
  /// null — the design rule is "one meaningful icon, or none".
  final IconData? icon;
  final String label;
  final bool required;

  /// Resolved value text for a selector row. Empty/null shows [placeholder]
  /// in a muted tone. Ignored when [child] is supplied.
  final String? value;
  final String? placeholder;

  /// A custom value widget (e.g. an inline editor). Overrides [value].
  final Widget? child;

  /// When set (and not [readOnly]) the whole row is tappable and, unless
  /// [trailing] is given, shows a chevron.
  final VoidCallback? onTap;

  /// Overrides the chevron — e.g. a [Switch] for a boolean field.
  final Widget? trailing;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atlas = AtlasColors.of(context);
    final hasValue = (value ?? '').trim().isNotEmpty;
    // Toggle rows (a trailing switch, no editor/value) render label-only.
    final showValue =
        child != null || hasValue || (placeholder ?? '').isNotEmpty;

    final valueWidget = child ??
        Text(
          hasValue ? value!.trim() : (placeholder ?? ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: hasValue ? atlas.textPrimary : atlas.textMuted,
          ),
        );

    final trailingWidget = trailing ??
        (onTap != null && !readOnly
            ? Icon(Icons.chevron_right,
                size: 20, color: atlas.textSecondary.withValues(alpha: 0.6))
            : null);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          AtlasIconChip(icon: icon!),
          const SizedBox(width: MercantisSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AtlasLabel(label: label, required: required),
              if (showValue) const SizedBox(height: 2),
              if (showValue) valueWidget,
            ],
          ),
        ),
        if (trailingWidget != null) ...[
          const SizedBox(width: MercantisSpacing.sm),
          trailingWidget,
        ],
      ],
    );

    return Material(
      color: atlas.surface,
      shape: RoundedRectangleBorder(
        borderRadius: MercantisRadius.rMd,
        side: BorderSide(color: atlas.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: readOnly ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MercantisSpacing.md,
            vertical: 10,
          ),
          child: row,
        ),
      ),
    );
  }
}
