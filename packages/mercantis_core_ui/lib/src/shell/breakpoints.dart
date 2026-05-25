import 'package:flutter/widgets.dart';

enum Breakpoint {
  phone,    // < 600
  compact,  // 600 - 839 (small tablet)
  medium,   // 840 - 1199 (large tablet / small desktop)
  expanded; // >= 1200 (desktop)

  static Breakpoint fromWidth(double width) {
    if (width >= 1200) return Breakpoint.expanded;
    if (width >= 840) return Breakpoint.medium;
    if (width >= 600) return Breakpoint.compact;
    return Breakpoint.phone;
  }

  static Breakpoint of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  bool get isPhone => this == Breakpoint.phone;
  bool get isTablet => this == Breakpoint.compact || this == Breakpoint.medium;
  bool get isDesktop => this == Breakpoint.expanded;
  bool get isHandset => this == Breakpoint.phone;
  bool get isLarge => this == Breakpoint.medium || this == Breakpoint.expanded;
}
