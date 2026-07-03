import 'package:flutter/material.dart';

import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import 'atlas_colors.dart';
import 'atlas_icon_chip.dart';
import 'atlas_label.dart';

/// A quantity field rendered as an Atlas row with a proper stepper control:
/// a `−` button, the editable value in the middle, and a `+` button. Tapping a
/// button steps by [step] (clamped to [min]/[max]); the value can also be typed
/// directly. Emits an `int` when [decimals] is 0, otherwise a `double`.
///
/// This is the Neuradix Atlas answer to fiddly numeric cell editing on touch —
/// the line-item bottom sheet uses it for qty so a phone user can nudge a
/// count without summoning the keyboard.
class AtlasQuantityStepper extends StatefulWidget {
  const AtlasQuantityStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.readOnly = false,
    this.min,
    this.max,
    this.step = 1,
    this.decimals = 0,
    this.icon,
  });

  final String label;
  final num? value;

  /// Emits the new value, or `null` when the field is cleared — an optional
  /// numeric left blank must stay blank, not silently become zero.
  final ValueChanged<num?> onChanged;
  final bool required;
  final bool readOnly;
  final num? min;
  final num? max;
  final num step;

  /// 0 renders/emits an integer; > 0 keeps that many decimals (trailing zeros
  /// trimmed for display) and emits a double.
  final int decimals;
  final IconData? icon;

  @override
  State<AtlasQuantityStepper> createState() => _AtlasQuantityStepperState();
}

class _AtlasQuantityStepperState extends State<AtlasQuantityStepper> {
  late final TextEditingController _controller =
      TextEditingController(text: _display(widget.value));
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(AtlasQuantityStepper old) {
    super.didUpdateWidget(old);
    // Re-sync from an external change (e.g. a formula) only while the user
    // isn't typing, so the cursor is never yanked mid-entry.
    if (!_focus.hasFocus) {
      final text = _display(widget.value);
      if (text != _controller.text) _controller.text = text;
    }
  }

  /// A null value shows as blank (an intentionally empty optional numeric),
  /// not "0".
  String _display(num? v) => v == null ? '' : _format(v);

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _format(num v) {
    if (widget.decimals == 0) return v.round().toString();
    var s = v.toStringAsFixed(widget.decimals);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  num _parse(String s) => widget.decimals == 0
      ? (int.tryParse(s) ?? 0)
      : (num.tryParse(s) ?? 0);

  num _clamp(num v) {
    var out = v;
    if (widget.min != null && out < widget.min!) out = widget.min!;
    if (widget.max != null && out > widget.max!) out = widget.max!;
    return out;
  }

  void _emit(num v) =>
      widget.onChanged(widget.decimals == 0 ? v.round() : v.toDouble());

  void _bump(num delta) {
    // Stepping a blank field starts from the floor (min, or 0).
    final base = _controller.text.trim().isEmpty
        ? (widget.min ?? 0)
        : _parse(_controller.text);
    final next = _clamp(base + delta);
    // Buttons set the text explicitly so the field reflects the change even
    // while focused (didUpdateWidget skips focused re-syncs).
    _controller.text = _format(next);
    _emit(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final atlas = AtlasColors.of(context);
    // A blank field is treated as the floor for enabling the − button.
    final blank = _controller.text.trim().isEmpty;
    final current = blank ? (widget.min ?? 0) : _parse(_controller.text);
    final canDec = !widget.readOnly &&
        !(widget.min != null && current <= widget.min!);
    final canInc = !widget.readOnly &&
        !(widget.max != null && current >= widget.max!);

    final row = Row(
      children: [
        if (widget.icon != null) ...[
          AtlasIconChip(icon: widget.icon!),
          const SizedBox(width: MercantisSpacing.md),
        ],
        Expanded(child: AtlasLabel(label: widget.label, required: widget.required)),
        const SizedBox(width: MercantisSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: MercantisRadius.rMd,
            border: Border.all(color: atlas.borderSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepButton(
                icon: Icons.remove,
                onTap: canDec ? () => _bump(-widget.step) : null,
              ),
              SizedBox(
                width: 52,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  readOnly: widget.readOnly,
                  textAlign: TextAlign.center,
                  keyboardType: widget.decimals == 0
                      ? const TextInputType.numberWithOptions(signed: true)
                      : const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: widget.readOnly
                      ? null
                      : (s) => s.trim().isEmpty
                          ? widget.onChanged(null)
                          : _emit(_clamp(_parse(s))),
                ),
              ),
              _StepButton(
                icon: Icons.add,
                onTap: canInc ? () => _bump(widget.step) : null,
              ),
            ],
          ),
        ),
      ],
    );

    return Material(
      color: atlas.surface,
      shape: RoundedRectangleBorder(
        borderRadius: MercantisRadius.rMd,
        side: BorderSide(color: atlas.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MercantisSpacing.md,
          vertical: 6,
        ),
        child: row,
      ),
    );
  }
}

/// A single − / + tap target inside [AtlasQuantityStepper]; greyed when null.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          icon,
          size: 20,
          color: onTap == null
              ? cs.onSurfaceVariant.withValues(alpha: 0.35)
              : cs.primary,
        ),
      ),
    );
  }
}
