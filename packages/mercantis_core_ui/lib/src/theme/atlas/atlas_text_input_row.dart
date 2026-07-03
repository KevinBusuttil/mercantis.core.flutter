import 'package:flutter/material.dart';

import 'atlas_field_row.dart';
import 'atlas_text_field_editor.dart';

/// Borderless decoration so an inline editor reads as an Atlas row's *value*
/// rather than an outlined box — the row already supplies the card, label and
/// padding. Shared by every editable Atlas row (text, money, …).
InputDecoration atlasInlineDecoration(
  BuildContext context, {
  String? hintText,
  String? prefixText,
  String? suffixText,
}) {
  return InputDecoration(
    isCollapsed: true,
    border: InputBorder.none,
    contentPadding: EdgeInsets.zero,
    hintText: hintText,
    hintStyle: TextStyle(
      color:
          Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      fontWeight: FontWeight.w500,
    ),
    prefixText: prefixText,
    suffixText: suffixText,
  );
}

/// The large, readable value text style for an Atlas row's inline editor.
TextStyle? atlasValueTextStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);

/// An editable single- or multi-line **text** Atlas row: a tinted icon, quiet
/// label and a borderless inline editor. Read-only renders the value directly
/// (multi-line preserved when [maxLines] > 1). Extracted from the form view so
/// any screen can render a text field as an Atlas row.
class AtlasTextInputRow extends StatelessWidget {
  const AtlasTextInputRow({
    super.key,
    this.icon,
    required this.label,
    this.required = false,
    this.readOnly = false,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.keyboardType,
    this.maxLines = 1,
    this.prefixText,
    this.suffixText,
  });

  final IconData? icon;
  final String label;
  final bool required;
  final bool readOnly;
  final String? value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? prefixText;
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    final v = value ?? '';
    return AtlasFieldRow(
      icon: icon,
      label: label,
      required: required,
      readOnly: readOnly,
      // A single-line read-only value uses the row's value slot; a multi-line
      // one renders as a child Text so line breaks survive.
      value: readOnly && maxLines <= 1 ? v : null,
      child: !readOnly
          ? AtlasTextFieldEditor(
              value: v,
              decoration: atlasInlineDecoration(context, hintText: placeholder),
              keyboardType: keyboardType,
              maxLines: maxLines,
              style: atlasValueTextStyle(context),
              readOnly: readOnly,
              onChanged: onChanged,
            )
          : (maxLines > 1 ? Text(v, style: atlasValueTextStyle(context)) : null),
    );
  }
}
