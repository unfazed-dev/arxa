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

import 'package:appboxd/config.dart';
import 'package:appboxd/gate_advertise.dart';
import 'package:appboxd/gate_intake.dart';
import 'package:appboxd/gate_memory.dart';
import 'package:appboxd/gates.dart';
import 'package:appboxd/server.dart' as server;

void main(List<String> args) {
  if (args.isEmpty) {
    _usage();
    exit(2);
  }

  final command = args.first;
  final rest = args.sublist(1);

  switch (command) {
    case 'gate':
      _runGate(rest);
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

void _runGate(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('appbox gate: missing gate name');
    stderr.writeln('  gates: intake freeze structure scaffold coverage memory advertise review native_deps deploy');
    exit(2);
  }

  final gateName = args.first;
  final rest = args.sublist(1);

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

  // Discover repo root by walking up for pipeline/pipeline.sh.
  repoRoot ??= _findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('appbox gate: cannot find repo root (no pipeline/pipeline.sh found)');
    exit(2);
  }

  final ctx = GateContext(
    repoRoot: repoRoot,
    appRoot: appRoot,
    check: check,
    selfTest: selfTest,
  );

  final result = _dispatchGate(gateName, ctx);

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

GateResult _dispatchGate(String name, GateContext ctx) {
  switch (name) {
    case 'memory':
      return memoryGate(ctx);
    case 'advertise':
      return advertiseGate(ctx);
    case 'intake':
      return intakeGate(ctx);
    // The following gates are ported incrementally — uncomment as they land:
    // case 'structure': return structureGate(ctx);
    // case 'deploy': return deployGate(ctx);
    // case 'native_deps': return nativeDepsGate(ctx);
    // case 'review' — already in Dart at gates/review/review.dart (1,658 lines)
    case 'freeze':
    case 'scaffold':
    case 'coverage':
    case 'review':
      return GateResult.env(
        'gate "$name" is not yet ported to Dart — use the bash gate at gates/$name/${name}.sh',
      );
    default:
      return GateResult.env('unknown gate "$name"');
  }
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

String? _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pipeline/pipeline.sh').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
