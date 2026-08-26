// arxa — the unified binary entry point.
//
// Subcommands:
//   arxa gate <name> [--app <root>] [--check] [--project <n>] — run a gate
//   arxa serve [--port <n>]                      — start the HTTP daemon
//   arxa lens <verb> <args>                      — visual gate
//   arxa design <sub> <args>                     — designer runtimes
//   arxa deploy <sub> <args>                     — deploy runtime
//   arxa intake <sub> <args>                     — elicitation engine
//   arxa emit <name> <args>                      — run an emitter
//
// Planned: `dart compile exe bin/arxa.dart` → self-contained binary.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/arch_guard.dart';
import 'package:arxa/blueprint.dart';
import 'package:arxa/config.dart';
import 'package:arxa/credential_cli.dart';
import 'package:arxa/crud.dart';
import 'package:arxa/design_cli.dart';
import 'package:arxa/design_tools.dart' show scriptRepoRoot;
import 'package:arxa/repo_project.dart' show findRepoProject;
import 'package:arxa/deploy_cli.dart';
import 'package:arxa/docs_lint.dart';
import 'package:arxa/emit_htmx.dart';
import 'package:arxa/emit_playground.dart';
import 'package:arxa/emit_stage.dart';
import 'package:arxa/emit_structure.dart';
import 'package:arxa/generate_view.dart';
import 'package:arxa/gen_freshness.dart';
import 'package:arxa/synthesize.dart';
import 'package:arxa/theme_map.dart';
import 'package:arxa/trace.dart';
import 'package:arxa/transform_tokens.dart';
import 'package:arxa/validate_docs.dart';
import 'package:arxa/gate_advertise.dart';
import 'package:arxa/gate_coverage.dart';
import 'package:arxa/gate_deploy.dart';
import 'package:arxa/gate_fidelity.dart';
import 'package:arxa/gate_freeze.dart';
import 'package:arxa/gate_intake.dart';
import 'package:arxa/gate_kind_registry.dart';
import 'package:arxa/gate_lens.dart';
import 'package:arxa/gate_memory.dart';
import 'package:arxa/gate_native_deps.dart';
import 'package:arxa/gate_scaffold.dart';
import 'package:arxa/gate_structure.dart';
import 'package:arxa/gate_tests.dart';
import 'package:arxa/gate_runner.dart';
import 'package:arxa/gates.dart';
import 'package:arxa/lens_cli.dart';
import 'package:arxa/lint_conventions.dart';
import 'package:arxa/palette.dart';
import 'package:arxa/server.dart' as server;
import 'package:arxa/scaffold_cli.dart';
import 'package:arxa/story_map_cli.dart';
import 'package:arxa/tier1.dart';
import 'package:arxa/api_map_scan.dart';
import 'package:arxa/capability_scan.dart';
import 'package:arxa/entitlement_cli.dart';
import 'package:arxa/gen_playbook.dart';
import 'package:arxa/intake_cli.dart';
import 'package:arxa/memory_cli.dart';
import 'package:arxa/moodboard_check.dart';
import 'package:arxa/project_cli.dart';
import 'package:arxa/kb_build.dart';
import 'package:arxa/kb_check.dart';
import 'package:arxa/kit_conventions.dart';
import 'package:arxa/kit_facts.dart';
import 'package:arxa/kit_lock.dart';
import 'package:arxa/scaffold.dart' show findRepoRoot;

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
    case 'lens':
      exit(await runLensCli(rest));
    case 'design':
      exit(await designMain(rest));
    case 'deploy':
      exit(await deployMain(rest));
    case 'intake':
      exit(intakeMain(rest));
    case 'project':
      exit(projectMain(rest));
    case 'moodboard':
      exit(moodboardCheckMain(rest));
    case 'memory':
      exit(await memoryCli(rest));
    case 'credentials':
      exit(await credentialsMain(
        rest,
        // Anchor on the executing checkout, not only the cwd — harness
        // credential shells (`!arxa credentials exec …` in Pi's models.json)
        // run from arbitrary directories.
        catalogPath:
            '${findRepoRoot() ?? scriptRepoRoot() ?? Directory.current.path}/config/credentials.catalog.json',
      ));
    case 'emit':
      _runEmit(rest);
      break;
    case 'crud':
      _runCrud(rest);
      break;
    case 'serve':
      _runServe(rest);
      break;
    case 'entitlement':
      exit(entitlementMain(rest));
    case 'lint':
      _runLint(rest);
      break;
    case 'docs':
      _runDocs(rest);
      break;
    case 'kb':
      _runKb(rest);
      break;
    case '--help' || '-h':
      _usage();
      break;
    default:
      stderr.writeln('arxa: unknown command "$command"');
      _usage();
      exit(2);
  }
}

void _usage() {
  stderr.writeln('''
Usage: arxa <command> [options]

Commands:
  gate <name>    Run a gate by name (arch, gen-freshness, trace, intake, freeze,
                 structure, kind_registry, scaffold, coverage, tests, memory,
                 advertise, review, native_deps, lens, deploy, tier1, capability,
                 api-map)
                 tier1 accepts --promote: on a green run, write the evidence
                 ledger + port-tested tiers (the only path that sets a tier)
  crud <op>      Feature CRUD on the authored layer (list/show/create/update/
                 rename/delete/verify — the one write path, §18)
  serve          Start the HTTP daemon (arxa)
  lens <verb>    Visual gate — capture/compare/tokens/dom/a11y/net/skeleton/
                 crawl/ocr/... and native capture (arxa lens --help)
  design <sub>   Designer runtimes — lint, check-ladder, check-wiring,
                 pseudolocalize, vendor-fetch, doctor (arxa design --help)
  deploy <sub>   Deploy runtime — doctor, deploy, --self-test (arxa deploy --help)
  intake <sub>   Elicitation engine — emit, seed, validate (arxa intake --help)
  project <sub>  Projects — init (native ~/.arxa), init --repo <dir> --kind
                 site|app (the repo law: marker + 8 stage folders), sync,
                 resolve, use, list (arxa project --help)
  moodboard <sub> Scored-moodboard gate — check <intake-dir> recomputes
                 weighted totals, enforces floors + locked criteria
                 (arxa moodboard check --help)
  memory <verb>  Project-scoped memory — add/recall/why on
                 <project>/memory/facts (arxa memory --help)
  credentials <verb>  Unified credential manager — list/check/set/unset over
                 the catalog + OS vault (never prints secrets)
  emit <name>    Run an emitter: structure, htmx, playground, transform_tokens,
                 synthesize, blueprint, emit_stage, generate_view, theme-map,
                 palette, story-map, scaffold
  lint [root]    Scan for repo convention violations (R2, R3)
  docs [root]    Validate the docs/INDEX.md contract (dead links fail,
                 unindexed docs + KB-lint orphans warn)
  kb <sub>       Kit introspection: facts, build, check, lock, playbook,
                 conventions
  entitlement <sub>  Cached entitlement JWT — status/verify (the D17 scaffold
                 paywall's operator surface); tokens are issued by the
                 /activate Edge Function (no client-side mint)

Options:
  --app <root>   App root (defaults to repo root)
  --check        Drift-check mode (no writes)
  --self-test    Run the gate's embedded self-test
  --port <n>     Port for serve (default 8787)
  --sarif <path> Write SARIF output to <path>
  --project <n>  Gate a project's own shell (~/.arxa/projects/<n>) instead of
                 the studio — intake + tests gates only
''');
}

// ── gate ───────────────────────────────────────────────────────────

Future<void> _runGate(List<String> args) async {
  const gateNames = 'arch gen-freshness trace intake freeze structure kind_registry scaffold '
      'coverage tests memory advertise review native_deps lens deploy tier1 '
      'capability api-map';
  if (args.isEmpty) {
    stderr.writeln('arxa gate: missing gate name');
    stderr.writeln('  gates: $gateNames');
    exit(2);
  }

  final gateName = args.first;
  final rest = args.sublist(1);

  // `arxa gate --help` is help, not an unknown gate name — it used to fall
  // through to the resolver and exit 2 on `unknown gate "--help"`.
  if (gateName == '--help' || gateName == '-h') {
    stdout.writeln('Usage: arxa gate <name> [options]');
    stdout.writeln('');
    stdout.writeln('Gates: $gateNames');
    stdout.writeln('');
    stdout.writeln('Common flags:');
    stdout.writeln('  --app <root>    App root (default: the nearest arxa.json');
    stdout.writeln('                  marker at or above cwd, else the repo root)');
    stdout.writeln('  --check         Drift-check mode (no writes, no test runs)');
    stdout.writeln('  --self-test     Run the gate\'s embedded self-test');
    stdout.writeln('  --sarif <path>  Write SARIF output to <path>');
    stdout.writeln('  --repo <root>   Repo root override');
    stdout.writeln('  --project <n>   Gate a project shell in ~/.arxa/projects/<n>');
    exit(0);
  }

  // --all runs the full gate suite.
  if (gateName == '--all' || gateName == 'all') {
    await _runAllGates(rest);
    return;
  }

  // arch is special: it validates a target's lib/ tree directly and takes
  // --target <dir> rather than a GateContext/repo-root discovery.
  if (gateName == 'arch') {
    final rc = _runArchGate(rest);
    exit(rc);
  }

  // tier1 is special: a pure in-memory self-check (auth + payments call-shape
  // verification). It needs no repo root, no credentials, no toolchain — so it
  // bypasses the GateContext/repo-root discovery like arch. `--promote` (green
  // runs only) writes the evidence ledger + registry tiers (plan 13.3).
  if (gateName == 'tier1') {
    exit(_runTier1Gate(rest));
  }

  // gen-freshness is also --target-driven (runs build_runner in a temp copy of
  // a Flutter target), so it bypasses the GateContext/repo-root path.
  if (gateName == 'gen-freshness') {
    final rc = await _runGenFreshnessGate(rest);
    exit(rc);
  }

  // trace is --target-driven: it cross-references a breakdown.json against the
  // emitted views/VMs/router in a target, so it bypasses repo-root discovery.
  if (gateName == 'trace') {
    final rc = _runTraceGate(rest);
    exit(rc);
  }

  // capability + api-map are consumer-app gates (scan the app that uses the kit,
  // not the kit itself) — bypass the GateContext/repo-root path.
  if (gateName == 'capability') {
    exit(_runCapabilityGate(rest));
  }
  if (gateName == 'api-map') {
    exit(_runApiMapGate(rest));
  }

  // Parse common flags.
  String? appRoot;
  var check = false;
  var selfTest = false;
  String? sarifPath;
  String? repoRoot;
  String? project;

  for (var i = 0; i < rest.length; i++) {
    switch (rest[i]) {
      case '--project':
        if (i + 1 >= rest.length) {
          stderr.writeln('arxa gate: --project requires a value');
          exit(2);
        }
        project = rest[++i];
        break;
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
        stderr.writeln('arxa gate: unknown flag ${rest[i]}');
        exit(2);
    }
  }

  // Discover repo root by walking up for config/arxa.config.json.
  repoRoot ??= findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('arxa gate: cannot find repo root (no config/arxa.config.json found)');
    exit(2);
  }

  // A repo-mode app owns its pipeline state (the arxa law), so standing inside
  // one and running a gate should gate THAT app, not fall through to arxa's
  // own studio. --app stays the explicit override; this only fills the gap.
  // No arxa.json sits above the arxa checkout, so gating arxa is unaffected.
  appRoot ??= findRepoProject()?.dir;

  final ctx = GateContext(
    repoRoot: repoRoot,
    appRoot: appRoot,
    check: check,
    selfTest: selfTest,
  );

  final result = await _dispatchGate(gateName, ctx, project: project);

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
  String? project;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--app':
        appRoot = args[++i];
        break;
      case '--repo':
        repoRoot = args[++i];
        break;
      // Parsed and carried, not dropped. The single-gate path already refuses
      // --project on gates that cannot use it; --all used to accept the flag
      // and silently gate the studio instead of the project asked for, which
      // is worse than either answer.
      case '--project':
        project = args[++i];
        break;
    }
  }
  repoRoot ??= findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('arxa gate --all: cannot find repo root');
    exit(2);
  }

  // A repo-mode app owns its pipeline state (the arxa law), so standing inside
  // one and running a gate should gate THAT app, not fall through to arxa's
  // own studio. --app stays the explicit override; this only fills the gap.
  // No arxa.json sits above the arxa checkout, so gating arxa is unaffected.
  appRoot ??= findRepoProject()?.dir;
  final ctx = GateContext(repoRoot: repoRoot, appRoot: appRoot, project: project);
  final suite = await runAllGates(ctx);
  for (final s in suite.summaries) {
    print(s);
  }
  exit(suite.exitCode);
}

Future<GateResult> _dispatchGate(String name, GateContext ctx,
    {String? project}) async {
  // Only intake and tests read a project shell so far — refuse rather than
  // accept the flag and quietly gate the studio instead of the project asked
  // for.
  if (project != null && name != 'intake' && name != 'tests') {
    return GateResult.env('gate "$name" does not support --project '
        '(intake + tests only)');
  }
  switch (name) {
    case 'memory':
      return memoryGate(ctx);
    case 'advertise':
      return advertiseGate(ctx);
    case 'intake':
      return intakeGate(ctx, project: project);
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
      return testsGate(ctx, project: project);
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

// ── tier1 ──────────────────────────────────────────────────────────

int _runTier1Gate(List<String> args) {
  final promote = args.contains('--promote');
  final result = runTier1Suites();
  for (final p in result.passed) {
    print('  PASS  $p');
  }
  for (final f in result.failed) {
    stderr.writeln('  FAIL  $f');
  }
  print('tier1: ${result.passed.length} passed, ${result.failed.length} failed');
  if (promote) {
    if (!result.allPassed) {
      stderr.writeln('tier1 --promote: refusing to promote — suites failed');
      return 1;
    }
    final root = findRepoRoot();
    if (root == null) {
      stderr.writeln('tier1 --promote: cannot find repo root');
      return 2;
    }
    final bumped = promoteTier1(
      [for (final (kitDir, name, _) in tier1Suites) (kitDir, name)],
      repoRoot: root,
    );
    print('promote: ${result.passed.length} provider(s) at port-tested '
        '($bumped registry field(s) changed); evidence recorded');
  }
  return result.allPassed ? 0 : 1;
}

// ── arch ───────────────────────────────────────────────────────────

int _runArchGate(List<String> args) {
  String? target;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--target' && i + 1 < args.length) {
      target = args[++i];
    } else {
      stderr.writeln('arxa gate arch: unknown flag ${args[i]}');
      exit(2);
    }
  }
  if (target == null) {
    stderr.writeln('arxa gate arch: --target <dir> required');
    return 2;
  }
  final r = archGuard(target);
  final status = r.passed ? 'PASS' : 'FAIL';
  print('arch_guard $status — files=${r.files} '
      'violations=${r.violations.length} warnings=${r.warnings.length}');
  for (final v in r.violations) {
    print('  ✗ ${v.rule} ${v.file}: ${v.msg}');
  }
  for (final w in r.warnings) {
    print('  ⚠ ${w.rule} ${w.file}: ${w.msg}');
  }
  return r.passed ? 0 : 1;
}

// ── trace ──────────────────────────────────────────────────────────

int _runTraceGate(List<String> args) {
  String? target;
  String? breakdownPath;
  var checkOnly = false;
  String? outPath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--target':
        target = args[++i];
        break;
      case '--breakdown':
        breakdownPath = args[++i];
        break;
      case '--out':
        outPath = args[++i];
        break;
      case '--check':
        checkOnly = true;
        break;
      default:
        stderr.writeln('arxa gate trace: unknown flag ${args[i]}');
        return 2;
    }
  }
  if (target == null) {
    stderr.writeln('arxa gate trace: --target <dir> required');
    return 2;
  }
  final manifest = derive(target, breakdownPath: breakdownPath);
  if (!checkOnly) {
    final path = outPath ?? '$target/.arxa/trace.json';
    final outFile = File(path);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(
      "${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n",
    );
    print('trace: wrote $path (${manifest.screens.length} screens)');
  }
  final r = check(manifest);
  final status = r.passed ? 'PASS' : 'FAIL';
  final initials = r.initials.join(',');
  final initialsDisplay = initials.isEmpty ? '(none)' : initials;
  print('trace_guard $status — initial=$initialsDisplay, issues=${r.issues.length}');
  for (final issue in r.issues) {
    print('  ✗ $issue');
  }
  return r.passed ? 0 : 1;
}

// ── gen-freshness ──────────────────────────────────────────────────

Future<int> _runGenFreshnessGate(List<String> args) async {
  String? target;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--target' && i + 1 < args.length) {
      target = args[++i];
    } else {
      stderr.writeln('arxa gate gen-freshness: unknown flag ${args[i]}');
      return 2;
    }
  }
  if (target == null) {
    stderr.writeln('arxa gate gen-freshness: --target <dir> required');
    return 2;
  }
  if (!Directory(target).existsSync()) {
    stderr.writeln('arxa gate gen-freshness: target not found: $target');
    return 2;
  }
  final r = await genFreshness(target);
  if (r.buildFailed == true) {
    stderr.writeln(
        'gen_freshness ERROR — build_runner failed (target not runnable):');
    stderr.writeln(r.logTail);
    return 2;
  }
  final status = r.passed ? 'PASS' : 'FAIL';
  print('gen_freshness $status — ${r.freshN} generated file(s) checked, '
      '${r.drifted.length} drifted');
  for (final d in r.drifted) {
    if (d['reason'] != null) {
      print('  ✗ ${d['file']}: ${d['reason']}');
    } else {
      print('  ✗ ${d['file']}: committed ${d['committedSha']} ≠ fresh '
          '${d['freshSha']} — regenerate: dart run build_runner build '
          '--delete-conflicting-outputs');
    }
  }
  return r.passed ? 0 : 1;
}

// ── crud ───────────────────────────────────────────────────────────

void _runCrud(List<String> args) {
  exit(crudMain(args));
}

// ── emit ───────────────────────────────────────────────────────────

void _runEmit(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('arxa emit: missing emitter name');
    stderr.writeln('  emitters: structure, htmx, playground, transform_tokens,');
    stderr.writeln('            synthesize, blueprint, emit_stage, generate_view,');
    stderr.writeln('            theme-map, palette');
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

  final repoRoot = findRepoRoot() ?? Directory.current.path;
  appRoot ??= repoRoot;
  // The canonical studio design default — keep in step with
  // GateContext.studioDesignDir (gates.dart). v2 replaced v1 2026-08-16.
  designDir ??= GateContext.studioDesignDir;

  switch (emitter) {
    case 'story-map':
      exit(storyMapMain(rest));
    case 'scaffold':
      exit(scaffoldMain(rest));
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
        stderr.writeln('arxa emit synthesize: needs <primitives> <maps> <design-html> <catalog> <out>');
        exit(2);
      }
      exit(synthesize(positional[0], positional[1], positional[2], positional[3], positional[4]));
    case 'blueprint':
      if (positional.length < 2) {
        stderr.writeln('arxa emit blueprint: needs <breakdown.json> <out-dir> [--tokens <path>]');
        exit(2);
      }
      exit(buildBlueprint(positional[0], positional[1], tokensPath: _flagValue(rest, '--tokens')));
    case 'emit_stage':
      if (positional.length < 2) {
        stderr.writeln('arxa emit emit_stage: needs <blueprint-dir> <target-dir> [--apply]');
        exit(2);
      }
      exit(emitStage(positional[0], positional[1], apply: rest.contains('--apply')));
    case 'generate_view':
      if (positional.length < 2) {
        stderr.writeln('arxa emit generate_view: needs <spec.json> <out.dart> [--tokens <path>]');
        exit(2);
      }
      exit(generateView(positional[0], positional[1], tokensPath: _flagValue(rest, '--tokens')));
    case 'theme-map':
      if (positional.isEmpty) {
        stderr.writeln('arxa emit theme-map: needs <tokens.json> [--out fragment.dart]');
        exit(2);
      }
      final tree =
          jsonDecode(File(positional[0]).readAsStringSync()) as Map<String, dynamic>;
      final frag = themeMap(tree);
      final outPath = _flagValue(rest, '--out');
      if (outPath != null) {
        File(outPath).writeAsStringSync(frag);
      } else {
        stdout.write(frag);
      }
      exit(0);
    case 'palette':
      if (positional.isEmpty) {
        stderr.writeln('arxa emit palette: needs <seed-hex> [--name brand] [--out tokens.json]');
        exit(2);
      }
      exit(_emitPalette(positional.first, rest));
  }
  stderr.writeln('arxa emit: unknown emitter "$emitter"');
  exit(2);
}

// ── palette emitter ────────────────────────────────────────────────

int _emitPalette(String seedHex, List<String> rest) {
  final name = _flagValue(rest, '--name') ?? 'brand';
  final out = _flagValue(rest, '--out');
  final doc = generate(seedHex, name: name);
  final blob = "${const JsonEncoder.withIndent('  ').convert(doc)}\n";
  if (out != null) {
    final f = File(out);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(blob);
    final ramp = tonalRamp(seedHex);
    final onAccent =
        ((doc['color'] as Map)['fg'] as Map)['on-accent'] as Map;
    final onAccentValue = onAccent[r'$value'] as String;
    final lc = apcaLc(onAccentValue, canonHex(seedHex)).abs().toStringAsFixed(0);
    print('wrote $out: ${ramp.length} tones from $seedHex (on-accent |Lc$lc|)');
  } else {
    stdout.write(blob);
  }
  return 0;
}

// ── lint ───────────────────────────────────────────────────────────

void _runLint(List<String> args) {
  final root = args.isNotEmpty && !args.first.startsWith('-')
      ? args.first
      : (findRepoRoot() ?? Directory.current.path);
  if (!File('$root/config/forbidden_abs_prefixes.txt').existsSync() ||
      !File('$root/config/stripped_names.txt').existsSync()) {
    stderr.writeln('arxa lint: missing config rule files under $root/config/');
    exit(2);
  }
  final result = lintConventions(root);
  for (final v in result.violations) {
    stderr.writeln('LINT FAIL: ${v.file} — ${v.message}');
  }
  if (result.ok) {
    print('LINT OK (${result.scanned} files scanned)');
    exit(0);
  }
  stderr.writeln('LINT FAILED: ${result.violations.length} violation(s)');
  exit(1);
}

// ── docs ───────────────────────────────────────────────────────────

void _runDocs(List<String> args) {
  final root = args.isNotEmpty && !args.first.startsWith('-')
      ? args.first
      : (findRepoRoot() ?? Directory.current.path);
  final result = validateDocs(root);
  for (final f in result.failures) {
    stderr.writeln('DOCS FAIL: $f');
  }
  for (final w in result.warnings) {
    stdout.writeln('docs warn: $w');
  }
  // Fold the advisory KB-lint warnings (orphans / supersede / wikilink) on top
  // of validate_docs' dead-link (R1) + index-coverage (R2) contract. These are
  // stdout warnings only — they never change the exit code.
  final kbWarnings = lintKb(root);
  for (final w in kbWarnings) {
    stdout.writeln('docs warn: $w');
  }
  if (result.ok) {
    print('DOCS OK (${result.scanned} links checked, '
        '${result.warnings.length + kbWarnings.length} warning(s))');
    exit(0);
  }
  stderr.writeln('DOCS FAILED: ${result.failures.length} dead link(s)');
  exit(1);
}

// ── kb ────────────────────────────────────────────────────────────

void _runKb(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('arxa kb: missing subcommand');
    stderr.writeln('  subcommands: facts build check lock playbook conventions');
    exit(2);
  }
  final sub = args.first;
  final rest = args.sublist(1);
  final repoRoot = findRepoRoot() ?? Directory.current.path;

  switch (sub) {
    case 'facts':
      final kitRoot = rest.isNotEmpty ? rest.first : '$repoRoot/kit';
      final facts = extractFacts(kitRoot,
          factsDir: '$repoRoot/memory/facts');
      print('extracted ${facts.length} kit fact(s) to memory/facts/');
      exit(0);
    case 'build':
      final root = rest.isNotEmpty ? rest.first : repoRoot;
      final result = buildKb(root);
      print('kb: ${result.registrySources} registry + '
          '${result.minedPackageRefs} mined, ${result.domainPages} pages, '
          '${result.injectedPlaybooks} playbooks');
      final toc = buildToc(root);
      print('toc: playbooks.md + llms.txt for ${toc.kitCount} kits');
      exit(0);
    case 'check':
      final root = rest.isNotEmpty ? rest.first : repoRoot;
      final result = kbCheck(root);
      for (final e in result.errors) {
        stderr.writeln('FAIL: $e');
      }
      for (final w in result.warnings) {
        stdout.writeln('WARN: $w');
      }
      print(result.ok ? 'OK' : 'FAILED');
      exit(result.ok ? 0 : 1);
    case 'lock':
      final root = rest.isNotEmpty ? rest.first : repoRoot;
      stdout.write(generateKitLock(root, '$root/kit'));
      exit(0);
    case 'playbook':
      if (rest.isEmpty) {
        stderr.writeln('arxa kb playbook: needs <facts.json>');
        exit(2);
      }
      final facts =
          jsonDecode(File(rest.first).readAsStringSync()) as Map<String, dynamic>;
      print(generatePlaybook(facts));
      exit(0);
    case 'conventions':
      final kitRoot = rest.isNotEmpty ? rest.first : '$repoRoot/kit';
      final result = checkArxaKitConventions(kitRoot);
      for (final e in result.errors) {
        stderr.writeln('FAIL: $e');
      }
      for (final w in result.warnings) {
        stdout.writeln('WARN: $w');
      }
      print(result.ok ? 'OK' : 'FAILED');
      exit(result.ok ? 0 : 1);
    default:
      stderr.writeln('arxa kb: unknown subcommand "$sub"');
      exit(2);
  }
}

// ── capability / api-map gates ────────────────────────────────────

int _runCapabilityGate(List<String> args) {
  final appRoot = args.isNotEmpty && !args.first.startsWith('-')
      ? args.first
      : (findRepoRoot() ?? Directory.current.path);
  final result = scanCapabilities(appRoot);
  for (final e in result.evidence) {
    print('  $e');
  }
  if (result.ok) {
    print('capability scan: all signals declared');
    return 0;
  }
  for (final u in result.undeclared) {
    stderr.writeln('FAIL: $u playback present but undeclared');
  }
  return 1;
}

int _runApiMapGate(List<String> args) {
  final appRoot = args.isNotEmpty && !args.first.startsWith('-')
      ? args.first
      : (findRepoRoot() ?? Directory.current.path);
  final mapPath = '$appRoot/kit/core/FLUTTER_API_MAP.md';
  final violations = scanApiMap(appRoot, mapPath);
  if (violations.isEmpty) {
    print('api map scan: clean');
    return 0;
  }
  for (final v in violations) {
    stderr.writeln(
        'FAIL: ${v.file} — ${v.token} (${v.sanctioned}; ${v.problemClass})');
  }
  return 1;
}

void _runServe(List<String> args) {
  var port = ArxadConfig.defaultPort;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--port' && i + 1 < args.length) {
      port = int.tryParse(args[++i]) ?? ArxadConfig.defaultPort;
    }
  }
  final repoRoot = findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('arxa serve: cannot find repo root');
    exit(2);
  }
  final config = ArxadConfig.load(repoRoot, port: port);
  server.startServer(config).then((s) {
    stdout.writeln('arxa serving on http://127.0.0.1:${s.port}');
  });
}

// ── helpers ────────────────────────────────────────────────────────

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}
