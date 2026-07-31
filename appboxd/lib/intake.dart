import 'process.dart';

/// 10.5 — drives the elicitation engine (`skills/appbox-intake/intake.py`)
/// headless via the [ProcessRunner] seam. Ported from
/// `app/lib/services/intake_runner_service.dart` (locator → injected config).
///
/// Intake ELICITS; it NEVER generates design or code (architecture §22). This
/// invokes the ONE engine on an answers file; it does not format the brief or
/// author the registry.
class IntakeRunner {
  IntakeRunner({
    required this.command,
    required this.script,
    ProcessRunner? runner,
  }) : _runner = runner ?? const RealProcessRunner();

  final String command;
  final String script;
  final ProcessRunner _runner;

  /// Emits brief.md + registry.json from [answersPath] by shelling out to the
  /// engine. Exit 0 = emitted, exit 1 = invalid input (nothing written — no
  /// partial artefacts), exit 2 = usage error.
  Future<RunnerResult> emit({
    required String answersPath,
    String? briefOut,
    String? registryOut,
    String? workingDirectory,
  }) {
    final args = <String>[
      script,
      'emit',
      '--answers', answersPath,
      if (briefOut != null) ...['--brief-out', briefOut],
      if (registryOut != null) ...['--registry-out', registryOut],
    ];
    return _runner.run(command, args, workingDirectory: workingDirectory);
  }
}
