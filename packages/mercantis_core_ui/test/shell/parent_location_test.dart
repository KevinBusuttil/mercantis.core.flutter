import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The left-edge back-swipe target: one level up the drill path.
void main() {
  group('parentLocation', () {
    test('a form goes back to its list', () {
      expect(parentLocation('/form/Sales%20Invoice/SINV-1'),
          '/list/Sales%20Invoice');
      expect(parentLocation('/form/Item/new'), '/list/Item');
    });

    test('a list goes back to home', () {
      expect(parentLocation('/list/Item'), '/');
      expect(parentLocation('/list/Account?selected=Cash'), '/');
    });

    test('a workspace route goes back to its workspace', () {
      expect(parentLocation('/w/finance/account-ledger?account=Bank'),
          '/w/finance');
    });

    test('a workspace goes back to home', () {
      expect(parentLocation('/w/finance'), '/');
    });

    test('top-level / unknown locations have no parent', () {
      expect(parentLocation('/'), isNull);
      expect(parentLocation(''), isNull);
      expect(parentLocation('/settings'), isNull);
    });
  });
}
