import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/credential_service.dart';

/// 8.13 / journey J1 — auto-launch the bundled **demo project** on first run.
///
/// Michelle must see output quality before typing anything: the demo launching
/// on first run *is* the pitch.
///
/// Naming note: this was called "showcase", which collided with
/// `stacked_kit/showcase_app` — the app this one was forked from (plan 8.1).
/// One word, two unrelated meanings, in one codebase. "Demo" is the product
/// concept; the fork's name is gone from `lib/` entirely.
class LaunchService {
  bool _didDemoLaunch = false;
  bool get didDemoLaunch => _didDemoLaunch;

  /// True on the first run only, when auto-launch is enabled in config.
  ///
  /// The marker lives in the vault so it survives a reinstall of the app data,
  /// but it is a **flag, not a credential** — writing it through `storeApiKey`
  /// made a fresh install report "BYO key — stored in the macOS Keychain"
  /// having stored nothing at all.
  Future<bool> shouldAutoLaunchDemo() async {
    final config = locator<ConfigService>();
    if (!config.autoLaunchDemo) return false;
    final creds = locator<CredentialService>();
    if (await creds.readFlag(config.firstRunKey)) return false;
    await creds.setFlag(config.firstRunKey);
    return true;
  }

  /// Marks the demo as launched (the shell calls this once it has driven the
  /// demo surface on first run).
  void markDemoLaunched() => _didDemoLaunch = true;
}
