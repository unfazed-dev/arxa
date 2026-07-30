// Deploy gate — port of gates/deploy/deploy.sh (+ licence_assert.sh) to Dart.
//
// Plan 11: asserts the three deployment prerequisites are confirmed in
// pipeline state before a target ships — the build target, the version, and
// the releasing account. This gate owns only the confirmation contract, so the
// pipeline cannot ship a build whose target/version/account is unset.
//
// §17 licence assertion FIRST (consolidation decision 11): a valid paid licence
// must be confirmed before the deploy phase runs — the paywall sits at first
// deploy; everything before it is free. Verified via the Licence class
// (appboxd/lib/licence.dart), failing CLOSED. A licence failure is never
// reported as a sarif gate finding (a gate that goes red for payment teaches
// people to distrust red — §17's own constraint).
//
// APPBOX_DEV_LICENCE=1 is the documented dev/dogfood bypass.

import 'dart:io';

import 'package:appboxd/gates.dart';
import 'package:appboxd/licence.dart';

GateResult deployGate(GateContext ctx) {
  // ---- §17 licence assertion FIRST (fail-closed, never a sarif finding) ----
  final licence = _licenceAssertion(ctx);
  if (!licence.passed) {
    return GateResult.fail(
      'deploy: HALTED — §17 licence assertion failed (see above).',
      licence.failLines,
    );
  }

  final details = <String>['  ✓ ${licence.okLine}'];
  var fails = 0;

  void fail(String msg) {
    details.add('  ✗ $msg');
    ctx.sarif.result('deploy', 'error', ctx.state.stateFile, msg);
    fails++;
  }

  // ---- pipeline state must exist ----
  final stateFile = ctx.state.stateFile;
  if (!File(stateFile).existsSync()) {
    fail('deploy: no pipeline state at $stateFile — '
        'a gate that cannot find its input never passes quietly');
    return GateResult.fail('deploy: FAIL ($fails check(s))', details);
  }

  // ---- target + version + account, read from state in one pass ----
  // approvalTokens.deploy carries the human confirmations (plan 11 shape);
  // targets is the top-level list.
  final targets = ctx.state.targets;
  if (targets.isEmpty) {
    fail('no build target in state.targets — set the target before deploying');
  } else {
    details.add('  ✓ target: ${targets.join(', ')}');
  }

  final toks = ctx.state.get('approvalTokens');
  final deploy = toks is Map ? toks['deploy'] : null;
  final deployMap = deploy is Map ? deploy : const <String, dynamic>{};

  final version = deployMap['version'];
  if (!_truthy(version)) {
    fail('deploy.version is not confirmed in approvalTokens.deploy — '
        'set the release version');
  } else {
    details.add('  ✓ version: $version');
  }

  final account = deployMap['account'];
  if (!_truthy(account)) {
    fail('deploy.account is not confirmed in approvalTokens.deploy — '
        'set the releasing account');
  } else {
    details.add('  ✓ account: $account');
  }

  if (fails > 0) {
    return GateResult.fail('deploy: FAIL ($fails check(s))', details);
  }
  return GateResult.ok(
    'deploy: PASS — target, version and account confirmed.',
    details,
  );
}

// ── §17 licence assertion ──────────────────────────────────────────

/// Fail-closed licence check. Mirrors licence_assert.sh + licence_tool's
/// `status` contract, but verifies via the Licence class directly (no shelling
/// out to `dart run licence_tool`). Never throws; every failure is a red
/// verdict. Returns the activation message on failure — never a sarif finding.
({bool passed, String okLine, List<String> failLines}) _licenceAssertion(
    GateContext ctx) {
  // --- dev/dogfood escape (works even before a licence file exists) ---
  if (Platform.environment['APPBOX_DEV_LICENCE'] == '1') {
    return (
      passed: true,
      okLine: 'licence: DEV BYPASS (APPBOX_DEV_LICENCE=1) — '
          'dev/dogfood only, never ship',
      failLines: const [],
    );
  }

  final path = _defaultLicencePath(ctx.repoRoot);
  final verdict = path == null
      ? const LicenceVerdict(status: LicenceStatus.none)
      : Licence.verifyFile(path);

  // Coarse status mirroring licence_tool's status contract:
  //   none -> "none"; valid|grace -> "paid"; invalid|expired -> "free".
  final status = verdict.status == LicenceStatus.none
      ? 'none'
      : (verdict.unlocks ? 'paid' : 'free');

  if (status == 'paid') {
    final tier = verdict.tier != null ? ' (tier: ${verdict.tier})' : '';
    final exp = verdict.expires != null
        ? ', expires: ${verdict.expires!.toIso8601String()}'
        : '';
    return (
      passed: true,
      okLine: 'licence: paid$tier$exp — deploy permitted',
      failLines: const [],
    );
  }

  // Fail closed. Never a sarif finding (§17).
  return (
    passed: false,
    okLine: '',
    failLines: [
      'PRECONDITION NOT MET: licence — '
          'licence status is "$status" — no valid paid licence.',
      'Deploy writes to the outside world and requires a valid paid licence '
          '(licence-only, flat, never per-seat — P1/P2).',
      'Everything before deploy is free; you pay when you ship. Activate your '
          "offline-signed licence with appboxd's licence_tool, then re-run the "
          'deploy gate.',
    ],
  );
}

/// Mirrors licence_tool's _defaultLicencePath: `~/.appbox/licence.json` then
/// `<repoRoot>/pipeline/state/licence.json`. First existing candidate wins.
String? _defaultLicencePath(String repoRoot) {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null) {
    final userPath = '$home/.appbox/licence.json';
    if (File(userPath).existsSync()) return userPath;
  }
  final repoPath = '$repoRoot/pipeline/state/licence.json';
  return File(repoPath).existsSync() ? repoPath : null;
}

/// Python-style truthiness for JSON-derived values (matches `not deploy.get(x)`).
bool _truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  if (v is List) return v.isNotEmpty;
  if (v is Map) return v.isNotEmpty;
  return true;
}
