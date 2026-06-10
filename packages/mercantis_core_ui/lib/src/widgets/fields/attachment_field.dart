import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Editor for `FieldType.attach` and `FieldType.attachImage`. Stores a file
/// reference (a local path or a URL) as the field value — the same value-based
/// contract as the other field widgets. A file picker fills the reference in,
/// and image fields render a preview. Durable byte storage for a saved document
/// is handled separately by the document-level attachments panel.
class AttachmentField extends StatefulWidget {
  const AttachmentField({
    super.key,
    required this.label,
    required this.required,
    required this.value,
    required this.readOnly,
    required this.onChanged,
    this.isImage = false,
  });

  final String label;
  final bool required;
  final String? value;
  final bool readOnly;
  final ValueChanged<dynamic> onChanged;

  /// Renders an image preview and constrains the picker to images.
  final bool isImage;

  @override
  State<AttachmentField> createState() => _AttachmentFieldState();
}

class _AttachmentFieldState extends State<AttachmentField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(covariant AttachmentField old) {
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

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: widget.isImage ? FileType.image : FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final ref = file.path ?? file.name;
    setState(() {
      _controller.text = ref;
      widget.onChanged(ref);
    });
  }

  void _clear() => setState(() {
        _controller.text = '';
        widget.onChanged(null);
      });

  @override
  Widget build(BuildContext context) {
    final value = _controller.text.trim();
    final hasValue = value.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          readOnly: widget.readOnly,
          decoration: InputDecoration(
            label: Text(widget.required ? '${widget.label} *' : widget.label),
            hintText: 'File path or URL',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(
                widget.isImage ? Icons.image_outlined : Icons.attach_file),
            suffixIcon: (!widget.readOnly && hasValue)
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Remove',
                    onPressed: _clear,
                  )
                : null,
          ),
          onChanged: (t) =>
              setState(() => widget.onChanged(t.isEmpty ? null : t)),
        ),
        if (!widget.readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(widget.isImage ? 'Choose image' : 'Choose file'),
              ),
            ),
          ),
        if (widget.isImage && hasValue) ...[
          const SizedBox(height: 12),
          _ImagePreview(source: value),
        ],
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.source});
  final String source;

  static Widget _broken(BuildContext context, Object error, StackTrace? stack) {
    final theme = Theme.of(context);
    return Container(
      height: 80,
      alignment: Alignment.center,
      child: Text('Cannot preview image',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = source.startsWith('http')
        ? Image.network(source,
            height: 160, fit: BoxFit.contain, errorBuilder: _broken)
        : Image.file(File(source),
            height: 160, fit: BoxFit.contain, errorBuilder: _broken);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: image,
    );
  }
}
