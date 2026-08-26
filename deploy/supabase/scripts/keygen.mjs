#!/usr/bin/env node
// keygen — generate the PRODUCTION Ed25519 entitlement-issuer keypair
// (docs/plans/entitlement-backend-runbook.md §1 "Signing key", §7 "Key
// management"). Local-only: the private half NEVER enters the repo — output
// lands in deploy/supabase/secrets/ which is gitignored.
//
//   node deploy/supabase/scripts/keygen.mjs           # first issuance
//   node deploy/supabase/scripts/keygen.mjs --force   # deliberate rotation
//
// Then, manually:
//   1. supabase secrets set ENTITLEMENT_ISSUER_JWK="$(cat deploy/supabase/secrets/entitlement-issuer.jwk.json)"
//   2. Replace Entitlement.publicKey in arxa/lib/entitlement.dart with the
//      printed public hex, delete `mint --dev`, flip test/release_gate_test.dart
//      (the rotation checklist lives in that file's header).

import { generateKeyPairSync } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const outDir = join(
  dirname(fileURLToPath(import.meta.url)),
  '..',
  'secrets',
);
const outFile = join(outDir, 'entitlement-issuer.jwk.json');

if (existsSync(outFile) && !process.argv.includes('--force')) {
  console.error(
    `REFUSING to overwrite ${outFile} — an issuer key already exists.\n` +
      'Rotation is a deliberate act (clients pin the public key): re-run with --force.',
  );
  process.exit(1);
}

const { privateKey, publicKey } = generateKeyPairSync('ed25519');
const jwk = privateKey.export({ format: 'jwk' }); // { kty, crv, x, d }
const pubRaw = publicKey.export({ format: 'der', type: 'spki' });
const pubHex = Buffer.from(pubRaw).subarray(-32).toString('hex'); // raw 32-byte key

mkdirSync(outDir, { recursive: true });
writeFileSync(outFile, JSON.stringify(jwk, null, 2) + '\n', { mode: 0o600 });
chmodSync(outFile, 0o600);

console.log(`issuer JWK (PRIVATE — gitignored, chmod 600): ${outFile}`);
console.log(`public key (raw 32-byte hex, embed in Entitlement.publicKey):\n${pubHex}`);
