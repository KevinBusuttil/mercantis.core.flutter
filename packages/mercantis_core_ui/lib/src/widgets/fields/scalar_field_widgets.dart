import 'package:flutter/material.dart';

/// Editor for `FieldType.rating` — a 1–5 star picker. Stores an `int` (0 = no
/// rating). Tapping the current rating again clears it.
class RatingField extends StatelessWidget {
  const RatingField({
    super.key,
    required this.label,
    required this.required,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.max = 5,
  });

  final String label;
  final bool required;
  final dynamic value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = (value as num?)?.round() ?? 0;
    return InputDecorator(
      decoration: InputDecoration(
        label: Text(required ? '$label *' : label),
        border: const OutlineInputBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= max; i++)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(
                i <= current ? Icons.star : Icons.star_border,
                color: i <= current ? Colors.amber.shade700 : theme.colorScheme.outline,
              ),
              onPressed: readOnly
                  ? null
                  : () => onChanged(i == current ? 0 : i),
            ),
        ],
      ),
    );
  }
}

/// Editor for `FieldType.duration` — hours + minutes inputs. Stores total
/// seconds as an `int` (mirroring the Swift duration field's storage).
class DurationField extends StatefulWidget {
  const DurationField({
    super.key,
    required this.label,
    required this.required,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final bool required;
  final dynamic value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  @override
  State<DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<DurationField> {
  late final TextEditingController _hours;
  late final TextEditingController _minutes;

  int get _seconds => (widget.value as num?)?.round() ?? 0;

  @override
  void initState() {
    super.initState();
    _hours = TextEditingController(text: _fmt(_seconds ~/ 3600));
    _minutes = TextEditingController(text: _fmt((_seconds % 3600) ~/ 60));
  }

  static String _fmt(int n) => n == 0 ? '' : '$n';

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _emit() {
    final h = int.tryParse(_hours.text) ?? 0;
    final m = int.tryParse(_minutes.text) ?? 0;
    final total = h * 3600 + m * 60;
    widget.onChanged(total == 0 ? null : total);
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        label: Text(widget.required ? '${widget.label} *' : widget.label),
        border: const OutlineInputBorder(),
      ),
      child: Row(
        children: [
          Expanded(child: _unit(_hours, 'Hours')),
          const SizedBox(width: 12),
          Expanded(child: _unit(_minutes, 'Minutes')),
        ],
      ),
    );
  }

  Widget _unit(TextEditingController c, String suffix) => TextField(
        controller: c,
        readOnly: widget.readOnly,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          suffixText: suffix,
        ),
        onChanged: (_) => _emit(),
      );
}

/// Editor for `FieldType.code` — a monospace, multi-line text area for snippets
/// / scripts. Stores a `String`.
class CodeField extends StatefulWidget {
  const CodeField({
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

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(covariant CodeField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _controller.text) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      readOnly: widget.readOnly,
      maxLines: 8,
      minLines: 3,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        label: Text(widget.required ? '${widget.label} *' : widget.label),
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      onChanged: (v) => widget.onChanged(v.isEmpty ? null : v),
    );
  }
}
