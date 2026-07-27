import 'dart:async';
import 'dart:io';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';

/// A scripted substitute for [Process.run] — the seam that makes the runner
/// unit-testable with NO toolchain in CI (8.8). Inject a fake in tests; the
/// production wiring uses [_RealProcessRunner].
abstract class ProcessRunner {
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  });
}

class RunnerResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const RunnerResult(this.exitCode, this.stdout, this.stderr);
  bool get ok => exitCode == 0;
}

class _RealProcessRunner implements ProcessRunner {
  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    final res = await Process.run(
      executable,
      args,
      environment: environment,
      workingDirectory: workingDirectory,
      runInShell: true,
    );
    return RunnerResult(
      res.exitCode,
      res.stdout.toString(),
      res.stderr.toString(),
    );
  }
}

/// 8.8 — the app **shells out** to the vendored pipeline through this port.
///
/// It does NOT reimplement the pipeline in Dart. The command shape comes from
/// config (R3). If the pipeline binary is absent (not yet vendored, or running
/// where no toolchain exists), the runner reports [PipelineAvailability.absent]
/// — honest, never a faked green.
enum PipelineAvailability { ready, absent }

class PipelineRunnerService {
  PipelineRunnerService([ProcessRunner? runner])
      : _runner = runner ?? _RealProcessRunner();

  final ProcessRunner _runner;

  /// Resolves the pipeline command from config. The vendored pipeline lives at
  /// `pipeline/pipeline.sh` (plan 03); before it's vendored, this is absent.
  Future<RunnerResult> invoke(String stage, {Map<String, String>? env}) async {
    final config = locator<ConfigService>();
    final args = [...config.pipelineArgs, stage];
    return _runner.run(
      config.pipelineCommand,
      args,
      environment: env ?? const {},
    );
  }

  /// Probes availability without running a stage — used by surfaces to show
  /// "pipeline not vendored" honestly instead of pretending to run.
  Future<PipelineAvailability> availability() async {
    try {
      // The runner resolves a relative command; if the binary is missing the
      // shell exits non-zero with a "not found" message. That is the signal.
      final res = await _runner.run('command', ['-v', locator<ConfigService>().pipelineCommand]);
      return res.ok ? PipelineAvailability.ready : PipelineAvailability.absent;
    } catch (_) {
      return PipelineAvailability.absent;
    }
  }
}
