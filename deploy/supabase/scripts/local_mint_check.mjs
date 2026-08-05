#!/usr/bin/env node
// local_mint_check — local proof that the /activate minting logic produces
// tokens the shipped Dart verifier accepts. No Supabase, no network: the
// shared minter (functions/_shared/entitlement_jwt.ts — the exact code the
// Edge Function imports) signs tokens with the DEV keypair, and
// `appbox entitlement status/verify --token <file>` (the real client
// verifier, appboxd/lib/entitlement.dart) judges them.
//
//   node --experimental-strip-types deploy/supabase/scripts/local_mint_check.mjs
//
// Exit 0 = every scenario's Dart verdict matches the expectation.
// The DEV keypair is a test fixture (appboxd/test/entitlement_fixture.dart),
// not a secret; using it proves byte-contract compatibility with the public
// key embedded in the client today. The production path differs ONLY in the
// JWK passed to mintEntitlementJwt.

import { generateKeyPairSync, createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  buildEntitlementClaims,
  mintEntitlementJwt,
} from '../functions/_shared/entitlement_jwt.ts';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const appboxd = join(repoRoot, 'appboxd');
const DAY = 86400;

// DEV keypair — matches Entitlement.publicKey (appboxd/lib/entitlement.dart)
// and the fixture seed. TEST FIXTURE ONLY, never the production key.
const DEV_JWK = JSON.stringify({
  kty: 'OKP',
  crv: 'Ed25519',
  d: hexToB64url('37346f25f6ff375d0901448591d7cb81c4684b25e57d0a1e3882579296873809'),
  x: hexToB64url('f3251c81da2ad5932308ec72886a19ea0c0309ef115417fffb41e746522fdd07'),
});

function hexToB64url(hex) {
  return Buffer.from(hex, 'hex').toString('base64url');
}

// Mirror of Entitlement.machineFingerprint (appboxd/lib/entitlement.dart):
// sha256 hex of the raw per-OS machine id. Fails loudly when undeterminable.
function machineFingerprint() {
  let raw = null;
  if (process.platform === 'darwin') {
    const out = execFileSync('/usr/sbin/ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice'], { encoding: 'utf8' });
    raw = out.match(/"IOPlatformUUID"\s*=\s*"([^"]+)"/)?.[1] ?? null;
  } else if (process.platform === 'linux') {
    for (const p of ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
      try { raw = readFileSync(p, 'utf8').trim(); break; } catch { /* next */ }
    }
  } else if (process.platform === 'win32') {
    const out = execFileSync(
      `${process.env.SystemRoot ?? 'C:\\Windows'}\\System32\\reg.exe`,
      ['query', 'HKLM\\SOFTWARE\\Microsoft\\Cryptography', '/v', 'MachineGuid'],
      { encoding: 'utf8' },
    );
    raw = out.match(/MachineGuid\s+REG_SZ\s+(\S+)/)?.[1] ?? null;
  }
  if (!raw) throw new Error(`machine fingerprint undeterminable on ${process.platform}`);
  return createHash('sha256').update(raw, 'utf8').digest('hex');
}

// Runs the real CLI verifier. Returns { exit, verdict } (verdict = parsed JSON line).
function dartEntitlement(sub, args, tokenFile) {
  const res = spawnSync(
    'dart',
    ['run', 'bin/appbox.dart', 'entitlement', sub, ...args, tokenFile],
    { cwd: appboxd, encoding: 'utf8' },
  );
  if (res.error) throw res.error;
  const line = res.stdout.trim().split('\n').find((l) => l.startsWith('{'));
  if (!line) throw new Error(`no JSON verdict on stdout:\n${res.stdout}\n${res.stderr}`);
  return { exit: res.status, verdict: JSON.parse(line) };
}

let failures = 0;
function check(name, token, { exit, status, verifyStatus }) {
  const tmp = join(tmpdir(), `appbox-ent-${process.pid}-${Math.random().toString(36).slice(2)}.jwt`);
  writeFileSync(tmp, token);
  try {
    const s = dartEntitlement('status', ['--token'], tmp);
    const v = dartEntitlement('verify', [], tmp);
    const ok =
      s.exit === exit && s.verdict.status === status &&
      v.exit === exit && v.verdict.status === verifyStatus;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`);
    if (!ok) {
      failures++;
      console.log(`  expected status=${status}/${verifyStatus} exit=${exit}`);
      console.log(`  got      status=${s.verdict.status}/${v.verdict.status} ` +
        `exit=${s.exit}/${v.exit} reason=${JSON.stringify(v.verdict.reason)}`);
    }
  } finally {
    rmSync(tmp, { force: true });
  }
}

const now = Math.floor(Date.now() / 1000);
const fpr = machineFingerprint();
console.log(`machine fingerprint: ${fpr}`);
console.log('cross-checking function-minted tokens against the Dart verifier…\n');

// 1. The production-shaped happy path (runbook §3 step 5).
check('valid token (sub/fpr/feat/iat/nbf/exp, EdDSA, 7d TTL)',
  await mintEntitlementJwt(DEV_JWK, buildEntitlementClaims('user_prod_01', fpr, now)),
  { exit: 0, status: 'entitled', verifyStatus: 'valid' });

// 2. Offline grace: expired 1d ago, inside the 30d client-side grace.
check('expired 1d ago — offline-continuation grace unlocks',
  await mintEntitlementJwt(DEV_JWK, buildEntitlementClaims('user_prod_01', fpr, now - 8 * DAY, 7 * DAY)),
  { exit: 0, status: 'entitled', verifyStatus: 'grace' });

// 3. Expired past grace (31d) — no unlock, but authentic claims reported.
check('expired 31d ago — past grace, does not unlock',
  await mintEntitlementJwt(DEV_JWK, buildEntitlementClaims('user_prod_01', fpr, now - 38 * DAY, 7 * DAY)),
  { exit: 1, status: 'unentitled', verifyStatus: 'expired' });

// 4. Missing the emit.scaffold feature.
check('feat without emit.scaffold — invalid',
  await mintEntitlementJwt(DEV_JWK, { ...buildEntitlementClaims('user_prod_01', fpr, now), feat: ['design.view'] }),
  { exit: 1, status: 'unentitled', verifyStatus: 'invalid' });

// 5. Bound to a different machine.
check('fpr for another machine — invalid',
  await mintEntitlementJwt(DEV_JWK, buildEntitlementClaims('user_prod_01', '00'.repeat(32), now)),
  { exit: 1, status: 'unentitled', verifyStatus: 'invalid' });

// 6. Future-dated nbf.
check('nbf in the future — invalid',
  await mintEntitlementJwt(DEV_JWK, buildEntitlementClaims('user_prod_01', fpr, now + 3600, 7 * DAY)),
  { exit: 1, status: 'unentitled', verifyStatus: 'invalid' });

// 7. Tampered payload (re-encoded claims, signature untouched).
{
  const good = await mintEntitlementJwt(DEV_JWK, buildEntitlementClaims('user_prod_01', fpr, now));
  const [h, p, s] = good.split('.');
  const tampered = `${h}.${Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(p, 'base64url').toString()), sub: 'mallory' })).toString('base64url')}.${s}`;
  check('tampered payload — invalid (signature covers exact bytes)', tampered,
    { exit: 1, status: 'unentitled', verifyStatus: 'invalid' });
}

// 8. Signed by an unknown key (wrong issuer).
{
  const { privateKey } = generateKeyPairSync('ed25519');
  check('signed by a non-issuer key — invalid',
    await mintEntitlementJwt(JSON.stringify(privateKey.export({ format: 'jwk' })),
      buildEntitlementClaims('user_prod_01', fpr, now)),
    { exit: 1, status: 'unentitled', verifyStatus: 'invalid' });
}

console.log(failures === 0 ? '\nALL PASS' : `\n${failures} scenario(s) FAILED`);
process.exit(failures === 0 ? 0 : 1);
