import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('device id is generated once, persisted, and stable across installs',
      () async {
    SharedPreferences.setMockInitialValues({});

    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    final id1 = await c1.read(deviceIdProvider.future);
    expect(id1, isNotEmpty);
    // Same container returns the same id (no re-mint).
    expect(await c1.read(deviceIdProvider.future), id1);

    // A fresh container reads the persisted id rather than minting a new one,
    // so a device keeps one identity across restarts.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(await c2.read(deviceIdProvider.future), id1);
  });

  test('honors a pre-seeded device id', () async {
    SharedPreferences.setMockInitialValues({'core.device_id': 'fixed-abc'});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(deviceIdProvider.future), 'fixed-abc');
  });
}
