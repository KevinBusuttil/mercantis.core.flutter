import 'package:flutter/material.dart';
import '../shell/breakpoints.dart';

/// Two- or three-pane responsive layout.
///
/// - phone: only [list] is shown (when [detail] is null) or only [detail]
///   (the navigator pattern is up to the caller — this widget simply collapses).
/// - compact (small tablet): list + detail (no aside).
/// - medium / expanded: list + detail + optional [aside].
class ResponsiveSplit extends StatelessWidget {
  const ResponsiveSplit({
    super.key,
    required this.list,
    this.detail,
    this.aside,
    this.listWidth = 340,
    this.asideWidth = 340,
    this.maxListWidthFraction = 0.42,
  });

  final Widget list;
  final Widget? detail;
  final Widget? aside;
  final double listWidth;
  final double asideWidth;
  final double maxListWidthFraction;

  @override
  Widget build(BuildContext context) {
    final bp = Breakpoint.of(context);
    if (bp == Breakpoint.phone) {
      return detail ?? list;
    }

    final width = MediaQuery.sizeOf(context).width;
    final cs = Theme.of(context).colorScheme;
    final effectiveListWidth = bp == Breakpoint.compact
        ? (width * 0.42).clamp(280.0, 360.0).toDouble()
        : listWidth;

    final divider = VerticalDivider(
      thickness: 1, width: 1, color: cs.outlineVariant,
    );

    final children = <Widget>[
      SizedBox(width: effectiveListWidth, child: list),
      divider,
      Expanded(child: detail ?? const SizedBox.shrink()),
    ];

    if (aside != null && bp.isLarge) {
      children.add(divider);
      children.add(SizedBox(width: asideWidth, child: aside!));
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
