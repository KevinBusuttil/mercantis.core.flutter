import 'package:flutter/material.dart';

/// Small, quiet field label with a red required asterisk hidden from a11y
/// (a semantic "<label>, required" is announced instead). The single label
/// used across every Atlas surface — the field rows, the quantity stepper, the
/// link picker, and (via [AtlasLabel.inheritStyle]) the Material floating-label
/// / heading contexts — so required fields announce identically everywhere.
class AtlasLabel extends StatelessWidget {
  /// The default row label: the quiet `labelMedium` treatment.
  const AtlasLabel({super.key, required this.label, this.required = false})
      : style = null,
        _inheritStyle = false;

  /// A label that inherits the ambient text style (merged with [style]) rather
  /// than imposing `labelMedium` — for an `InputDecoration.label` floating
  /// label or a heading, where the caller/theme owns the type.
  const AtlasLabel.inheritStyle({
    super.key,
    required this.label,
    this.required = false,
    this.style,
  }) : _inheritStyle = true;

  final String label;
  final bool required;
  final TextStyle? style;
  final bool _inheritStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = _inheritStyle
        ? DefaultTextStyle.of(context).style.merge(style)
        : (theme.textTheme.labelMedium ?? const TextStyle())
            .copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Semantics(
      label: required ? '$label, required' : label,
      excludeSemantics: true,
      child: RichText(
        text: TextSpan(
          style: base,
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
