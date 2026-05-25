import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

void main() {
  group('Breakpoint.fromWidth', () {
    test('phone below 600', () {
      expect(Breakpoint.fromWidth(0), Breakpoint.phone);
      expect(Breakpoint.fromWidth(360), Breakpoint.phone);
      expect(Breakpoint.fromWidth(599.9), Breakpoint.phone);
    });
    test('compact 600..839', () {
      expect(Breakpoint.fromWidth(600), Breakpoint.compact);
      expect(Breakpoint.fromWidth(839.9), Breakpoint.compact);
    });
    test('medium 840..1199', () {
      expect(Breakpoint.fromWidth(840), Breakpoint.medium);
      expect(Breakpoint.fromWidth(1199), Breakpoint.medium);
    });
    test('expanded 1200+', () {
      expect(Breakpoint.fromWidth(1200), Breakpoint.expanded);
      expect(Breakpoint.fromWidth(1920), Breakpoint.expanded);
    });
  });

  group('Breakpoint flags', () {
    test('isPhone/isTablet/isDesktop are mutually consistent', () {
      expect(Breakpoint.phone.isPhone, isTrue);
      expect(Breakpoint.compact.isTablet, isTrue);
      expect(Breakpoint.medium.isTablet, isTrue);
      expect(Breakpoint.medium.isLarge, isTrue);
      expect(Breakpoint.expanded.isDesktop, isTrue);
      expect(Breakpoint.expanded.isLarge, isTrue);
    });
  });
}
