// RELEASE GATE — dev entitlement keypair checklist artifact.
//
// The arxa entitlement verifier (lib/entitlement.dart) embeds a PUBLIC key;
// the CLI (lib/entitlement_cli.dart `_devSeed`) embeds the matching DEV
// PRIVATE key, compiled into every distributed binary. Anyone who extracts
// it can mint valid entitlements for any machine. This is accepted for
// pre-release dogfooding ONLY.
//
// THIS TEST MUST FAIL BEFORE THE FIRST PAID RELEASE. If it passes, the dev
// keypair is still embedded and shipping. Rotation checklist:
// EXECUTED 2026-08-26 — the production Ed25519 keypair landed:
//   1. `Entitlement.publicKey` now carries the production Totem public key.
//   2. Delete `_devSeed` and the whole `mint --dev` path from
//      lib/entitlement_cli.dart.
//   3. Flip this test to assert the embedded key is NOT the dev key (or
//      delete this file once nothing dev-key-shaped remains).
// (docs/plans/entitlement-backend-runbook.md, "Dev key swap".)

import 'package:arxa/entitlement.dart';
import 'package:test/test.dart';

import 'entitlement_fixture.dart';

void main() {
  test(
      'RELEASE GATE (flipped 2026-08-26): embedded public key is the '
      'PRODUCTION key, never the dev keypair', () {
    expect(
      Entitlement.publicKey,
      isNot(equals(devEntitlementKey.publicKey)),
      reason: 'The embedded entitlement key matches the DEV keypair again — '
          'the production rotation has been reverted. Restore the production '
          'public key: dev-signed tokens must never verify in a shipped '
          'binary.',
    );
  });
}
