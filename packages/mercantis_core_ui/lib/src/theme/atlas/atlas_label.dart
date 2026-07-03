import 'package:flutter/material.dart';

/// Small, quiet field label with a red required asterisk hidden from a11y
/// (a semantic "<label>, required" is announced instead). Shared by every
/// Atlas row so the form, the quantity stepper and the link picker announce
/// required fields identically (consolidating three earlier copies).
class AtlasLabel extends StatelessWidget {
  const AtlasLabel({super.key, required this.label, this.required = false});
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
