import 'package:flutter/material.dart';

enum WorkflowActionStyle { primary, secondary, danger }

class WorkflowActionButton extends StatelessWidget {
  const WorkflowActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = WorkflowActionStyle.secondary,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final WorkflowActionStyle style;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconWidget = busy
        ? const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink());
    final labelWidget = Text(label);

    switch (style) {
      case WorkflowActionStyle.primary:
        return FilledButton.icon(
          onPressed: busy ? null : onPressed,
          icon: iconWidget,
          label: labelWidget,
        );
      case WorkflowActionStyle.danger:
        return FilledButton.icon(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: cs.errorContainer,
            foregroundColor: cs.onErrorContainer,
          ),
          icon: iconWidget,
          label: labelWidget,
        );
      case WorkflowActionStyle.secondary:
        return OutlinedButton.icon(
          onPressed: busy ? null : onPressed,
          icon: iconWidget,
          label: labelWidget,
        );
    }
  }
}
