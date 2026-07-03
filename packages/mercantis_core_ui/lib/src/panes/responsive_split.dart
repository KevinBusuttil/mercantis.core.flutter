import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../shell/breakpoints.dart';

/// Two- or three-pane responsive layout.
///
/// - phone: only [list] is shown (when [detail] is null) or only [detail]
///   (the navigator pattern is up to the caller — this widget simply collapses).
/// - compact (small tablet): list + detail (no aside).
/// - medium / expanded: list + detail + optional [aside].
///
/// Pane widths are computed from the widget's own [LayoutBuilder] constraints,
/// not the window (`MediaQuery`), so it lays out correctly when nested inside a
/// narrower pane. The [list] is capped at [maxListWidthFraction] of the
/// available width, and a minimum-detail guard drops the [aside] first — then
/// narrows the list — before the detail pane is starved.
class ResponsiveSplit extends StatelessWidget {
  const ResponsiveSplit({
    super.key,
    required this.list,
    this.detail,
    this.aside,
    this.listWidth = 340,
    this.asideWidth = 340,
    this.maxListWidthFraction = 0.42,
    this.minDetailWidth = 360,
  });

  final Widget list;
  final Widget? detail;
  final Widget? aside;
  final double listWidth;
  final double asideWidth;

  /// Hard cap on the list pane as a fraction of the available width, so a
  /// narrow pane can't be dominated by the list.
  final double maxListWidthFraction;

  /// The detail pane is kept at least this wide (when the pane can afford it)
  /// by first dropping the aside, then shrinking the list.
  final double minDetailWidth;

  @override
  Widget build(BuildContext context) {
    final bp = Breakpoint.of(context);
    if (bp == Breakpoint.phone) {
      return detail ?? list;
    }

    final cs = Theme.of(context).colorScheme;
    final divider = VerticalDivider(
      thickness: 1, width: 1, color: cs.outlineVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;

        // List: the requested fixed width, but never more than
        // [maxListWidthFraction] of the pane.
        var listW = math.min(listWidth, available * maxListWidthFraction);

        // Aside only on large panes — and only if there's room for it plus a
        // usable detail pane. Drop it first when the detail would be starved.
        var asideW = (aside != null && bp.isLarge) ? asideWidth : 0.0;
        if (asideW > 0 &&
            available - listW - asideW - 2 < minDetailWidth) {
          asideW = 0;
        }

        final dividerCount = asideW > 0 ? 2 : 1;
        // Then shrink the list so the detail keeps [minDetailWidth] (never
        // letting the list go negative on a very narrow pane).
        final maxListForDetail =
            available - (dividerCount * divider.width!) - asideW - minDetailWidth;
        if (maxListForDetail > 0 && listW > maxListForDetail) {
          listW = maxListForDetail;
        }
        listW = math.max(0.0, listW);

        final children = <Widget>[
          SizedBox(width: listW, child: list),
          divider,
          Expanded(child: detail ?? const SizedBox.shrink()),
        ];
        if (asideW > 0) {
          children.add(divider);
          children.add(SizedBox(width: asideW, child: aside!));
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}
