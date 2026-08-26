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
//   1. Replace `Entitlement.publicKey` with the production Totem public key.
//   2. Delete `_devSeed` and the whole `mint --dev` path from
//      lib/entitlement_cli.dart.
//   3. Flip this test to assert the embedded key is NOT the dev key (or
//      delete this file once nothing dev-key-shaped remains).
// (docs/plans/entitlement-backend-runbook.md, "Dev key swap".)

import 'package:arxa/entitlement.dart';
import 'package:test/test.dart';

import 'entitlement_fixture.dart';

void main() {
  test('embedded public key is still the DEV keypair — rotation pending', () {
    expect(
      Entitlement.publicKey,
      devEntitlementKey.publicKey,
      reason: 'The embedded entitlement key no longer matches the dev '
          'keypair: the production key has landed. Flip or delete this '
          'release-gate test (see its file header).',
    );
  });
}
