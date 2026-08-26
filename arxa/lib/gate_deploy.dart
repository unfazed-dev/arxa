// Deploy gate — port of gates/deploy/deploy.sh to Dart.
//
// Plan 11: asserts the three deployment prerequisites are confirmed in
// pipeline state before a target ships — the build target, the version, and
// the releasing account. This gate owns only the confirmation contract, so the
// pipeline cannot ship a build whose target/version/account is unset.
//
// D17/D18 (docs/plans/monetization-and-entitlements.md): the payment boundary
// moved from deploy to scaffold — the old §17 licence assertion and the
// ARXA_DEV_LICENCE bypass that weakened it are REMOVED (the licence file
// itself is retired; the entitlement JWT is asserted in scaffoldMain and
// scaffoldGate). What remains here is the pipeline-state contract, still
// fail-closed.

import 'dart:io';

import 'package:arxa/gates.dart';

GateResult deployGate(GateContext ctx) {
  final details = <String>[];
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
  final targets = ctx.targets;
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
