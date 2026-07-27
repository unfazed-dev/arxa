import 'dart:async';
import 'dart:io';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/pipeline_runner_service.dart'
    show ProcessRunner, RunnerResult;

/// 10.5 — drives the elicitation engine (`skills/app-box-intake/intake.py`)
/// headless via the **same** [ProcessRunner] seam [PipelineRunnerService] uses.
///
/// The wizard is a view over the phase, not a parallel implementation: it
/// collects answers in the UI, writes them to a JSON file (the same format the
/// headless path uses), then shells out to `intake.py emit`. The engine is the
/// single source of emission — **if the wizard and the headless phase can
/// disagree, plan 10 has failed** (DW1: byte-identical output from the same
/// answers).
///
/// Architecture §22: intake ELICITS; it NEVER generates design or code. This
/// service invokes the engine; it does not format the brief, author the
/// registry, or invent any content. Every field carries provenance
/// (client|founder|inferred); `inferred` fields are visibly marked in the
/// emitted brief by the engine.
class IntakeRunnerService {
  IntakeRunnerService([ProcessRunner? runner])
      : _runner = runner ?? _RealProcessRunner();

  final ProcessRunner _runner;

  /// Emits brief.md + registry.json from [answersPath] by shelling out to the
  /// engine. The wizard writes the answers JSON file (the same shape the
  /// headless path uses); this method invokes the ONE engine on it.
  ///
  /// Returns the engine's [RunnerResult]: exit 0 = emitted, exit 1 = invalid
  /// input (nothing written — no partial artefacts), exit 2 = usage error.
  Future<RunnerResult> emit({
    required String answersPath,
    String? briefOut,
    String? registryOut,
  }) async {
    final config = locator<ConfigService>();
    final args = <String>[
      config.intakeScript,
      'emit',
      '--answers', answersPath,
      if (briefOut != null) ...['--brief-out', briefOut],
      if (registryOut != null) ...['--registry-out', registryOut],
    ];
    return _runner.run(config.intakeCommand, args);
  }
}

/// The production [ProcessRunner] — delegates to [Process.run]. A mirror of the
/// one in pipeline_runner_service.dart (which is private); kept local so the
/// intake runner has no dependency on a sibling service's private members.
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
