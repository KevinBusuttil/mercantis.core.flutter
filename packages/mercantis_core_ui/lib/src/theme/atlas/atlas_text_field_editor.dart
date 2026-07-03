import 'package:flutter/material.dart';

/// A thin, controller-backed [TextFormField] wrapper that keeps its text in
/// sync with an externally-driven [value] (e.g. a formula recompute) without
/// resetting the cursor mid-entry. The [decoration] is supplied by the caller,
/// so the same editor serves both an outlined child-table cell and a borderless
/// Atlas value slot. Extracted from the form view so any Atlas row can reuse it.
class AtlasTextFieldEditor extends StatefulWidget {
  const AtlasTextFieldEditor({
    super.key,
    required this.value,
    required this.decoration,
    required this.readOnly,
    required this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.style,
  });

  final String value;
  final InputDecoration decoration;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextStyle? style;

  @override
  State<AtlasTextFieldEditor> createState() => _AtlasTextFieldEditorState();
}

class _AtlasTextFieldEditorState extends State<AtlasTextFieldEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(AtlasTextFieldEditor old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      style: widget.style,
      readOnly: widget.readOnly,
      onChanged: widget.readOnly ? null : widget.onChanged,
    );
  }
}
