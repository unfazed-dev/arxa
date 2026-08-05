// Shared entitlement-JWT minter for the /activate Edge Function.
//
// Pure Web APIs only (WebCrypto, TextEncoder, btoa — no Deno/Node imports) so
// the exact same code runs in the Supabase Edge Runtime (Deno) AND in the
// local Node harness (deploy/supabase/scripts/local_mint_check.mjs), which
// cross-checks its output against the Dart verifier
// (`appbox entitlement verify`, appboxd/lib/entitlement.dart).
//
// Token contract (docs/plans/entitlement-backend-runbook.md §1 — the client
// verifier is the authority):
//   header  {"alg":"EdDSA","typ":"JWT"}   — alg MUST be EdDSA
//   claims  sub / fpr / feat / iat / nbf / exp (epoch seconds)
//   signature  Ed25519 over the exact ASCII bytes of "<header>.<payload>"
// The verifier never re-encodes, so the compact parts are signed verbatim and
// emitted unpadded base64url (the verifier accepts padded too).

export interface EntitlementClaims {
  sub: string; // Supabase user id
  fpr: string; // sha256 hex of the machine fingerprint (never the raw id)
  feat: string[]; // MUST contain "emit.scaffold"
  iat: number; // issued-at (ignored by the verifier, carried for operators)
  nbf: number; // not-before, epoch seconds
  exp: number; // expiry, epoch seconds (issue with nbf + 7*86400)
}

export const ENTITLEMENT_FEATURE = 'emit.scaffold';
export const TOKEN_TTL_SECONDS = 7 * 86400; // runbook §1: ≈ 7 days

function b64url(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

/// Claims for [sub]/[fpr] spanning now..now+ttl, per runbook §3 step 5.
export function buildEntitlementClaims(
  sub: string,
  fpr: string,
  nowSeconds: number,
  ttlSeconds: number = TOKEN_TTL_SECONDS,
): EntitlementClaims {
  return {
    sub,
    fpr: fpr.toLowerCase(),
    feat: [ENTITLEMENT_FEATURE],
    iat: nowSeconds,
    nbf: nowSeconds,
    exp: nowSeconds + ttlSeconds,
  };
}

/// Mints a compact JWS. [issuerJwkJson] is the Supabase secret
/// ENTITLEMENT_ISSUER_JWK: an Ed25519 JWK {"kty":"OKP","crv":"Ed25519","d","x"}
/// (the output of deploy/supabase/scripts/keygen.mjs — the private half never
/// enters the repo).
export async function mintEntitlementJwt(
  issuerJwkJson: string,
  claims: EntitlementClaims,
): Promise<string> {
  const jwk = JSON.parse(issuerJwkJson);
  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: jwk.kty, crv: jwk.crv, d: jwk.d, x: jwk.x },
    { name: 'Ed25519' },
    false,
    ['sign'],
  );
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify({ alg: 'EdDSA', typ: 'JWT' })));
  const payload = b64url(enc.encode(JSON.stringify(claims)));
  // Sign the exact compact bytes — never a re-encoded form.
  const signingInput = enc.encode(`${header}.${payload}`);
  const sig = await crypto.subtle.sign({ name: 'Ed25519' }, key, signingInput);
  return `${header}.${payload}.${b64url(new Uint8Array(sig))}`;
}
