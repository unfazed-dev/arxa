// deploy_cli — CLI entry for `arxa deploy`.
//
// Dispatches the three deploy.py subcommands and maps outcomes to the exit-code
// contract (0 ok / 1 halt / 2 usage), HALT lines to stderr:
//   arxa deploy --self-test                                   # assert shapes
//   arxa deploy doctor [--config <f>]                         # preflight (NOT a gate)
//   arxa deploy deploy --target T --version V --account A \
//                       --approval <tok> [--ledger <f>]         # run a target
//
// The ledger path resolves as --ledger > $ARXA_DEPLOY_LEDGER >
// <repo-root>/pipeline/state/deploy-ledger.json (the Python's default, derived
// from the repo root — never a literal — R3). Note: `arxa gate deploy` is the
// strict gate that asserts the deploy triple; this command runs the mechanics.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/deploy.dart';
import 'package:arxa/scaffold.dart' show findRepoRoot;

const String _usage = '''
Usage: arxa deploy <subcommand> [options]

Subcommands:
  --self-test                          Assert every command shape (no toolchain,
                                       no credentials — the one property that
                                       makes a deploy stage self-testable, §17).
  doctor [--config <f>]                Preflight readiness report. NOT a gate —
                                       the gates/deploy gate asserts the deploy
                                       triple, not this.
  deploy --target T --version V --account A --approval <tok> [--ledger <f>]
                                       Run a target's command shapes. REQUIRES a
                                       human approval token; an automated run
                                       reaches the gate and halts, minting
                                       nothing.

Exit codes: 0 ok / 1 halt / 2 usage. HALT lines go to stderr.

Note: `arxa gate deploy` remains the strict deploy gate; this command is the
deploy runtime the gate wraps.''';

/// Entry point for `arxa deploy`. Returns the process exit code (0/1/2).
Future<int> deployMain(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(_usage);
    return 2;
  }
  final cmd = args.first;
  final rest = args.sublist(1);

  switch (cmd) {
    case '--self-test':
      return _runSelfTest();
    case 'doctor':
      return _runDoctor(rest);
    case 'deploy':
      return _runDeploy(rest);
    default:
      stderr.writeln("arxa deploy: unknown subcommand '$cmd'");
      stderr.writeln(_usage);
      return 2;
  }
}

Future<int> _runSelfTest() async {
  final result = await runDeploySelfTest();
  for (final p in result.passed) {
    print('  PASS  $p');
  }
  for (final f in result.failed) {
    stderr.writeln('  FAIL  $f');
  }
  print('deploy self-test: ${result.passed.length} passed, '
      '${result.failed.length} failed');
  return result.allPassed ? 0 : 1;
}

int _runDoctor(List<String> args) {
  final o = _parse(args);
  if (o == null) return 2;
  final rep = Deployer().doctor(configPath: o['config']);
  print(const JsonEncoder.withIndent('  ').convert(rep.toMap()));
  return 0;
}

Future<int> _runDeploy(List<String> args) async {
  final o = _parse(args);
  if (o == null) return 2;
  for (final required in ['target', 'version', 'account', 'approval']) {
    if (o[required] == null) {
      stderr.writeln('arxa deploy deploy: --$required required');
      stderr.writeln(_usage);
      return 2;
    }
  }
  final ledgerPath = _resolveLedger(o['ledger']);
  try {
    final res = await Deployer(ledgerPath: ledgerPath).deploy(
      target: o['target']!,
      version: o['version']!,
      account: o['account']!,
      approval: o['approval']!,
    );
    print(const JsonEncoder.withIndent('  ').convert(res.toMap()));
    return 0;
  } on DeployHalted catch (e) {
    stderr.writeln('HALT: $e');
    return 1;
  }
}

/// Resolve the ledger path: --ledger > $ARXA_DEPLOY_LEDGER > repo-root
/// default (mirrors deploy.py's DEF_LEDGER, derived from the repo root).
String _resolveLedger(String? flag) {
  if (flag != null && flag.isNotEmpty) return flag;
  final env = Platform.environment['ARXA_DEPLOY_LEDGER'];
  if (env != null && env.isNotEmpty) return env;
  final root = findRepoRoot() ?? Directory.current.path;
  return '$root/pipeline/state/deploy-ledger.json';
}


/// Minimal `--flag value` parser for the deploy flags. Returns null + writes
/// usage on an unknown flag.
Map<String, String>? _parse(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--')) {
      final name = a.substring(2);
      if (i + 1 >= args.length) {
        stderr.writeln("arxa deploy: missing value for --$name");
        stderr.writeln(_usage);
        return null;
      }
      out[name] = args[++i];
    } else {
      stderr.writeln("arxa deploy: unexpected argument '$a'");
      stderr.writeln(_usage);
      return null;
    }
  }
  return out;
}
