import 'package:flutter/material.dart';

/// Editor for `FieldType.color`. Stores a `#RRGGBB` hex string. Shows the
/// current swatch + hex; tapping opens a palette of presets plus a hex entry.
class ColorField extends StatelessWidget {
  const ColorField({
    super.key,
    required this.label,
    required this.required,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final bool required;
  final String? value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  static const _presets = <int>[
    0xFFEF5350, 0xFFEC407A, 0xFFAB47BC, 0xFF7E57C2, 0xFF5C6BC0,
    0xFF42A5F5, 0xFF29B6F6, 0xFF26C6DA, 0xFF26A69A, 0xFF66BB6A,
    0xFF9CCC65, 0xFFD4E157, 0xFFFFEE58, 0xFFFFCA28, 0xFFFFA726,
    0xFFFF7043, 0xFF8D6E63, 0xFFBDBDBD, 0xFF78909C, 0xFF000000,
  ];

  @override
  Widget build(BuildContext context) {
    final color = parseHex(value);
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        label: Text(required ? '$label *' : label),
        border: const OutlineInputBorder(),
      ),
      child: InkWell(
        onTap: readOnly ? null : () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color ?? theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value?.isNotEmpty == true ? value!.toUpperCase() : 'No colour',
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              if (!readOnly) const Icon(Icons.colorize, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ColorPickerDialog(label: label, initial: value),
    );
    if (result != null) onChanged(result.isEmpty ? null : result);
  }

  /// Parses `#RRGGBB` (or `RRGGBB`) into a [Color]; returns null when invalid.
  static Color? parseHex(String? hex) {
    if (hex == null) return null;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  static String toHex(Color c) {
    String two(int n) => n.toRadixString(16).padLeft(2, '0');
    final r = two((c.r * 255).round());
    final g = two((c.g * 255).round());
    final b = two((c.b * 255).round());
    return '#$r$g$b'.toUpperCase();
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.label, required this.initial});
  final String label;
  final String? initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late final TextEditingController _hex =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ColorField.parseHex(_hex.text);
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final argb in ColorField._presets)
                  _Swatch(
                    color: Color(argb),
                    selected: current?.toARGB32() == argb,
                    onTap: () => setState(
                        () => _hex.text = ColorField.toHex(Color(argb))),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hex,
              decoration: const InputDecoration(
                labelText: 'Hex',
                hintText: '#RRGGBB',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: current == null
              ? null
              : () => Navigator.pop(context, ColorField.toHex(current)),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
