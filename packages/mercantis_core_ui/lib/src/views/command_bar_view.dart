import 'package:flutter/material.dart';
import '../shell/breakpoints.dart';
import '../theme/tokens/spacing.dart';

/// The record lifecycle command bar — Save / Submit / Cancel / Amend plus any
/// host-contributed actions. Pinned to the bottom of the record workspace (via
/// `Scaffold.bottomNavigationBar`) so the primary actions are thumb-reachable on
/// phones; on narrow widths the host-contributed [extraActions] collapse into a
/// "More actions" overflow sheet so the bar never overflows.
///
/// The action *gating* (which lifecycle buttons appear, keyed on
/// docStatus / isDirty / isSubmittable) is posting-critical and unchanged from
/// the original top-mounted bar — only the placement and the phone overflow are
/// new.
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
    final theme = Theme.of(context);
    final isPhone = Breakpoint.of(context).isPhone;
    final lifecycle = _lifecycleActions();

    // Nothing to surface (a clean draft with no actions and no status) — don't
    // occupy the pinned slot with an empty bar. Purely presentational; no
    // action is ever hidden by this.
    final hasContent = isSaving ||
        error != null ||
        _isSubmitted ||
        _isCancelled ||
        lifecycle.isNotEmpty ||
        extraActions.isNotEmpty;
    if (!hasContent) return const SizedBox.shrink();

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 1),
            if (error != null) _ErrorBanner(message: error!),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MercantisSpacing.lg,
                vertical: MercantisSpacing.sm,
              ),
              child: Row(
                children: [
                  if (_isSubmitted) const Chip(label: Text('Submitted')),
                  if (_isCancelled) const Chip(label: Text('Cancelled')),
                  const Spacer(),
                  if (isSaving)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    ..._actionRow(context, isPhone: isPhone, lifecycle: lifecycle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The built-in lifecycle buttons for the current docStatus. Gating preserved
  /// verbatim from the original bar — do not change these conditions without
  /// matching the engine's transition rules.
  List<Widget> _lifecycleActions() {
    final widgets = <Widget>[];
    if (_isDraft) {
      if (isDirty) {
        widgets.add(FilledButton(onPressed: onSave, child: const Text('Save')));
      }
      if (isSubmittable && documentName != null && !isDirty) {
        widgets.add(
            FilledButton(onPressed: onSubmit, child: const Text('Submit')));
      }
    }
    if (_isSubmitted && onCancel != null) {
      widgets.add(
          OutlinedButton(onPressed: onCancel, child: const Text('Cancel')));
    }
    if (_isCancelled && onAmend != null) {
      widgets
          .add(OutlinedButton(onPressed: onAmend, child: const Text('Amend')));
    }
    return widgets;
  }

  /// Lays the lifecycle buttons out with consistent spacing, then appends the
  /// host-contributed [extraActions] — inline on wide panes, or behind a "More
  /// actions" overflow sheet on phones so the row can't overflow.
  List<Widget> _actionRow(
    BuildContext context, {
    required bool isPhone,
    required List<Widget> lifecycle,
  }) {
    final items = <Widget>[];
    void addSpaced(Widget w) {
      if (items.isNotEmpty) {
        items.add(const SizedBox(width: MercantisSpacing.sm));
      }
      items.add(w);
    }

    for (final a in lifecycle) {
      addSpaced(a);
    }
    if (extraActions.isEmpty) return items;

    if (isPhone) {
      addSpaced(IconButton(
        icon: const Icon(Icons.more_horiz),
        tooltip: 'More actions',
        onPressed: () => _showMoreActions(context),
      ));
    } else {
      for (final a in extraActions) {
        addSpaced(a);
      }
    }
    return items;
  }

  void _showMoreActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in extraActions)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MercantisSpacing.lg,
                  vertical: MercantisSpacing.xs,
                ),
                child: a,
              ),
            const SizedBox(height: MercantisSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MercantisSpacing.lg,
          vertical: MercantisSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: MercantisSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
