import 'dart:io';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/credential_service.dart';

/// 8.10 — subscription auth strategy.
///
/// Where an already-authenticated harness CLI is present, the app **shells out**
/// to it (no token held by the app). Only the standalone case — no harness —
/// holds an OAuth token itself. Which path is active is stated in the UI.
class AuthHarnessService {
  /// True when the harness CLI is available (env var or on PATH). Resolved from
  /// config, never a literal (R3).
  Future<bool> get harnessPresent async {
    final config = locator<ConfigService>();
    final envPath = Platform.environment[config.harnessEnvHint];
    if (envPath != null && envPath.isNotEmpty) return true;
    final res = await Process.run('command', ['-v', config.harnessCommand]);
    return res.exitCode == 0;
  }

  /// Shells out to the harness CLI for an authenticated action. The harness
  /// holds the session; the app receives only the action's result. Uses
  /// `dart:io Process` directly — the same shell-out posture as the pipeline
  /// runner (8.8), not a Dart reimplementation of the harness.
  Future<HarnessResult> harnessAction(String action) async {
    final config = locator<ConfigService>();
    final r = await Process.run(config.harnessCommand, [action], runInShell: true);
    return HarnessResult(r.exitCode, r.stdout.toString(), r.stderr.toString());
  }

  /// Standalone path: hold an OAuth token in the Keychain (8.6). Used only when
  /// no harness is present.
  Future<void> storeStandaloneOAuth({
    required String provider,
    required String token,
  }) async {
    await locator<CredentialService>().storeOAuthToken(id: provider, token: token);
  }
}

class HarnessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const HarnessResult(this.exitCode, this.stdout, this.stderr);
  bool get ok => exitCode == 0;
}
