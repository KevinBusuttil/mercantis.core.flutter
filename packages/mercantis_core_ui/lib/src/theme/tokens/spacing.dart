import 'package:flutter/widgets.dart';

class MercantisSpacing {
  const MercantisSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const EdgeInsets pagePhone = EdgeInsets.all(lg);
  static const EdgeInsets pageTablet = EdgeInsets.all(xl);
  static const EdgeInsets pageDesktop = EdgeInsets.symmetric(horizontal: xxl, vertical: xl);

  static EdgeInsets pageFor(double width) {
    if (width >= 1200) return pageDesktop;
    if (width >= 600) return pageTablet;
    return pagePhone;
  }
}
