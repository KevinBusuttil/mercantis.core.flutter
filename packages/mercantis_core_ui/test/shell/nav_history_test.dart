import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The back-stack that powers the system-back / back-swipe: return to the actual
/// previous screen, not a heuristic parent.
void main() {
  group('NavHistory', () {
    test('back returns the previous location visited', () {
      final h = NavHistory('/w/home');
      h.visit('/form/Sales Order/new'); // Home → New Sales Order (a quick action)
      expect(h.canGoBack, isTrue);
      // Back goes to Home — the screen actually come from, not the form's list.
      expect(h.back(), '/w/home');
      expect(h.current, '/w/home');
      expect(h.canGoBack, isFalse);
    });

    test('at the first location there is nowhere to go back to', () {
      final h = NavHistory('/w/home');
      expect(h.canGoBack, isFalse);
      expect(h.back(), isNull);
    });

    test('re-visiting the current location is a no-op (absorbs back re-report)',
        () {
      final h = NavHistory('/w/home');
      h.visit('/list/Item');
      h.visit('/list/Item'); // router re-reports same location
      expect(h.length, 2);
      // Simulate the back()→go(prev) round-trip: back, then the router reports
      // the previous location again — which must not re-grow the stack.
      final prev = h.back();
      expect(prev, '/w/home');
      h.visit(prev!);
      expect(h.length, 1);
      expect(h.canGoBack, isFalse);
    });

    test('deep chains walk back one screen at a time', () {
      final h = NavHistory('/w/sales')
        ..visit('/list/Sales Order')
        ..visit('/form/Sales Order/SO-1');
      expect(h.back(), '/list/Sales Order');
      expect(h.back(), '/w/sales');
      expect(h.back(), isNull); // exit from here
    });
  });
}
