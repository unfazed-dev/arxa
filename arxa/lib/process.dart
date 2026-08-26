import 'dart:io';

/// A scripted substitute for [Process.run] — the seam that makes every
/// shell-out unit-testable with NO toolchain in CI. Inject a fake in tests;
/// the production wiring uses [RealProcessRunner].
///
/// Ported from `app/lib/services/pipeline_runner_service.dart` (which carried
/// two private copies — one in the pipeline runner, one in the intake runner).
/// The daemon is the single home for shelling out to the pipeline, the intake
/// engine, and the auth harness.
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

class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

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
