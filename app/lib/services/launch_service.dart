import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/credential_service.dart';

/// 8.13 / journey J1 — auto-launch the showcase app on first install.
///
/// Michelle must see output quality before typing anything: the showcase app
/// launching on first run *is* the demo. The first-run flag lives in the
/// Keychain (via [CredentialService]) so it survives reinstalls of the app data.
class LaunchService {
  bool _didShowcaseLaunch = false;
  bool get didShowcaseLaunch => _didShowcaseLaunch;

  /// Returns true on the first call (the first run) when auto-launch is enabled
  /// in config; subsequent calls return false.
  Future<bool> shouldAutoLaunchShowcase() async {
    final config = locator<ConfigService>();
    if (!config.autoLaunchShowcase) return false;
    final creds = locator<CredentialService>();
    final seen = await creds.read(config.firstRunKey);
    if (seen != null) return false; // already launched once
    await creds.storeApiKey(id: config.firstRunKey, key: '1');
    return true;
  }

  /// Marks the showcase as launched (the shell calls this once it has driven the
  /// showcase surface on first run).
  void markShowcaseLaunched() => _didShowcaseLaunch = true;
}
