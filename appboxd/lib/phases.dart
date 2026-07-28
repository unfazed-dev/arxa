import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'process.dart';

/// Pipeline phases, in FSM order (pipeline/state/state.schema.json, with
/// `prototype` from pipeline.sh between intake and design).
const phases = [
  'intake',
  'prototype',
  'design',
  'scaffold',
  'review',
  'build',
  'deploy',
];

/// The current phase per pipeline/state/default.state.json, or null when no
/// run has been initialised yet.
String? currentPhase(String repoRoot) {
  final file = File(p.join(repoRoot, 'pipeline', 'state', 'default.state.json'));
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync());
    final phase = (json as Map)['phase'];
    return phase is String ? phase : null;
  } on FormatException {
    return null;
  }
}

class PhaseResult {
  PhaseResult(this.phase, this.exitCode, this.stdout, this.stderr);

  final String phase;
  final int exitCode;
  final String stdout;
  final String stderr;

  Map<String, Object?> toJson() => {
        'phase': phase,
        'exitCode': exitCode,
        'stdout': stdout,
        'stderr': stderr,
      };
}

/// Runs `bash pipeline/pipeline.sh gate <phase>` from the repo root,
/// capturing stdout/stderr and the exit code. Goes through the [ProcessRunner]
/// seam so tests (and surfaces) can drive it with no toolchain present.
Future<PhaseResult> runPhase(String repoRoot, String phase,
    {ProcessRunner? runner}) async {
  final script = p.join(repoRoot, 'pipeline', 'pipeline.sh');
  final res = await (runner ?? const RealProcessRunner()).run(
    'bash',
    [script, 'gate', phase],
    workingDirectory: repoRoot,
  );
  return PhaseResult(phase, res.exitCode, res.stdout, res.stderr);
}

enum PipelineAvailability { ready, absent }

/// Config-driven pipeline invocation (R3: the command shape comes from
/// runtime config, never a literal). Ported from
/// `app/lib/services/pipeline_runner_service.dart`.
///
/// Unlike [runPhase] — which serves the phase-gate endpoint against the
/// repo's real `pipeline/pipeline.sh` — this resolves the vendored pipeline
/// command from config and probes availability honestly: if the binary is
/// absent, the answer is [PipelineAvailability.absent], never a faked green.
class PipelineRunner {
  PipelineRunner({
    required this.repoRoot,
    required this.command,
    required this.args,
    ProcessRunner? runner,
  }) : _runner = runner ?? const RealProcessRunner();

  final String repoRoot;
  final String command;
  final List<String> args;
  final ProcessRunner _runner;

  /// Invokes the pipeline with [stage] appended to the configured args.
  Future<RunnerResult> invoke(String stage, {Map<String, String>? env}) {
    final argv = [
      for (final a in args) p.isRelative(a) ? p.join(repoRoot, a) : a,
      stage,
    ];
    return _runner.run(
      command,
      argv,
      environment: env ?? const {},
      workingDirectory: repoRoot,
    );
  }

  /// Probes availability without running a stage, so callers can report
  /// "pipeline not vendored" honestly instead of pretending to run.
  Future<PipelineAvailability> availability() async {
    try {
      final res = await _runner.run('command', ['-v', command]);
      return res.ok ? PipelineAvailability.ready : PipelineAvailability.absent;
    } catch (_) {
      return PipelineAvailability.absent;
    }
  }
}
