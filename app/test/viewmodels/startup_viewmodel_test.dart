// This file used to hold a `group()` with a setUp/tearDown and no cases at all
// — it ran, reported nothing, and padded the suite's file count. A test that
// cannot fail is worse than no test, because it reads as coverage.
//
// The startup path is worth a real case: it is the only place that hydrates the
// vault, and it is where the first-run marker used to be minted as a BYO API
// key.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/credential_service.dart';
import 'package:app_box/services/launch_service.dart';

const _config = {
  'credential': {'storageTierLabel': 'macOS Keychain', 'keyPrefix': 'app_box.'},
  'launch': {'autoLaunchDemo': true, 'firstRunKey': 'app_box.first_run_done'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    locator
      ..registerSingleton<ConfigService>(ConfigService()..loadMap(_config))
      ..registerSingleton<CredentialService>(CredentialService())
      ..registerSingleton<LaunchService>(LaunchService());
  });

  tearDown(() => locator.reset());

  group('StartupViewModel — the boot sequence', () {
    test('hydration makes a licence stored in a previous run visible again',
        () async {
      final creds = locator<CredentialService>();
      await creds.storeLicence('LIC-123');

      // Simulate a restart: a brand new service over the same vault.
      final fresh = CredentialService();
      expect(fresh.hasLicence, isFalse, reason: 'nothing read yet');
      await fresh.hydrate();
      expect(fresh.hasLicence, isTrue,
          reason: 'without hydrate() a paid licence reads as absent on restart '
              'and LicenceService blocks the build');
    });

    test('hydration restores BYO keys but never internal flags', () async {
      final creds = locator<CredentialService>();
      await creds.storeApiKey(id: 'anthropic', key: 'sk-test');
      await creds.setFlag('app_box.first_run_done');

      final fresh = CredentialService();
      await fresh.hydrate();

      expect(fresh.credentials.map((c) => c.id), ['anthropic']);
      expect(fresh.activeTier, CredentialTier.byoKey);
    });

    test('the first-run marker survives a restart, so the demo launches once',
        () async {
      final launch = locator<LaunchService>();
      expect(await launch.shouldAutoLaunchDemo(), isTrue);

      // A new LaunchService over the same vault is the restart.
      expect(await LaunchService().shouldAutoLaunchDemo(), isFalse);
    });
  });
}
