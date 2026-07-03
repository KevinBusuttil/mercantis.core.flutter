import 'package:flutter/material.dart';

import 'atlas_field_row.dart';
import 'atlas_option_sheet.dart';

/// An Atlas selector row for a fixed list of [options] (a `select` field):
/// shows the chosen value (or a "Select <label>" placeholder) and opens an
/// [AtlasOptionSheet] on tap. Presentation + choice only — the caller owns the
/// value via [onChanged].
class AtlasSelectorRow extends StatelessWidget {
  const AtlasSelectorRow({
    super.key,
    this.icon,
    required this.label,
    this.required = false,
    this.readOnly = false,
    required this.value,
    required this.options,
    this.placeholder,
    required this.onChanged,
  });

  final IconData? icon;
  final String label;
  final bool required;
  final bool readOnly;
  final String? value;
  final List<String> options;
  final String? placeholder;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AtlasFieldRow(
      icon: icon,
      label: label,
      required: required,
      readOnly: readOnly || options.isEmpty,
      value: value,
      placeholder: placeholder ?? 'Select $label',
      onTap: () async {
        final picked = await showAtlasOptionSheet(
          context,
          title: label,
          options: options,
          selected: value,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
