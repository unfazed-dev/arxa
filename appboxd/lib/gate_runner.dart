// Gate runner — orchestrates all gates in dependency order.
// Dart port of gates/run_all.sh (178 lines).
//
// Strangler pattern: Dart gates run natively; gates not yet ported
// fall back to the bash gate via Process.run. The fallback shrinks
// to zero as each gate is ported.

import 'dart:io';

import 'package:appboxd/gate_advertise.dart';
import 'package:appboxd/gate_coverage.dart';
import 'package:appboxd/gate_deploy.dart';
import 'package:appboxd/gate_fidelity.dart';
import 'package:appboxd/gate_freeze.dart';
import 'package:appboxd/gate_intake.dart';
import 'package:appboxd/gate_kind_registry.dart';
import 'package:appboxd/gate_lens.dart';
import 'package:appboxd/gate_memory.dart';
import 'package:appboxd/gate_native_deps.dart';
import 'package:appboxd/gate_scaffold.dart';
import 'package:appboxd/gate_structure.dart';
import 'package:appboxd/gate_tests.dart';
import 'package:appboxd/gates.dart';
import 'package:appboxd/memory.dart';
import 'package:path/path.dart' as p;

/// The gate execution order (matches gates/run_all.sh:148-164).
const gateOrder = [
  'intake',
  'freeze',
  'structure',
  'kind_registry',
  'scaffold',
  'fidelity',
  'coverage',
  'tests',
  'memory',
  'advertise',
  'review',
  'native_deps',
  'lens',
  'deploy',
];

/// Result of running the full gate suite.
class SuiteResult {
  final int passed;
  final int failed;
  final int skipped;
  final List<String> summaries;

  SuiteResult({
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.summaries,
  });

  bool get allPassed => failed == 0;
  int get exitCode => failed > 0 ? 1 : 0;
}

/// Run all gates in dependency order.
/// Dart-portable gates run natively; others fall back to bash.
Future<SuiteResult> runAllGates(GateContext ctx) async {
  var passed = 0, failed = 0, skipped = 0;
  final summaries = <String>[];

  for (final name in gateOrder) {
    final result = await _runSingleGate(name, ctx);

    if (result == null) {
      // Gate not available — skip with a note.
      skipped++;
      summaries.add('  ⊘ $name: skipped (not yet ported, bash gate unavailable)');
      continue;
    }

    summaries.add('  ${result.passed ? "✓" : "✗"} $name: ${result.summary}');
    for (final d in result.details) {
      summaries.add('    $d');
    }

    if (result.passed) {
      passed++;
    } else if (result.exitCode == envExit) {
      skipped++;
    } else {
      failed++;
    }
  }

  summaries.insert(0, 'appbox gate suite: $passed passed, $failed failed, $skipped skipped');
  return SuiteResult(passed: passed, failed: failed, skipped: skipped, summaries: summaries);
}

/// Run a single gate by name. Returns null if the gate is unavailable.
/// Public for phase-gate dispatch from phases.dart.
Future<GateResult?> runGate(String name, GateContext ctx) => _runSingleGate(name, ctx);

/// Run a single gate by name. Returns null if the gate is unavailable.
Future<GateResult?> _runSingleGate(String name, GateContext ctx) async {
  final sw = Stopwatch()..start();

  // Try Dart gate first.
  final dartResult = await _tryDartGate(name, ctx);
  if (dartResult != null) {
    await _appendGateRunEvent(name, dartResult, ctx, sw.elapsed);
    return dartResult;
  }

  // Fall back to bash gate (strangler — unported gates still work).
  final bashResult = await _tryBashGate(name, ctx);
  if (bashResult != null) {
    await _appendGateRunEvent(name, bashResult, ctx, sw.elapsed);
  }
  return bashResult;
}

/// M1: the gate runner is a deterministic writer of raw memory events
/// (engine.dart writes stage_run; this writes gate_run). Best-effort —
/// a logging failure warns, never fails the gate run.
Future<void> _appendGateRunEvent(
    String name, GateResult result, GateContext ctx, Duration duration) async {
  try {
    await EventLog(p.join(ctx.repoRoot, 'pipeline', 'state'))
        .append(MemoryEvent(
      kind: MemoryKinds.gateRun,
      actor: 'gate-runner',
      payload: {
        'gate': name,
        'passed': result.passed,
        'exit_code': result.exitCode,
        'duration_ms': duration.inMilliseconds,
      },
    ));
  } catch (e) {
    stderr.writeln('gate-runner: WARN memory event append failed: $e');
  }
}

/// Dispatch to a Dart-ported gate. Returns null if not yet ported.
Future<GateResult?> _tryDartGate(String name, GateContext ctx) async {
  switch (name) {
    case 'memory':
      return memoryGate(ctx);
    case 'advertise':
      return advertiseGate(ctx);
    case 'intake':
      return intakeGate(ctx, project: ctx.project);
    case 'structure':
      return structureGate(ctx);
    case 'kind_registry':
      return kindRegistryGate(ctx);
    case 'deploy':
      return deployGate(ctx);
    case 'native_deps':
      return nativeDepsGate(ctx);
    case 'lens':
      return lensGate(ctx);
    case 'coverage':
      return coverageGate(ctx);
    case 'fidelity':
      return fidelityGate(ctx);
    case 'scaffold':
      return scaffoldGate(ctx);
    case 'tests':
      return testsGate(ctx, project: ctx.project);
    case 'freeze':
      return freezeGate(ctx);
    default:
      return null; // not yet ported to Dart
  }
}

/// Fall back to the bash gate at `gates/<name>/<name>.sh`.
/// Returns null if the bash gate doesn't exist.
Future<GateResult?> _tryBashGate(String name, GateContext ctx) async {
  final extensions = {'intake': '.sh', 'freeze': '.sh', 'structure': '.sh',
    'scaffold': '.sh', 'coverage': '.sh', 'review': '.dart',
    'native_deps': '.sh', 'deploy': '.sh'};
  final ext = extensions[name];
  if (ext == null) return null;

  final gatePath = '${ctx.repoRoot}/gates/$name/$name$ext';
  if (!File(gatePath).existsSync()) return null;

  List<String> cmd;
  if (ext == '.dart') {
    cmd = ['dart', 'run', gatePath];
  } else {
    cmd = ['bash', gatePath];
  }
  if (ctx.appRoot != null) cmd.addAll(['--app', ctx.appRoot!]);

  final result = await Process.run(cmd.first, cmd.sublist(1),
      workingDirectory: ctx.repoRoot);

  final stdout = (result.stdout as String).trim();
  final stderr = (result.stderr as String).trim();

  if (result.exitCode == 0) {
    return GateResult.ok('$name (bash fallback): ${stdout.split('\n').last}');
  } else if (result.exitCode == 2) {
    return GateResult.env('$name (bash fallback): env/not-applicable');
  } else {
    final msg = stderr.isNotEmpty ? stderr : stdout;
    return GateResult.fail('$name (bash fallback): ${msg.split('\n').first}',
        msg.split('\n'));
  }
}
