import 'dart:io';

import 'process.dart';

/// 8.10 — subscription auth strategy.
///
/// Where an already-authenticated harness CLI is present, the daemon **shells
/// out** to it (no token held). Only the standalone case — no harness — holds
/// an OAuth token itself. Ported from `app/lib/services/auth_harness_service.dart`
/// (locator → injected command/env hint; raw `Process.run` → [ProcessRunner]).
class HarnessAuth {
  HarnessAuth({
    required this.command,
    required this.envHint,
    ProcessRunner? runner,
  }) : _runner = runner ?? const RealProcessRunner();

  final String command;
  final String envHint;
  final ProcessRunner _runner;

  /// True when the harness CLI is available (env var or on PATH).
  Future<bool> get harnessPresent async {
    final envPath = Platform.environment[envHint];
    if (envPath != null && envPath.isNotEmpty) return true;
    final res = await _runner.run('command', ['-v', command]);
    return res.ok;
  }

  /// Shells out to the harness CLI for an authenticated action. The harness
  /// holds the session; the daemon receives only the action's result.
  Future<RunnerResult> harnessAction(String action) =>
      _runner.run(command, [action]);
}
