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
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // On blur, reconcile the controller to the authoritative value. While
    // focused we deliberately drop external updates (see didUpdateWidget), so
    // without this a real change that arrived mid-edit — e.g. a parent that
    // coerced an unparsable paste to null/blank — would leave stale text on
    // screen that no longer matches what a save would persist.
    _focus.addListener(_syncOnBlur);
  }

  void _syncOnBlur() {
    if (!_focus.hasFocus) _syncFromWidget();
  }

  void _syncFromWidget() {
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void didUpdateWidget(AtlasTextFieldEditor old) {
    super.didUpdateWidget(old);
    // Only re-sync from an external value change (e.g. a formula recompute)
    // while the user isn't typing. Otherwise a parent that rebuilds on every
    // keystroke — and feeds back a *normalised* value (e.g. "1" → "1.0") —
    // would fight the caret and corrupt live input (1 → 1.0 → 1.02). A change
    // that arrives while focused is reconciled instead on blur (_syncOnBlur).
    if (!_focus.hasFocus) _syncFromWidget();
  }

  @override
  void dispose() {
    _focus.removeListener(_syncOnBlur);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focus,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      style: widget.style,
      readOnly: widget.readOnly,
      onChanged: widget.readOnly ? null : widget.onChanged,
    );
  }
}
