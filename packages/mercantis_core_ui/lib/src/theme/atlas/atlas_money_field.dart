import 'package:flutter/material.dart';

import 'atlas_field_row.dart';
import 'atlas_text_field_editor.dart';
import 'atlas_text_input_row.dart';

/// An editable numeric Atlas row for currency / float / percent values: a
/// borderless inline editor with an optional currency [prefixText] and/or
/// [suffixText] (e.g. `%`). Emits a `num?` — null when the field is cleared —
/// so an intentionally-blank optional amount stays blank. Read-only renders the
/// value directly (read-only *totals* use AtlasTotalRow instead, upstream).
///
/// (Precision-/tabular-figure display polish lands in a later phase; for now
/// the value is shown as typed to preserve current behaviour.)
class AtlasMoneyField extends StatelessWidget {
  const AtlasMoneyField({
    super.key,
    this.icon,
    required this.label,
    this.required = false,
    this.readOnly = false,
    required this.value,
    required this.onChanged,
    this.prefixText,
    this.suffixText,
  });

  final IconData? icon;
  final String label;
  final bool required;
  final bool readOnly;
  final num? value;
  final ValueChanged<num?> onChanged;
  final String? prefixText;
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    return AtlasFieldRow(
      icon: icon,
      label: label,
      required: required,
      readOnly: readOnly,
      value: readOnly ? value?.toString() : null,
      child: readOnly
          ? null
          : AtlasTextFieldEditor(
              value: value?.toString() ?? '',
              decoration: atlasInlineDecoration(
                context,
                prefixText: prefixText,
                suffixText: suffixText,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: atlasValueTextStyle(context),
              readOnly: readOnly,
              onChanged: (s) => onChanged(double.tryParse(s)),
            ),
    );
  }
}
