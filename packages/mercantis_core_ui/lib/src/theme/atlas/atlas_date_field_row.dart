import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'atlas_field_row.dart';

/// Atlas selector row for a `date` field — shows the formatted value (or a
/// "Choose <label>" placeholder) and opens a date picker on tap. Stores a
/// `yyyy-MM-dd` string.
class AtlasDateFieldRow extends StatelessWidget {
  const AtlasDateFieldRow({
    super.key,
    this.icon,
    required this.label,
    this.required = false,
    this.readOnly = false,
    required this.value,
    required this.onChanged,
    this.onCleared,
  });

  final IconData? icon;
  final String label;
  final bool required;
  final bool readOnly;
  final String? value;
  final ValueChanged<String> onChanged;

  /// When supplied (and the field has a value and is editable), a trailing
  /// clear button lets the user remove an optional date — the picker alone
  /// can only change it, never empty it.
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(value ?? '');
    final display =
        parsed != null ? DateFormat('d MMM yyyy').format(parsed) : (value ?? '');
    final canClear =
        onCleared != null && !readOnly && (value ?? '').isNotEmpty;
    return AtlasFieldRow(
      icon: icon,
      label: label,
      required: required,
      readOnly: readOnly,
      value: display,
      placeholder: 'Choose $label',
      trailing: canClear ? _AtlasClearButton(onPressed: onCleared!) : null,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: parsed ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(DateFormat('yyyy-MM-dd').format(picked));
      },
    );
  }
}

/// Small trailing "clear" affordance for a selector row that carries an
/// optional value (replaces the chevron while a value is present).
class _AtlasClearButton extends StatelessWidget {
  const _AtlasClearButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.close, size: 18),
      visualDensity: VisualDensity.compact,
      tooltip: 'Clear',
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: onPressed,
    );
  }
}

/// Atlas selector row for a `time` field — opens a time picker; stores `HH:mm`.
class AtlasTimeFieldRow extends StatelessWidget {
  const AtlasTimeFieldRow({
    super.key,
    this.icon,
    required this.label,
    this.required = false,
    this.readOnly = false,
    required this.value,
    required this.onChanged,
  });

  final IconData? icon;
  final String label;
  final bool required;
  final bool readOnly;
  final String? value;
  final ValueChanged<String> onChanged;

  static TimeOfDay _parse(String? v) {
    if (v != null && v.contains(':')) {
      final parts = v.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) return TimeOfDay(hour: h, minute: m);
    }
    return TimeOfDay.now();
  }

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AtlasFieldRow(
      icon: icon,
      label: label,
      required: required,
      readOnly: readOnly,
      value: value,
      placeholder: 'Choose $label',
      onTap: () async {
        final picked =
            await showTimePicker(context: context, initialTime: _parse(value));
        if (picked != null) onChanged(_format(picked));
      },
    );
  }
}

/// Atlas selector row for a `dateTime` field — opens a date then a time picker;
/// stores `yyyy-MM-dd HH:mm`.
class AtlasDateTimeFieldRow extends StatelessWidget {
  const AtlasDateTimeFieldRow({
    super.key,
    this.icon,
    required this.label,
    this.required = false,
    this.readOnly = false,
    required this.value,
    required this.onChanged,
  });

  final IconData? icon;
  final String label;
  final bool required;
  final bool readOnly;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(value ?? '');
    final display = parsed != null
        ? DateFormat('d MMM yyyy, HH:mm').format(parsed)
        : (value ?? '');
    return AtlasFieldRow(
      icon: icon,
      label: label,
      required: required,
      readOnly: readOnly,
      value: display,
      placeholder: 'Choose $label',
      onTap: () async {
        final existing = parsed ?? DateTime.now();
        final date = await showDatePicker(
          context: context,
          initialDate: existing,
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(existing),
        );
        if (time == null) return;
        final combined =
            DateTime(date.year, date.month, date.day, time.hour, time.minute);
        onChanged(DateFormat('yyyy-MM-dd HH:mm').format(combined));
      },
    );
  }
}
