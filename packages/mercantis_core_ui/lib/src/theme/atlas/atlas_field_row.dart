import 'package:flutter/material.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../tokens/radius.dart';
import '../tokens/spacing.dart';

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
    final cs = theme.colorScheme;
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
            color: hasValue ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        );

    final trailingWidget = trailing ??
        (onTap != null && !readOnly
            ? Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.6))
            : null);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          _AtlasIconChip(icon: icon!),
          const SizedBox(width: MercantisSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AtlasLabel(label: label, required: required),
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
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: MercantisRadius.rMd,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
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

/// A read-only "money" row for a form summary — label on the left, value on the
/// right in tabular figures. The [emphasize] variant (a document's grand total)
/// uses a tinted block in the accent colour so the bottom line reads at a
/// glance, per the Atlas "strong totals" rule.
class AtlasTotalRow extends StatelessWidget {
  const AtlasTotalRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final valueStyle =
        (emphasize ? theme.textTheme.titleMedium : theme.textTheme.titleSmall)
            ?.copyWith(
      color: emphasize ? cs.primary : cs.onSurface,
      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final labelStyle =
        (emphasize ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
            ?.copyWith(
      color: emphasize ? cs.primary : cs.onSurfaceVariant,
      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
    );
    return Container(
      decoration: BoxDecoration(
        color: emphasize
            ? cs.primary.withValues(alpha: 0.10)
            : cs.surfaceContainerLowest,
        borderRadius: MercantisRadius.rMd,
        border: Border.all(
          color: emphasize
              ? cs.primary.withValues(alpha: 0.28)
              : cs.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: MercantisSpacing.md, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          const SizedBox(width: MercantisSpacing.sm),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

/// Groups a form's money-total rows into one distinct, raised card that reads
/// as the document's bottom line. Designed to be pinned at the foot of the
/// form (a sticky totals bar): a top divider + soft upward shadow lift it off
/// the scrolling field area, and its own tinted surface sets it apart from the
/// ordinary section cards. Content taller than [maxHeightFactor] of the
/// available height scrolls inside the card so it can never swallow the form.
class AtlasSummaryCard extends StatelessWidget {
  const AtlasSummaryCard({
    super.key,
    this.title,
    required this.children,
    this.maxHeightFactor = 0.45,
  });

  /// Small header above the rows (e.g. the totals section name). Hidden when
  /// null/blank.
  final String? title;
  final List<Widget> children;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((title ?? '').trim().isNotEmpty) ...[
          Text(
            title!.trim().toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: MercantisSpacing.sm),
        ],
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: MercantisSpacing.sm),
          children[i],
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight * maxHeightFactor
            : double.infinity;
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.8)),
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(
            MercantisSpacing.lg,
            MercantisSpacing.md,
            MercantisSpacing.lg,
            MercantisSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(child: content),
          ),
        );
      },
    );
  }
}

/// The tinted 36×36 rounded-square that carries a field row's leading glyph.
class _AtlasIconChip extends StatelessWidget {
  const _AtlasIconChip({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: MercantisRadius.rMd,
      ),
      child: Icon(icon, size: 18, color: cs.primary),
    );
  }
}

/// Small, quiet field label with a red required asterisk hidden from a11y
/// (a semantic "<label>, required" is announced instead).
class _AtlasLabel extends StatelessWidget {
  const _AtlasLabel({required this.label, required this.required});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.labelMedium ?? const TextStyle();
    return Semantics(
      label: required ? '$label, required' : label,
      excludeSemantics: true,
      child: RichText(
        text: TextSpan(
          style: base.copyWith(color: theme.colorScheme.onSurfaceVariant),
          children: [
            TextSpan(text: label),
            if (required)
              TextSpan(
                text: ' *',
                style: base.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Chooses a leading glyph for a field row. Prefers a match on the field's key
/// (so common ERP fields read at a glance), then falls back to the field type.
/// Returns null when nothing meaningful fits — the row then renders chip-less.
IconData? atlasFieldIcon(FieldDefinition field) {
  final k = field.key.toLowerCase();
  bool has(String s) => k.contains(s);

  if (has('customer') || has('contact') || has('lead') || has('party')) {
    return Icons.person_outline;
  }
  if (has('supplier') || has('vendor')) return Icons.local_shipping_outlined;
  if (has('item') || has('product')) return Icons.inventory_2_outlined;
  if (has('warehouse')) return Icons.warehouse_outlined;
  if (has('currency')) return Icons.attach_money;
  if (has('tax')) return Icons.percent;
  if (has('account') || has('ledger')) return Icons.account_balance_outlined;
  if (has('cost_center') || has('cost centre')) return Icons.hub_outlined;
  if (has('company')) return Icons.business_outlined;
  if (has('project')) return Icons.folder_outlined;
  if (has('description') || has('remarks') || has('notes') || has('terms')) {
    return Icons.notes_outlined;
  }

  switch (field.type) {
    case FieldType.date:
    case FieldType.dateTime:
      return Icons.calendar_today_outlined;
    case FieldType.time:
      return Icons.schedule_outlined;
    case FieldType.link:
    case FieldType.dynamicLink:
      return Icons.link_outlined;
    case FieldType.select:
    case FieldType.autocomplete:
      return Icons.expand_more;
    case FieldType.currency:
      return Icons.attach_money;
    case FieldType.percent:
      return Icons.percent;
    default:
      return null;
  }
}
