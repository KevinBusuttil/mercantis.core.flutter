import 'package:flutter/material.dart';

class CommandBarView extends StatelessWidget {
  const CommandBarView({
    super.key,
    required this.docTypeName,
    required this.documentName,
    required this.isDirty,
    required this.isSaving,
    required this.isSubmittable,
    required this.docStatus,
    required this.onSave,
    required this.onSubmit,
    this.onCancel,
    this.onAmend,
    this.error,
    this.extraActions = const <Widget>[],
  });

  final String docTypeName;
  final String? documentName;
  final bool isDirty;
  final bool isSaving;
  final bool isSubmittable;
  final int docStatus;
  final VoidCallback onSave;
  final VoidCallback onSubmit;
  final VoidCallback? onCancel;
  final VoidCallback? onAmend;
  final String? error;

  /// Host-contributed action buttons (e.g. document conversion), rendered after
  /// the built-in lifecycle actions. Pre-built widgets so this view stays free
  /// of any module dependency.
  final List<Widget> extraActions;

  bool get _isDraft => docStatus == 0;
  bool get _isSubmitted => docStatus == 1;
  bool get _isCancelled => docStatus == 2;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null)
          ColoredBox(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                documentName ?? 'New $docTypeName',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_isSubmitted)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Chip(label: Text('Submitted')),
                ),
              if (_isCancelled)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Chip(label: Text('Cancelled')),
                ),
              const Spacer(),
              if (isSaving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ..._actions(),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  List<Widget> _actions() {
    final widgets = <Widget>[];
    if (_isDraft) {
      if (isDirty) {
        widgets.add(FilledButton(onPressed: onSave, child: const Text('Save')));
      }
      if (isSubmittable && documentName != null && !isDirty) {
        widgets.add(const SizedBox(width: 8));
        widgets.add(
            FilledButton(onPressed: onSubmit, child: const Text('Submit')));
      }
    }
    if (_isSubmitted && onCancel != null) {
      widgets.add(const SizedBox(width: 8));
      widgets
          .add(OutlinedButton(onPressed: onCancel, child: const Text('Cancel')));
    }
    if (_isCancelled && onAmend != null) {
      widgets.add(const SizedBox(width: 8));
      widgets
          .add(OutlinedButton(onPressed: onAmend, child: const Text('Amend')));
    }
    for (final action in extraActions) {
      widgets.add(const SizedBox(width: 8));
      widgets.add(action);
    }
    return widgets;
  }
}
