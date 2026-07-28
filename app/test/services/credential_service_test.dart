// The vault must state the *right* tier, not merely a tier.
//
// 8.6 promises the UI names the active tier plainly ("stored in the macOS
// Keychain"). That promise is only kept if the tier is DERIVED from what the
// user actually supplied. Three things used to break it, and each has a case
// below:
//
//  1. LaunchService persisted its first-run marker through storeApiKey(), so a
//     fresh install reported byoKey and listed the marker as a credential.
//  2. storeLicence() tagged the licence byoKey — a licence is a purchase
//     precondition (8.12), not an LLM key.
//  3. activeTier ended in `return byoKey` as a fallback, so any non-empty list
//     that held no BYO key still answered byoKey.
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

  late CredentialService creds;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    if (locator.isRegistered<ConfigService>()) locator.unregister<ConfigService>();
    if (locator.isRegistered<CredentialService>()) {
      locator.unregister<CredentialService>();
    }
    final config = ConfigService()..loadMap(_config);
    creds = CredentialService();
    locator.registerSingleton<ConfigService>(config);
    locator.registerSingleton<CredentialService>(creds);
  });

  tearDown(() => locator.reset());

  group('CredentialService — the tier is derived, never defaulted', () {
    test('a fresh vault is `none`', () {
      expect(creds.activeTier, CredentialTier.none);
      expect(creds.credentials, isEmpty);
    });

    test('a BYO LLM key — and only that — reports byoKey', () async {
      await creds.storeApiKey(id: 'anthropic', key: 'sk-test');
      expect(creds.activeTier, CredentialTier.byoKey);
    });

    test('a licence is not a BYO key: it is a purchase precondition (8.12)',
        () async {
      await creds.storeLicence('LIC-123');
      expect(creds.hasLicence, isTrue,
          reason: 'the licence must still be readable by LicenceService');
      expect(creds.activeTier, CredentialTier.none,
          reason: 'a licence says nothing about how the app reaches an LLM');
    });

    test('a licence alongside a BYO key still reports byoKey', () async {
      await creds.storeLicence('LIC-123');
      await creds.storeApiKey(id: 'anthropic', key: 'sk-test');
      expect(creds.activeTier, CredentialTier.byoKey);
    });

    test('harness auth outranks a BYO key (the app holds no token)', () async {
      await creds.storeApiKey(id: 'anthropic', key: 'sk-test');
      creds.markHarnessAuth('claude-code');
      expect(creds.activeTier, CredentialTier.harness);
    });

    test('an internal flag is not a credential and cannot set a tier',
        () async {
      await creds.setFlag('app_box.first_run_done');
      expect(await creds.readFlag('app_box.first_run_done'), isTrue);
      expect(creds.credentials, isEmpty,
          reason: 'a boolean marker must never appear in the credential list');
      expect(creds.activeTier, CredentialTier.none);
    });
  });

  group('LaunchService — the first-run marker is not a credential', () {
    setUp(() {
      if (locator.isRegistered<LaunchService>()) locator.unregister<LaunchService>();
      locator.registerSingleton<LaunchService>(LaunchService());
    });

    test('first run does not mint a BYO key', () async {
      final launch = locator<LaunchService>();

      expect(await launch.shouldAutoLaunchDemo(), isTrue,
          reason: 'first call on a fresh install auto-launches the demo');

      // This is the defect the user caught: a fresh install used to show
      // "BYO key — stored in the macOS Keychain" having stored nothing.
      expect(creds.activeTier, CredentialTier.none);
      expect(creds.credentials, isEmpty);
    });

    test('the marker persists, so the second run does not auto-launch',
        () async {
      final launch = locator<LaunchService>();
      expect(await launch.shouldAutoLaunchDemo(), isTrue);
      expect(await launch.shouldAutoLaunchDemo(), isFalse);
    });
  });
}
