import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

/// Editor for `FieldType.barcode`. Stores the underlying data string and renders
/// a live Code 128 barcode preview (via `barcode_widget`) beneath the value.
class BarcodeField extends StatefulWidget {
  const BarcodeField({
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
  State<BarcodeField> createState() => _BarcodeFieldState();
}

class _BarcodeFieldState extends State<BarcodeField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(covariant BarcodeField old) {
    super.didUpdateWidget(old);
    // Keep the field in sync when the value is reset externally (e.g. a fresh
    // record) without clobbering the caret while the user is typing.
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
    final theme = Theme.of(context);
    final data = _controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          readOnly: widget.readOnly,
          decoration: InputDecoration(
            label: Text(widget.required ? '${widget.label} *' : widget.label),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.qr_code_2),
          ),
          onChanged: (v) => setState(() => widget.onChanged(v.isEmpty ? null : v)),
        ),
        if (data.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: BarcodeWidget(
              data: data,
              barcode: Barcode.code128(),
              drawText: true,
              height: 72,
              color: Colors.black,
              errorBuilder: (context, error) => Text(
                'Cannot encode value: $error',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
