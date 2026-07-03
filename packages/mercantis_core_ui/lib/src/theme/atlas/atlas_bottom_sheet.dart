import 'package:flutter/material.dart';

import '../../shell/breakpoints.dart';
import '../tokens/radius.dart';
import 'atlas_colors.dart';

/// Launches [builder] as a focused overlay, picking the presentation by
/// breakpoint: a draggable modal bottom sheet on a phone (resize handle + a
/// forwarded [ScrollController]) or a fixed-size centred dialog on a wider
/// pane. The one launcher for every rich Atlas sheet, so the phone-vs-desktop
/// decision and the DraggableScrollableSheet plumbing live in one place instead
/// of being re-derived at every call site.
///
/// [builder] receives a [ScrollController] on phone (wire it into the sheet's
/// scrollable body) and `null` in the dialog case; use `scrollController != null`
/// to decide whether to show the drag handle (see [AtlasBottomSheet.showHandle]).
Future<T?> showAtlasBottomSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController? scrollController)
      builder,
  double initialSize = 0.85,
  double minSize = 0.5,
  double maxSize = 0.95,
  bool draggable = true,
  BoxConstraints dialogConstraints = const BoxConstraints(
    minWidth: 420,
    maxWidth: 560,
    minHeight: 420,
    maxHeight: 640,
  ),
}) {
  if (Breakpoint.of(context).isPhone) {
    // A [draggable] sheet resizes with a handle and forwards a ScrollController
    // to its scrollable body (the default — for a form-like editor). A sheet
    // that owns its own scroll (e.g. a search picker with a fixed header +
    // results list) opts out and gets a plain fixed modal, with a null
    // controller passed to the builder.
    if (!draggable) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => builder(ctx, null),
      );
    }
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: initialSize,
        minChildSize: minSize,
        maxChildSize: maxSize,
        expand: false,
        builder: (_, scroll) => builder(ctx, scroll),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: dialogConstraints,
        child: builder(ctx, null),
      ),
    ),
  );
}

/// The chrome for a focused sheet/dialog: an optional drag handle, a
/// title/subtitle header, a scrollable [body], and an optional sticky [footer]
/// (typically an AtlasBottomActionBar). The body is supplied by the caller
/// (wired to the launcher's [ScrollController]) so this stays a layout, not a
/// content owner.
class AtlasBottomSheet extends StatelessWidget {
  const AtlasBottomSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.headerTrailing,
    required this.body,
    this.footer,
    this.showHandle = true,
  });

  final String title;
  final String? subtitle;

  /// Optional trailing widget in the header (e.g. a close or delete button).
  final Widget? headerTrailing;

  /// The scrollable content — the caller wires it to the forwarded controller.
  final Widget body;

  /// Sticky footer, pinned below the scrolling body (does not scroll away).
  final Widget? footer;

  /// Shown only in the phone/draggable presentation; the launcher passes false
  /// for the dialog variant.
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atlas = AtlasColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHandle)
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              decoration: BoxDecoration(
                color: atlas.textSecondary.withValues(alpha: 0.4),
                borderRadius: MercantisRadius.rPill,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    if ((subtitle ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: atlas.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (headerTrailing != null) headerTrailing!,
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(child: body),
        if (footer != null) ...[
          const Divider(height: 1),
          footer!,
        ],
      ],
    );
  }
}
