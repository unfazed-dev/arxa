// arxa-deployer — the deploy mechanics, behind the strictest human gate.
//
// Dart port of skills/arxa-deployer/deploy.py (plan 11 / Architecture §17).
// The deploy kit (`arxa_kit_deploy`) is pure-Dart, standalone, registry
// `phase: stable`. This module drives the kit's external CLIs through the
// daemon-wide `ProcessRunner` seam (lib/process.dart) — the same place every
// other shell-out routes through. The scripted runner asserts every command
// shape with NO toolchain, NO credentials, NO signing identity — the one
// property that makes a deploy stage self-testable (§17).
//
// TARGETS
//   fastlane-ios / fastlane-android     wired
//   shorebird-release / shorebird-patch wired
//   cloudflare-pages                    wired
//   cloudflare-workers                  wired
//   vercel                              wired
//
// THE ONE THING THIS MODULE WILL NOT DO
//   Mint an approval token. Deploy is the third human gate (§17): it names
//   the target, the version and the account, and a person confirms that
//   exact triple. [Deployer.deploy] REQUIRES that approval as an argument;
//   an automated run reaches the gate and halts, minting nothing.
//
// The ledger (default pipeline/state/deploy-ledger.json, override via
// --ledger or $ARXA_DEPLOY_LEDGER in the CLI) is append-only and records
// EVERY attempt, including one that halted at the gate. Stdlib only.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/process.dart';

// Re-export the seam types so importing this module alone is enough — the
// deploy API is expressed entirely in terms of ProcessRunner / RunnerResult.
export 'package:arxa/process.dart' show ProcessRunner, RunnerResult;

// --------------------------------------------------------------------------- //
// Scripted runner — fake that asserts the exact argv shape, in order. Mirrors
// the Python's ScriptedRunner (and tier1's): each expectation is an
// (argvPrefix, result) tuple; the first element of argvPrefix is the
// executable, the rest is the args prefix the port must issue.
// --------------------------------------------------------------------------- //

class ScriptedRunner implements ProcessRunner {
  final List<(List<String> argvPrefix, RunnerResult result)> _expectations;
  var _i = 0;

  ScriptedRunner(this._expectations);

  /// Number of expectations consumed so far (mirrors the Python `_i` field).
  int get callCount => _i;

  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    if (_i >= _expectations.length) {
      throw StateError('port issued an unexpected extra command: '
          '$executable $args (suite expected only ${_expectations.length})');
    }
    final (wantPrefix, result) = _expectations[_i];
    final argv = [executable, ...args];
    if (!_startsWith(argv, wantPrefix)) {
      final got = argv.length < wantPrefix.length
          ? argv
          : argv.sublist(0, wantPrefix.length);
      throw StateError('port called the wrong command:\n'
          '  expected prefix $wantPrefix\n'
          '  got                  $got');
    }
    _i++;
    return result;
  }
}

bool _startsWith(List<String> a, List<String> prefix) {
  if (a.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (a[i] != prefix[i]) return false;
  }
  return true;
}

// --------------------------------------------------------------------------- //
// Result + ledger row.
// --------------------------------------------------------------------------- //

/// Outcome of one target run.
class DeployResult {
  final bool ok;
  final String target;
  final String? artefactId;
  final String? error;
  final bool halted;

  const DeployResult(
    this.ok,
    this.target, {
    this.artefactId,
    this.error,
    this.halted = false,
  });

  Map<String, dynamic> toMap() => {
        'ok': ok,
        'target': target,
        if (artefactId != null) 'artefact_id': artefactId,
        if (error != null) 'error': error,
        'halted': halted,
      };
}

/// One row in the deploy ledger. Records EVERY attempt — shipped or halted.
class DeployAttempt {
  final String target;
  final String version;
  final String account;
  final String? approver; // null until a person confirms (a halted run mints none)
  final String timestamp;
  final String? artefactId; // null for a halted run
  final String status; // "shipped" | "halted"

  const DeployAttempt({
    required this.target,
    required this.version,
    required this.account,
    this.approver,
    required this.timestamp,
    this.artefactId,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
        'target': target,
        'version': version,
        'account': account,
        'approver': approver,
        'timestamp': timestamp,
        'artefact_id': artefactId,
        'status': status,
      };
}

/// Raised when deploy() is asked to run without the confirmed triple + approval,
/// or against an unknown / stub target. The automated run reached the gate and
/// stopped, minting nothing.
class DeployHalted implements Exception {
  final String message;
  const DeployHalted(this.message);

  @override
  String toString() => message;
}

// --------------------------------------------------------------------------- //
// Target ports — each builds the external CLI command shape and reads the
// result. The argv is the contract the scripted runner asserts; the real
// runner shells out. Ported function-for-function from deploy.py.
// --------------------------------------------------------------------------- //

/// iOS store lane: build (gym) -> sign (match) -> upload to TestFlight.
/// `fastlane run <action>` is the real CLI form for each lane action.
Future<DeployResult> fastlaneIos(ProcessRunner runner, String version) async {
  await runner.run('fastlane', ['run', 'gym', '--version', version]);
  await runner.run('fastlane', ['run', 'match']);
  final up = await runner.run('fastlane', ['run', 'upload_to_testflight']);
  if (!up.ok) {
    return DeployResult(false, 'fastlane-ios',
        error: 'testflight upload failed: ${up.stderr}');
  }
  final id = up.stdout.trim();
  return DeployResult(true, 'fastlane-ios', artefactId: id.isEmpty ? 'tf_build_demo' : id);
}

/// Android store lane: build aab -> upload to Play (internal track).
Future<DeployResult> fastlaneAndroid(ProcessRunner runner, String version) async {
  await runner.run('flutter', ['build', 'appbundle', '--build-name', version]);
  final up =
      await runner.run('fastlane', ['run', 'upload_to_play_store', '--track', 'internal']);
  if (!up.ok) {
    return DeployResult(false, 'fastlane-android',
        error: 'play upload failed: ${up.stderr}');
  }
  final id = up.stdout.trim();
  return DeployResult(true, 'fastlane-android',
      artefactId: id.isEmpty ? 'play_vc_demo' : id);
}

/// Shorebird full release (native + Dart) -> a shorebird release id.
Future<DeployResult> shorebirdRelease(ProcessRunner runner, String version) async {
  final r =
      await runner.run('shorebird', ['release', 'release-version', '--version', version]);
  if (!r.ok) {
    return DeployResult(false, 'shorebird-release',
        error: 'shorebird release failed: ${r.stderr}');
  }
  final id = r.stdout.trim();
  return DeployResult(true, 'shorebird-release',
      artefactId: id.isEmpty ? 'shorebird_rel_demo' : id);
}

/// Shorebird OTA Dart patch (no store round-trip). Patches Dart only.
Future<DeployResult> shorebirdPatch(ProcessRunner runner, String version) async {
  final r = await runner.run('shorebird', ['release', 'patch', '--version', version]);
  if (!r.ok) {
    return DeployResult(false, 'shorebird-patch',
        error: 'shorebird patch failed: ${r.stderr}');
  }
  final id = r.stdout.trim();
  return DeployResult(true, 'shorebird-patch',
      artefactId: id.isEmpty ? 'shorebird_patch_demo' : id);
}

/// Cloudflare Pages deploy via wrangler -> a deployment URL.
Future<DeployResult> cloudflarePages(ProcessRunner runner, String version) async {
  final r = await runner
      .run('wrangler', ['pages', 'deploy', '--commit-dirty', '--version', version]);
  if (!r.ok) {
    return DeployResult(false, 'cloudflare-pages',
        error: 'pages deploy failed: ${r.stderr}');
  }
  final id = r.stdout.trim();
  return DeployResult(true, 'cloudflare-pages',
      artefactId: id.isEmpty ? 'https://demo.pages.dev' : id);
}

/// Cloudflare Workers deploy via wrangler -> a deployment URL. No flutter
/// build step — a Worker ships from its own wrangler.toml in the working
/// directory, with CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID in the
/// ambient environment.
Future<DeployResult> cloudflareWorkers(ProcessRunner runner, String version) async {
  final r = await runner.run('wrangler', ['deploy']);
  if (!r.ok) {
    return DeployResult(false, 'cloudflare-workers',
        error: 'workers deploy failed: ${r.stderr}');
  }
  final id = r.stdout.trim();
  return DeployResult(true, 'cloudflare-workers',
      artefactId: id.isEmpty ? 'https://demo.workers.dev' : id);
}

/// Vercel deploy of a static Flutter web build:
/// `flutter build web --release` -> `vercel deploy build/web --prod --yes`,
/// with VERCEL_TOKEN in the ambient environment -> a deployment URL. Same
/// command shape as kit/deploy's VercelTarget.
Future<DeployResult> vercel(ProcessRunner runner, String version) async {
  final build = await runner.run('flutter', ['build', 'web', '--release']);
  if (!build.ok) {
    return DeployResult(false, 'vercel',
        error: 'flutter build web failed: ${build.stderr}');
  }
  final r = await runner.run('vercel', ['deploy', 'build/web', '--prod', '--yes']);
  if (!r.ok) {
    return DeployResult(false, 'vercel', error: 'vercel deploy failed: ${r.stderr}');
  }
  final id = r.stdout.trim();
  return DeployResult(true, 'vercel',
      artefactId: id.isEmpty ? 'https://demo.vercel.app' : id);
}

typedef _TargetPort = Future<DeployResult> Function(ProcessRunner runner, String version);

class _Target {
  final _TargetPort port;
  final String status; // "wired" | "stub"
  const _Target(this.port, this.status);
}

/// The deploy contract: name -> (port, status). The kit's fixed target
/// vocabulary (like tier1's provider ports), not project-varying config —
/// version/account/approver/ledger-path are the config.
final Map<String, _Target> _targets = {
  'fastlane-ios': _Target(fastlaneIos, 'wired'),
  'fastlane-android': _Target(fastlaneAndroid, 'wired'),
  'shorebird-release': _Target(shorebirdRelease, 'wired'),
  'shorebird-patch': _Target(shorebirdPatch, 'wired'),
  'cloudflare-pages': _Target(cloudflarePages, 'wired'),
  'cloudflare-workers': _Target(cloudflareWorkers, 'wired'),
  'vercel': _Target(vercel, 'wired'),
};

/// OFFERED = wired targets only, sorted. gates/advertise independently
/// enforces this against the registry; this is the skill-side defence in
/// depth.
final List<String> offered =
    (_targets.entries.where((e) => e.value.status == 'wired').map((e) => e.key).toList()
          ..sort());

/// Look up a target's status ("wired" | "stub"), or null if unknown.
String? targetStatus(String name) =>
    _targets.containsKey(name) ? _targets[name]!.status : null;

// --------------------------------------------------------------------------- //
// doctor — preflight readiness report. NOT a gate (§17 / 11.3).
// --------------------------------------------------------------------------- //

class DoctorReport {
  final List<String> offered;
  final List<String> stubNotOfferered;
  final List<String> configuredTargets;
  final String ready;

  const DoctorReport({
    required this.offered,
    required this.stubNotOfferered,
    required this.configuredTargets,
    required this.ready,
  });

  Map<String, dynamic> toMap() => {
        'offered': offered,
        'stub_not_offered': stubNotOfferered,
        'configured_targets': configuredTargets,
        'ready': ready,
      };
}

/// The ready string is constant — doctor never decides whether a deploy may
/// proceed (that is the gate's job, gates/deploy asserts a VALUE).
const String _doctorReady =
    'preflight report — the gates/deploy gate asserts the deploy triple, not this';

/// Read the configured-targets list from a JSON file (`{"targets": [...]}`).
/// De-duplicates + sorts. Missing/unreadable/malformed config yields empty.
List<String> _readConfiguredTargets(String? path) {
  if (path == null || path.isEmpty) return const [];
  final f = File(path);
  if (!f.existsSync()) return const [];
  try {
    final decoded = jsonDecode(f.readAsStringSync());
    if (decoded is Map<String, dynamic> && decoded['targets'] is List) {
      return (decoded['targets'] as List).whereType<String>().toSet().toList()..sort();
    }
  } catch (_) {
    // corrupt config — report nothing configured, never fail the preflight
  }
  return const [];
}

// --------------------------------------------------------------------------- //
// Ledger — append-only, records every attempt (shipped AND halted). 11.6.
// --------------------------------------------------------------------------- //

void _recordLedger(DeployAttempt attempt, String ledgerPath) {
  final f = File(ledgerPath);
  Map<String, dynamic> ledger = {'attempts': <Map<String, dynamic>>[]};
  if (f.existsSync()) {
    try {
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is Map<String, dynamic> && decoded['attempts'] is List) {
        ledger = decoded;
      }
    } catch (_) {
      // corrupt ledger — start fresh rather than fail the deploy record
      ledger = {'attempts': <Map<String, dynamic>>[]};
    }
  }
  (ledger['attempts'] as List).add(attempt.toMap());
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(ledger)}\n');
}

// --------------------------------------------------------------------------- //
// Deployer — holds the runner + ledger path; runs the gate. The target port
// functions above are the spec (ported function-for-function from deploy.py);
// Deployer is the stateful wrapper the CLI drives.
// --------------------------------------------------------------------------- //

class Deployer {
  final ProcessRunner _runner;
  final String _ledgerPath;

  /// Default ledger (relative to cwd, which is the repo root when invoked via
  /// the CLI) — overridden by an explicit [ledgerPath], and by the CLI's
  /// --ledger / $ARXA_DEPLOY_LEDGER resolution.
  static const String defaultLedgerPath = 'pipeline/state/deploy-ledger.json';

  Deployer({ProcessRunner? runner, String? ledgerPath})
      : _runner = runner ?? const RealProcessRunner(),
        _ledgerPath = ledgerPath ?? defaultLedgerPath;

  /// Run a target's command shapes and record the attempt. The triple
  /// (target, version, account) and a non-empty approval MUST all be present
  /// — this is the gate contract (§17). If any is missing, or the target is
  /// unknown or a stub, the attempt is recorded as HALTED (no artefact; no
  /// recorded approver for a missing-field halt) and [DeployHalted] is raised.
  /// The function never synthesises an approval token.
  Future<DeployResult> deploy({
    required String target,
    required String version,
    required String account,
    required String approval,
  }) async {
    final fields = const [('target', 0), ('version', 1), ('account', 2), ('approval', 3)];
    final values = [target, version, account, approval];
    final missing = [for (final e in fields) if (values[e.$2].isEmpty) e.$1];
    final ts = _utcTimestamp(DateTime.now().toUtc());

    if (missing.isNotEmpty) {
      _recordLedger(
        DeployAttempt(
          target: target,
          version: version,
          account: account,
          approver: null,
          timestamp: ts,
          artefactId: null,
          status: 'halted',
        ),
        _ledgerPath,
      );
      throw DeployHalted('deploy halted at the gate — missing ${missing.join(', ')}. '
          'An agent may prepare and preflight but never mint the approval token.');
    }

    if (!_targets.containsKey(target)) {
      _recordLedger(
        DeployAttempt(
          target: target,
          version: version,
          account: account,
          approver: approval,
          timestamp: ts,
          artefactId: null,
          status: 'halted',
        ),
        _ledgerPath,
      );
      throw DeployHalted("deploy halted — unknown target '$target'");
    }

    final entry = _targets[target]!;
    if (entry.status == 'stub') {
      _recordLedger(
        DeployAttempt(
          target: target,
          version: version,
          account: account,
          approver: approval,
          timestamp: ts,
          artefactId: null,
          status: 'halted',
        ),
        _ledgerPath,
      );
      throw DeployHalted(
          "deploy halted — target '$target' is a stub and is not offered");
    }

    final res = await entry.port(_runner, version);
    _recordLedger(
      DeployAttempt(
        target: target,
        version: version,
        account: account,
        approver: approval,
        timestamp: ts,
        artefactId: res.artefactId,
        status: res.ok ? 'shipped' : 'halted',
      ),
      _ledgerPath,
    );
    if (!res.ok) {
      throw DeployHalted('deploy halted — $target failed: ${res.error}');
    }
    return res;
  }

  /// Preflight readiness report. NOT a gate. [configPath] points at a JSON file
  /// with a `targets` list; missing/unreadable/malformed config yields empty.
  /// doctor never decides whether a deploy may proceed.
  DoctorReport doctor({String? configPath}) {
    final stub = _targets.entries
        .where((e) => e.value.status == 'stub')
        .map((e) => e.key)
        .toList()
      ..sort();
    return DoctorReport(
      offered: List<String>.from(offered),
      stubNotOfferered: stub,
      configuredTargets: _readConfiguredTargets(configPath),
      ready: _doctorReady,
    );
  }
}

String _utcTimestamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}Z';
}

// --------------------------------------------------------------------------- //
// Self-test — assert-based, no framework. Exercises every shape under the
// scripted runner with no toolchain and no credentials (11.7). Mirrors the
// Python self-test + tier1's runTier1Suites: the bundled self-check the CLI
// `arxa deploy --self-test` runs.
// --------------------------------------------------------------------------- //

void _check(bool cond, String msg) {
  if (!cond) throw StateError(msg);
}

/// Run [action] against a freshly loaded [ScriptedRunner], returning both so
/// the caller can assert how many commands were consumed.
Future<(ScriptedRunner, R)> _scripted<R>(
  List<(List<String>, RunnerResult)> expectations,
  Future<R> Function(ProcessRunner) action,
) async {
  final runner = ScriptedRunner(expectations);
  return (runner, await action(runner));
}

Future<void> _suiteFastlaneIos() async {
  var (r, res) = await _scripted(
    [
      (['fastlane', 'run', 'gym'], const RunnerResult(0, '', '')),
      (['fastlane', 'run', 'match'], const RunnerResult(0, '', '')),
      (['fastlane', 'run', 'upload_to_testflight'],
          const RunnerResult(0, 'tf_build_77', '')),
    ],
    (run) => fastlaneIos(run, '1.2.3'),
  );
  _check(r.callCount == 3, 'fastlane-ios did not issue gym -> match -> upload');
  _check(res.ok && res.artefactId == 'tf_build_77', 'fastlane-ios: $res');
  // upload failure is surfaced, not swallowed
  (_, res) = await _scripted(
    [
      (['fastlane', 'run', 'gym'], const RunnerResult(0, '', '')),
      (['fastlane', 'run', 'match'], const RunnerResult(0, '', '')),
      (['fastlane', 'run', 'upload_to_testflight'],
          const RunnerResult(1, '', 'api 401')),
    ],
    (run) => fastlaneIos(run, '1.2.3'),
  );
  _check(!res.ok && res.error!.contains('api 401'), 'fastlane-ios failure: $res');
}

Future<void> _suiteFastlaneAndroid() async {
  final (r, res) = await _scripted(
    [
      (['flutter', 'build', 'appbundle'], const RunnerResult(0, '', '')),
      (['fastlane', 'run', 'upload_to_play_store'],
          const RunnerResult(0, 'play_vc_401', '')),
    ],
    (run) => fastlaneAndroid(run, '1.2.3'),
  );
  _check(r.callCount == 2, 'fastlane-android did not issue build -> upload');
  _check(res.ok && res.artefactId == 'play_vc_401', 'fastlane-android: $res');
}

Future<void> _suiteShorebirdRelease() async {
  final (_, res) = await _scripted(
    [
      (['shorebird', 'release', 'release-version'],
          const RunnerResult(0, 'shorebird_rel_9', '')),
    ],
    (run) => shorebirdRelease(run, '1.2.3'),
  );
  _check(res.ok && res.artefactId == 'shorebird_rel_9', 'shorebird-release: $res');
}

Future<void> _suiteShorebirdPatch() async {
  final (_, res) = await _scripted(
    [
      (['shorebird', 'release', 'patch'],
          const RunnerResult(0, 'shorebird_patch_3', '')),
    ],
    (run) => shorebirdPatch(run, '1.2.4'),
  );
  _check(res.ok && res.artefactId == 'shorebird_patch_3', 'shorebird-patch: $res');
}

Future<void> _suiteCloudflarePages() async {
  final (_, res) = await _scripted(
    [
      (['wrangler', 'pages', 'deploy'],
          const RunnerResult(0, 'https://app.pages.dev', '')),
    ],
    (run) => cloudflarePages(run, '1.2.3'),
  );
  _check(res.ok && res.artefactId == 'https://app.pages.dev',
      'cloudflare-pages: $res');
}

Future<void> _suiteCloudflareWorkers() async {
  final (_, res) = await _scripted(
    [
      (['wrangler', 'deploy'],
          const RunnerResult(0, 'https://app.workers.dev', '')),
    ],
    (run) => cloudflareWorkers(run, '1.2.3'),
  );
  _check(res.ok && res.artefactId == 'https://app.workers.dev',
      'cloudflare-workers: $res');
}

Future<void> _suiteVercel() async {
  var (r, res) = await _scripted(
    [
      (['flutter', 'build', 'web', '--release'], const RunnerResult(0, '', '')),
      (['vercel', 'deploy', 'build/web', '--prod', '--yes'],
          const RunnerResult(0, 'https://app.vercel.app', '')),
    ],
    (run) => vercel(run, '1.2.3'),
  );
  _check(r.callCount == 2, 'vercel did not issue build -> deploy');
  _check(res.ok && res.artefactId == 'https://app.vercel.app', 'vercel: $res');
  // a failed flutter build short-circuits — never deploy a broken build
  (r, res) = await _scripted(
    [
      (['flutter', 'build', 'web', '--release'],
          const RunnerResult(1, '', 'compile error')),
    ],
    (run) => vercel(run, '1.2.3'),
  );
  _check(r.callCount == 1 && !res.ok && res.error!.contains('compile error'),
      'vercel build failure: $res');
  _check(offered.contains('vercel'), 'vercel is offered: $offered');
  _check(targetStatus('vercel') == 'wired', 'vercel is wired');
}

Future<void> _suiteOfferedIsExactlyTheWiredSet() async {
  _check(
    _listEq(
      offered,
      [
        'cloudflare-pages',
        'cloudflare-workers',
        'fastlane-android',
        'fastlane-ios',
        'shorebird-patch',
        'shorebird-release',
        'vercel',
      ],
    ),
    'OFFERED is the wired set, sorted: $offered',
  );
}

Future<void> _suiteDoctorIsPreflightNotGate() async {
  final rep = Deployer().doctor();
  _check(rep.ready.contains('gate'), 'doctor ready mentions gate: ${rep.ready}');
  _check(rep.stubNotOfferered.isEmpty, 'no stubs: ${rep.stubNotOfferered}');
  _check(_listEq(rep.offered, offered), 'doctor.offered == OFFERED');
}

bool _listEq(List<String> a, List<String> b) =>
    a.length == b.length && _startsWith(a, b);

String _selftestLedger() =>
    '${Directory.systemTemp.createTempSync('deploy_selftest').path}/deploy-ledger.json';

Future<void> _suiteDeployHaltsWithoutApproval() async {
  final ledger = _selftestLedger();
  // No approval token -> DeployHalted, no artefact, no recorded approver.
  try {
    await Deployer(runner: ScriptedRunner([]), ledgerPath: ledger).deploy(
      target: 'fastlane-ios',
      version: '1.2.3',
      account: 'totem-labs',
      approval: '',
    );
  } catch (e) {
    _check(e.toString().contains('approval'), 'halt names approval: $e');
  }
  final led = (jsonDecode(File(ledger).readAsStringSync())
      as Map<String, dynamic>)['attempts'] as List;
  _check(
      led.length == 1 && (led.first as Map)['status'] == 'halted', 'halted row: $led');
  final row = led.first as Map<String, dynamic>;
  _check(row['artefact_id'] == null && row['approver'] == null,
      'mints nothing: $row');
  // missing version / account / target each halt too
  for (final c in <(String, String, String, String)>[
    ('version', 'fastlane-ios', '', 'a'),
    ('account', 'fastlane-ios', '1', ''),
    ('target', '', '1', 'a'),
  ]) {
    final l2 = _selftestLedger();
    try {
      await Deployer(runner: ScriptedRunner([]), ledgerPath: l2).deploy(
        target: c.$2,
        version: c.$3,
        account: c.$4,
        approval: 'ok',
      );
    } catch (e) {
      _check(e.toString().contains(c.$1), 'halt names ${c.$1}: $e');
    }
  }
}

Future<void> _suiteDeployRecordsFullAttempt() async {
  final ledger = _selftestLedger();
  final (_, res) = await _scripted(
    [
      (['fastlane', 'run', 'gym'], const RunnerResult(0, '', '')),
      (['fastlane', 'run', 'match'], const RunnerResult(0, '', '')),
      (['fastlane', 'run', 'upload_to_testflight'],
          const RunnerResult(0, 'tf_build_512', '')),
    ],
    (run) => Deployer(runner: run, ledgerPath: ledger).deploy(
      target: 'fastlane-ios',
      version: '1.2.3',
      account: 'totem-labs',
      approval: 'ops@totem',
    ),
  );
  _check(res.ok && res.artefactId == 'tf_build_512', 'shipped: $res');
  final led = (jsonDecode(File(ledger).readAsStringSync())
      as Map<String, dynamic>)['attempts'] as List;
  final row = led.last as Map<String, dynamic>;
  _check(row['status'] == 'shipped' && row['artefact_id'] == 'tf_build_512', 'row: $row');
  _check(row['target'] == 'fastlane-ios' && row['version'] == '1.2.3', 'row: $row');
  _check(row['account'] == 'totem-labs' && row['approver'] == 'ops@totem', 'row: $row');
  _check((row['timestamp'] as String).isNotEmpty &&
      (row['timestamp'] as String).endsWith('Z'), 'row ts: $row');
}

Future<void> _suiteDeployShipsVercelWithApproval() async {
  final ledger = _selftestLedger();
  // vercel is wired, but the gate still applies: only a confirmed triple +
  // approval ships, and the attempt is recorded.
  final (_, res) = await _scripted(
    [
      (['flutter', 'build', 'web', '--release'], const RunnerResult(0, '', '')),
      (['vercel', 'deploy', 'build/web', '--prod', '--yes'],
          const RunnerResult(0, 'https://app.vercel.app', '')),
    ],
    (run) => Deployer(runner: run, ledgerPath: ledger).deploy(
      target: 'vercel',
      version: '1.2.3',
      account: 'totem-labs',
      approval: 'ops@totem',
    ),
  );
  _check(res.ok && res.artefactId == 'https://app.vercel.app', 'shipped: $res');
  final led = (jsonDecode(File(ledger).readAsStringSync())
      as Map<String, dynamic>)['attempts'] as List;
  final row = led.last as Map<String, dynamic>;
  _check(row['status'] == 'shipped' && row['target'] == 'vercel', 'row: $row');
}

/// One deploy self-test suite: its label plus the entrypoint.
typedef DeploySuite = (String name, Future<void> Function() body);

/// Every self-test suite, in deploy.py's SUITE order.
final List<DeploySuite> deploySuites = <DeploySuite>[
  ('fastlane-ios shape', _suiteFastlaneIos),
  ('fastlane-android shape', _suiteFastlaneAndroid),
  ('shorebird-release shape', _suiteShorebirdRelease),
  ('shorebird-patch shape', _suiteShorebirdPatch),
  ('cloudflare-pages shape', _suiteCloudflarePages),
  ('cloudflare-workers shape', _suiteCloudflareWorkers),
  ('vercel shape', _suiteVercel),
  ('OFFERED is exactly the wired set', _suiteOfferedIsExactlyTheWiredSet),
  ('doctor is preflight, not a gate', _suiteDoctorIsPreflightNotGate),
  ('deploy halts without approval', _suiteDeployHaltsWithoutApproval),
  ('deploy records full attempt', _suiteDeployRecordsFullAttempt),
  ('deploy ships vercel with approval', _suiteDeployShipsVercelWithApproval),
];

/// Outcome of running every self-test suite.
class DeploySelfTestResult {
  final List<String> passed; // suite name
  final List<String> failed; // "suite name: <error>"

  DeploySelfTestResult(this.passed, this.failed);

  bool get allPassed => failed.isEmpty;
}

/// Run every self-test suite, catching failures per suite so one break does
/// not mask the rest. Mirrors deploy.py's `_self_test` loop. Async because the
/// deploy mechanics are async (the runner seam is a Future).
Future<DeploySelfTestResult> runDeploySelfTest() async {
  final passed = <String>[];
  final failed = <String>[];
  for (final (name, body) in deploySuites) {
    try {
      await body();
      passed.add(name);
    } catch (e) {
      failed.add('$name: $e');
    }
  }
  return DeploySelfTestResult(passed, failed);
}
