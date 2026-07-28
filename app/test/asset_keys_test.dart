// Regression guard: app_box is a STANDALONE app, so its asset constants
// must be plain keys ('assets/seed/...'). The 'packages/app_box/'
// prefix is only valid when a host app bundles this package as a dependency —
// with the prefixed keys the standalone app white-screens at boot
// (initialize() throws "Unable to load asset" before runApp).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_box/app/app_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fixture + fake-user asset keys resolve via rootBundle', () async {
    for (final key in [
      AppData.fakeUsersAsset,
      ...AppData.fixtureAssets,
    ]) {
      final data = await rootBundle.load(key);
      expect(data.lengthInBytes, greaterThan(0), reason: key);
    }
  });
}
