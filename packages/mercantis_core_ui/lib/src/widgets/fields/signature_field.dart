import 'dart:convert';

import 'package:flutter/material.dart';

/// Editor for `FieldType.signature`. Captures freehand strokes and stores them
/// as JSON with normalised (0..1) coordinates, so a signature re-renders at any
/// size. Hand-rolled (GestureDetector + CustomPainter) — no plugin needed.
class SignatureField extends StatelessWidget {
  const SignatureField({
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strokes = decodeStrokes(value);
    final hasSignature = strokes.any((s) => s.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            required ? '$label *' : label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Container(
          height: 140,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasSignature
              ? CustomPaint(
                  painter: _SignaturePainter(
                    strokes,
                    color: theme.colorScheme.onSurface,
                  ),
                  child: const SizedBox.expand(),
                )
              : Center(
                  child: Text(
                    readOnly ? 'No signature' : 'Tap “Sign” to add a signature',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
        ),
        if (!readOnly)
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasSignature)
                  TextButton.icon(
                    onPressed: () => onChanged(null),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                  ),
                TextButton.icon(
                  onPressed: () => _openPad(context),
                  icon: const Icon(Icons.draw_outlined, size: 18),
                  label: Text(hasSignature ? 'Re-sign' : 'Sign'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _openPad(BuildContext context) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _SignaturePadDialog(label: label),
    );
    // The dialog pops with the encoded signature on Save, or is dismissed
    // (null) on Cancel — only Save mutates the value.
    if (result != null) onChanged(result.isEmpty ? null : result);
  }

  /// Decodes the stored JSON into normalised strokes. Tolerates null / malformed
  /// input by returning an empty list.
  static List<List<Offset>> decodeStrokes(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw);
      final strokes = (data is Map ? data['strokes'] : data) as List;
      return [
        for (final s in strokes)
          [
            for (final p in (s as List))
              Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          ],
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Encodes normalised strokes to the stored JSON shape.
  static String encodeStrokes(List<List<Offset>> strokes) => jsonEncode({
        'strokes': [
          for (final s in strokes)
            [
              for (final p in s) [p.dx, p.dy],
            ],
        ],
      });
}

/// Paints normalised (0..1) strokes scaled to the canvas size.
class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes, {required this.color});
  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path();
      final first = _scale(stroke.first, size);
      path.moveTo(first.dx, first.dy);
      if (stroke.length == 1) {
        // A single tap — draw a dot.
        canvas.drawCircle(first, 1.5, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      for (final p in stroke.skip(1)) {
        final o = _scale(p, size);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  Offset _scale(Offset p, Size size) =>
      Offset(p.dx * size.width, p.dy * size.height);

  @override
  bool shouldRepaint(covariant _SignaturePainter old) =>
      old.strokes != strokes || old.color != color;
}

class _SignaturePadDialog extends StatefulWidget {
  const _SignaturePadDialog({required this.label});
  final String label;

  @override
  State<_SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<_SignaturePadDialog> {
  /// Strokes captured in the pad's local pixel coordinates; normalised on save.
  final List<List<Offset>> _strokes = [];
  Size _canvasSize = Size.zero;

  void _start(Offset local) => setState(() => _strokes.add([local]));

  void _extend(Offset local) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.add(local));
  }

  void _save() {
    final w = _canvasSize.width, h = _canvasSize.height;
    if (w == 0 || h == 0) {
      Navigator.pop(context, '');
      return;
    }
    final normalised = [
      for (final s in _strokes)
        [for (final p in s) Offset(p.dx / w, p.dy / h)],
    ];
    Navigator.pop(context, SignatureField.encodeStrokes(normalised));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 360,
        height: 220,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: GestureDetector(
                onPanStart: (d) => _start(d.localPosition),
                onPanUpdate: (d) => _extend(d.localPosition),
                child: CustomPaint(
                  painter: _PadPainter(_strokes, color: theme.colorScheme.onSurface),
                  child: const SizedBox.expand(),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _strokes.isEmpty ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Paints strokes already in canvas-pixel coordinates (the live pad).
class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes, {required this.color});
  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.5, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) => true;
}
