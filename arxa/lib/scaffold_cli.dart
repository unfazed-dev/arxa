// scaffold_cli — CLI entry for `arxa emit scaffold`.
//
// Ports scaffold.py `main(argv)`. Flags:
//   --design-dir <d>   frozen design root (app-root-relative; carries structure.json)
//   --app-root <a>     app root to scaffold lib/ui/views/ under
//   --targets <t1,t2>  comma-separated targets (macos, ios, android, web, ...)
//   --check            compare the on-disk tree against structure.json + targets (drift)
//   --self-test        run the negative-case self-test (R5)
//
// D8: a kit-manifest.json sidecar beside structure.json (written by the
// studio's scaffold picker) is picked up automatically — no flag; the sidecar
// location is the contract, exactly like structure.json itself.
//
// Env fallbacks (preserved verbatim from the Python):
//   KIT_DESIGN_DIR (default 'design'), ARXA_APP (default '.'), ARXA_TARGETS.
//
// Exit: 0 emitted / in-sync · 1 missing input, drift, wrong count, bad flags.

import 'dart:io';

import 'package:arxa/entitlement.dart';
import 'package:arxa/scaffold.dart';
import 'package:path/path.dart' as p;

/// Entry point for `arxa emit scaffold`. Returns the process exit code.
int scaffoldMain(List<String> args) {
  var selfTest = false;
  var check = false;
  String? designDir;
  String? appRoot;
  String? targetsArg;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--self-test':
        selfTest = true;
        break;
      case '--check':
        check = true;
        break;
      case '--design-dir':
        if (++i >= args.length) return _badFlag('--design-dir needs a value');
        designDir = args[i];
        break;
      case '--app-root':
        if (++i >= args.length) return _badFlag('--app-root needs a value');
        appRoot = args[i];
        break;
      case '--targets':
        if (++i >= args.length) return _badFlag('--targets needs a value');
        targetsArg = args[i];
        break;
      case '-h':
      case '--help':
        stdout.writeln(_usage);
        return 0;
      default:
        return _badFlag('unknown flag $a');
    }
  }

  if (selfTest) {
    return runSelfTest();
  }

  // D17 entitlement assertion FIRST (fail-closed): the paywall sits at
  // scaffold — this is the primary hook, in the emitter's execution path so
  // it cannot be skipped via the gate path. --self-test/--help stay free
  // (diagnostics; gating them teaches distrust of red).
  final ent = entitlementAssertion();
  if (!ent.passed) {
    for (final line in ent.failLines) {
      stderr.writeln(line);
    }
    return 1;
  }

  // Explicit --targets wins; ARXA_TARGETS env is the deterministic fallback.
  // Never reads ambient pipeline state silently — a reproducibility run that
  // picked up whatever targets happen to be in state is the stale-green defect
  // the coverage gate warns about.
  final targets = <String>[];
  final src = targetsArg ?? Platform.environment['ARXA_TARGETS'] ?? '';
  for (final t in src.split(',')) {
    if (t.isNotEmpty) targets.add(t);
  }
  if (targets.isEmpty) {
    stderr.writeln('FAIL: no --targets given (and no ARXA_TARGETS env) — pass '
        '--targets explicitly; a scaffold run that reads ambient state is the '
        'stale-green defect (§16)');
    return 1;
  }

  final dd = designDir ?? Platform.environment['KIT_DESIGN_DIR'] ?? 'design';
  // R3: --design-dir must stay app-root-relative.
  if (p.isAbsolute(dd)) {
    stderr.writeln('FAIL: --design-dir must stay app-root-relative (R3: no absolute paths)');
    return 1;
  }

  final ar = appRoot ?? Platform.environment['ARXA_APP'] ?? '.';
  // A wrong root here is not a degraded run, it is a WRONG one: the derivation
  // table and the engine config would be read out of whatever repo cwd happens
  // to sit in. The walk-up used to substitute cwd silently, so running this from
  // a client checkout resolved that client repo as arxa's root and surfaced much
  // later as an unhandled file-not-found inside the emit. Fail where the cause is.
  final repoRoot = findRepoRoot(Directory.current.path);
  if (repoRoot == null) {
    stderr.writeln('arxa emit scaffold: no config/arxa.config.json above '
        '${Directory.current.path} — not an arxa repo checkout. The engine '
        'config and the target-derivation table live in the arxa repo; run '
        'this from inside it.');
    return 2;
  }
  final derivationPath = '$repoRoot/pipeline/state/targets.derivation.json';
  final configPath = '$repoRoot/config/arxa.config.json';

  final designRoot = p.absolute(p.join(ar, dd));
  final absAppRoot = p.absolute(ar);
  return scaffold(designRoot, absAppRoot, targets, derivationPath, configPath,
      check: check);
}

int _badFlag(String msg) {
  stderr.writeln('arxa emit scaffold: $msg');
  stderr.writeln(_usage);
  return 2;
}

const _usage = '''Usage: arxa emit scaffold --design-dir <d> --app-root <a> --targets <t> [--check] [--self-test]

  --design-dir <d>   frozen design root (app-root-relative; carries structure.json)
  --app-root <a>     app root to scaffold lib/ui/views/ under (default: ARXA_APP or '.')
  --targets <t>      comma-separated targets (macos, ios, android, web, pwa, ...)
  --check            drift-check the on-disk tree against structure.json + targets
  --self-test        run the negative-case self-test (R5)

Env: KIT_DESIGN_DIR (default 'design'), ARXA_APP (default '.'), ARXA_TARGETS.''';
