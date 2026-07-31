// appbox — the unified binary entry point.
//
// Subcommands:
//   appbox gate <name> [--app <root>] [--check]   — run a gate
//   appbox serve [--port <n>]                      — start the HTTP daemon
//   appbox lens <args>                             — visual gate (future)
//   appbox emit <name> <args>                      — run an emitter (future)
//
// Planned: `dart compile exe bin/appbox.dart` → self-contained binary.

import 'dart:io';

import 'package:appboxd/blueprint.dart';
import 'package:appboxd/config.dart';
import 'package:appboxd/emit_htmx.dart';
import 'package:appboxd/emit_playground.dart';
import 'package:appboxd/emit_stage.dart';
import 'package:appboxd/emit_structure.dart';
import 'package:appboxd/generate_view.dart';
import 'package:appboxd/synthesize.dart';
import 'package:appboxd/transform_tokens.dart';
import 'package:appboxd/gate_advertise.dart';
import 'package:appboxd/gate_coverage.dart';
import 'package:appboxd/gate_deploy.dart';
import 'package:appboxd/gate_freeze.dart';
import 'package:appboxd/gate_intake.dart';
import 'package:appboxd/gate_memory.dart';
import 'package:appboxd/gate_native_deps.dart';
import 'package:appboxd/gate_scaffold.dart';
import 'package:appboxd/gate_structure.dart';
import 'package:appboxd/gate_runner.dart';
import 'package:appboxd/gates.dart';
import 'package:appboxd/server.dart' as server;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(2);
  }

  final command = args.first;
  final rest = args.sublist(1);

  switch (command) {
    case 'gate':
      await _runGate(rest);
      break;
    case 'emit':
      _runEmit(rest);
      break;
    case 'serve':
      _runServe(rest);
      break;
    case '--help' || '-h':
      _usage();
      break;
    default:
      stderr.writeln('appbox: unknown command "$command"');
      _usage();
      exit(2);
  }
}

void _usage() {
  stderr.writeln('''
Usage: appbox <command> [options]

Commands:
  gate <name>    Run a gate by name (intake, freeze, structure, scaffold,
                 coverage, memory, advertise, review, native_deps, deploy)
  serve          Start the HTTP daemon (appboxd)
  lens           Visual gate (appbox lens — future)
  emit <name>    Run an emitter (future)

Options:
  --app <root>   App root (defaults to repo root)
  --check        Drift-check mode (no writes)
  --self-test    Run the gate's embedded self-test
  --port <n>     Port for serve (default 8787)
  --sarif <path> Write SARIF output to <path>
''');
}

// ── gate ───────────────────────────────────────────────────────────

Future<void> _runGate(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('appbox gate: missing gate name');
    stderr.writeln('  gates: intake freeze structure scaffold coverage memory advertise review native_deps deploy');
    exit(2);
  }

  final gateName = args.first;
  final rest = args.sublist(1);

  // --all runs the full gate suite.
  if (gateName == '--all' || gateName == 'all') {
    await _runAllGates(rest);
    return;
  }

  // Parse common flags.
  String? appRoot;
  var check = false;
  var selfTest = false;
  String? sarifPath;
  String? repoRoot;

  for (var i = 0; i < rest.length; i++) {
    switch (rest[i]) {
      case '--app':
        appRoot = rest[++i];
        break;
      case '--check':
        check = true;
        break;
      case '--self-test':
        selfTest = true;
        break;
      case '--sarif':
        sarifPath = rest[++i];
        break;
      case '--repo':
        repoRoot = rest[++i];
        break;
      default:
        stderr.writeln('appbox gate: unknown flag ${rest[i]}');
        exit(2);
    }
  }

  // Discover repo root by walking up for config/appbox.config.json.
  repoRoot ??= _findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('appbox gate: cannot find repo root (no config/appbox.config.json found)');
    exit(2);
  }

  final ctx = GateContext(
    repoRoot: repoRoot,
    appRoot: appRoot,
    check: check,
    selfTest: selfTest,
  );

  final result = await _dispatchGate(gateName, ctx);

  // Print details.
  for (final d in result.details) {
    print(d);
  }
  print(result.summary);

  // SARIF output.
  if (sarifPath != null) {
    File(sarifPath).writeAsStringSync(ctx.sarif.flush());
  }

  exit(result.exitCode);
}

Future<void> _runAllGates(List<String> args) async {
  String? repoRoot;
  String? appRoot;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--app':
        appRoot = args[++i];
        break;
      case '--repo':
        repoRoot = args[++i];
        break;
    }
  }
  repoRoot ??= _findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('appbox gate --all: cannot find repo root');
    exit(2);
  }
  final ctx = GateContext(repoRoot: repoRoot, appRoot: appRoot);
  final suite = await runAllGates(ctx);
  for (final s in suite.summaries) {
    print(s);
  }
  exit(suite.exitCode);
}

Future<GateResult> _dispatchGate(String name, GateContext ctx) async {
  switch (name) {
    case 'memory':
      return memoryGate(ctx);
    case 'advertise':
      return advertiseGate(ctx);
    case 'intake':
      return intakeGate(ctx);
    case 'structure':
      return structureGate(ctx);
    case 'deploy':
      return deployGate(ctx);
    case 'native_deps':
      return nativeDepsGate(ctx);
    case 'coverage':
      return coverageGate(ctx);
    case 'scaffold':
      return scaffoldGate(ctx);
    case 'freeze':
      return freezeGate(ctx);
    case 'review':
      // review.dart is 1,658 lines at gates/review/review.dart — call via dart run.
      return _runReviewGate(ctx);
    default:
      return GateResult.env('unknown gate "$name"');
  }
}

Future<GateResult> _runReviewGate(GateContext ctx) async {
  final gatePath = '${ctx.repoRoot}/gates/review/review.dart';
  if (!File(gatePath).existsSync()) {
    return GateResult.env('review gate not found at $gatePath');
  }
  final args = <String>['run', gatePath];
  if (ctx.appRoot != null) args.addAll(['--app', ctx.appRoot!]);
  final result = Process.runSync('dart', args, workingDirectory: ctx.repoRoot);
  final out = (result.stdout as String).trim();
  final err = (result.stderr as String).trim();
  if (result.exitCode == 0) {
    return GateResult.ok('review: ${out.split('\n').last}');
  } else if (result.exitCode == 2) {
    return GateResult.env('review: env/not-applicable');
  }
  return GateResult.fail('review: ${(err.isNotEmpty ? err : out).split('\n').first}',
      err.isNotEmpty ? err.split('\n') : out.split('\n'));
}

// ── emit ───────────────────────────────────────────────────────────

void _runEmit(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('appbox emit: missing emitter name');
    stderr.writeln('  emitters: structure, htmx, playground, transform_tokens,');
    stderr.writeln('            synthesize, blueprint, emit_stage, generate_view');
    exit(2);
  }

  final emitter = args.first;
  final rest = args.sublist(1);

  // Parse common flags.
  String? appRoot;
  String? designDir;
  var check = false;

  // Collect positional args (not flags).
  final positional = <String>[];
  for (var i = 0; i < rest.length; i++) {
    switch (rest[i]) {
      case '--app':
        appRoot = rest[++i];
        break;
      case '--design-dir':
        designDir = rest[++i];
        break;
      case '--check':
        check = true;
        break;
      case '--apply':
        break;
      case '--tokens':
      case '--out':
      case '--breakdown':
      case '--spec':
      case '--target':
      case '--blueprint':
      case '--primitives':
      case '--maps':
      case '--design-html':
      case '--catalog':
        // Consume the value so it doesn't become positional.
        i++;
        break;
      default:
        if (rest[i].startsWith('--')) {
          i++; // skip flag value if present
        } else {
          positional.add(rest[i]);
        }
    }
  }

  final repoRoot = _findRepoRoot() ?? Directory.current.path;
  appRoot ??= repoRoot;
  designDir ??= 'designs/appbox';

  switch (emitter) {
    case 'structure':
      exit(emitStructure('$appRoot/$designDir', check: check));
    case 'transform_tokens':
      exit(transformTokens('$appRoot/$designDir/tokens.json', '$appRoot/$designDir'));
    case 'htmx':
      emitHtmx('$appRoot/$designDir', check: check).then((rc) => exit(rc));
      return;
    case 'playground':
      emitPlayground('$appRoot/$designDir', check: check).then((rc) => exit(rc));
      return;
    case 'synthesize':
      if (positional.length < 5) {
        stderr.writeln('appbox emit synthesize: needs <primitives> <maps> <design-html> <catalog> <out>');
        exit(2);
      }
      exit(synthesize(positional[0], positional[1], positional[2], positional[3], positional[4]));
    case 'blueprint':
      if (positional.length < 2) {
        stderr.writeln('appbox emit blueprint: needs <breakdown.json> <out-dir> [--tokens <path>]');
        exit(2);
      }
      exit(buildBlueprint(positional[0], positional[1], tokensPath: _flagValue(rest, '--tokens')));
    case 'emit_stage':
      if (positional.length < 2) {
        stderr.writeln('appbox emit emit_stage: needs <blueprint-dir> <target-dir> [--apply]');
        exit(2);
      }
      exit(emitStage(positional[0], positional[1], apply: rest.contains('--apply')));
    case 'generate_view':
      if (positional.length < 2) {
        stderr.writeln('appbox emit generate_view: needs <spec.json> <out.dart> [--tokens <path>]');
        exit(2);
      }
      exit(generateView(positional[0], positional[1], tokensPath: _flagValue(rest, '--tokens')));
  }
  stderr.writeln('appbox emit: unknown emitter "$emitter"');
  exit(2);
}

// ── serve ──────────────────────────────────────────────────────────

void _runServe(List<String> args) {
  var port = AppboxdConfig.defaultPort;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--port' && i + 1 < args.length) {
      port = int.tryParse(args[++i]) ?? AppboxdConfig.defaultPort;
    }
  }
  final repoRoot = _findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('appbox serve: cannot find repo root');
    exit(2);
  }
  final config = AppboxdConfig.load(repoRoot, port: port);
  server.startServer(config).then((s) {
    stdout.writeln('appbox serving on http://127.0.0.1:${s.port}');
  });
}

// ── helpers ────────────────────────────────────────────────────────

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

String? _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/config/appbox.config.json').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
