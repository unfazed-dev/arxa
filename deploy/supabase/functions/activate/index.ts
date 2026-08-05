// POST /activate — the production entitlement mint path
// (docs/plans/entitlement-backend-runbook.md §3). Also serves
// DELETE /machines/:fpr (self-service seat deactivation) from the same
// router, per runbook §3 step 3.
//
// Auth: Supabase Auth user JWT in the Authorization header. All DB writes go
// through the service role (the schema's RLS is read-own-rows only for
// users). Every failure is a 4xx with an honest error — never a token.
//
// Secrets (supabase secrets set, never in the repo):
//   ENTITLEMENT_ISSUER_JWK — Ed25519 issuer JWK from scripts/keygen.mjs
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — provided by the runtime.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import {
  buildEntitlementClaims,
  ENTITLEMENT_FEATURE,
  mintEntitlementJwt,
} from '../_shared/entitlement_jwt.ts';

const SEAT_CAP = 3; // runbook §2: 3 machines per user
const PLATFORMS = new Set(['macos', 'windows', 'linux']);
const FPR_RE = /^[0-9a-fA-F]{64}$/;

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  try {
    const jwt = (req.headers.get('Authorization') ?? '').replace(
      /^Bearer\s+/i,
      '',
    );
    if (!jwt) return json({ error: 'missing Authorization bearer token' }, 401);

    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    // Step 1: resolve the user from the auth JWT.
    const {
      data: { user },
      error: userError,
    } = await db.auth.getUser(jwt);
    if (userError || !user) {
      return json({ error: 'invalid or expired auth token' }, 401);
    }

    const machineRoute = new URL(req.url).pathname.match(
      /\/machines\/([0-9a-fA-F]{64})\/?$/,
    );
    if (req.method === 'DELETE' && machineRoute) {
      return await deactivate(db, user.id, machineRoute[1].toLowerCase());
    }
    if (req.method === 'POST') return await activate(db, user.id, req);
    return json({ error: 'not found' }, 404);
  } catch (e) {
    console.error('activate: unhandled error', e);
    return json({ error: 'internal error' }, 500);
  }
});

// deno-lint-ignore no-explicit-any
async function activate(db: SupabaseClient<any>, userId: string, req: Request) {
  let body: { fpr?: unknown; platform?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'body must be JSON: { "fpr", "platform" }' }, 400);
  }
  const fpr = typeof body.fpr === 'string' ? body.fpr.toLowerCase() : '';
  if (!FPR_RE.test(fpr)) {
    return json({ error: 'fpr must be the sha256 hex of the machine fingerprint' }, 400);
  }
  if (typeof body.platform !== 'string' || !PLATFORMS.has(body.platform)) {
    return json({ error: 'platform must be macos | windows | linux' }, 400);
  }

  // Step 2: an active (or past_due inside Stripe's retry window) entitlement.
  const { data: rows, error: entError } = await db
    .from('entitlements')
    .select('status, expires_at')
    .eq('user_id', userId)
    .eq('feature', ENTITLEMENT_FEATURE)
    .maybeSingle();
  if (entError) throw entError;
  const entitled =
    rows != null &&
    (rows.status === 'active' || rows.status === 'past_due') &&
    new Date(rows.expires_at).getTime() > Date.now();
  if (!entitled) {
    return json(
      { error: `no active ${ENTITLEMENT_FEATURE} entitlement`, upgrade: true },
      402,
    );
  }

  // Step 3: seat cap — re-issue to a known machine, else require < 3 seats.
  const nowIso = new Date().toISOString();
  const { data: machines, error: machError } = await db
    .from('machines')
    .select('fingerprint_sha256')
    .eq('user_id', userId)
    .is('deactivated_at', null);
  if (machError) throw machError;
  const active = machines ?? [];
  const known = active.some((m) => m.fingerprint_sha256 === fpr);
  if (!known && active.length >= SEAT_CAP) {
    return json(
      {
        error: `seat cap reached (${SEAT_CAP} machines)`,
        hint: 'Deactivate a machine first: DELETE /machines/:fpr on this function.',
      },
      409,
    );
  }

  // Step 4: insert/refresh the machine row.
  const { error: upsertError } = await db.from('machines').upsert(
    known
      ? {
          user_id: userId,
          fingerprint_sha256: fpr,
          platform: body.platform,
          last_seen_at: nowIso,
        }
      : {
          user_id: userId,
          fingerprint_sha256: fpr,
          platform: body.platform,
          activated_at: nowIso,
          last_seen_at: nowIso,
        },
    { onConflict: 'user_id,fingerprint_sha256' },
  );
  if (upsertError) throw upsertError;
  // kimitail: no rate-limit on activate/deactivate cycling (runbook §3 known
  // abuse gap) — activations are logged here; decide limits before launch.
  console.log('activate', JSON.stringify({ userId, fpr, known }));

  // Step 5: mint per runbook §1.
  const issuerJwk = Deno.env.get('ENTITLEMENT_ISSUER_JWK');
  if (!issuerJwk) {
    console.error('activate: ENTITLEMENT_ISSUER_JWK secret is not set');
    return json({ error: 'issuer not configured' }, 500);
  }
  const claims = buildEntitlementClaims(
    userId,
    fpr,
    Math.floor(Date.now() / 1000),
  );
  const token = await mintEntitlementJwt(issuerJwk, claims);
  return json({ token }, 200);
}

// Self-service deactivation (runbook §3 step 3): sets deactivated_at on the
// caller's own machine row. The seat is freed immediately; already-minted
// tokens for that machine still verify until exp (offline grace is deliberate).
// deno-lint-ignore no-explicit-any
async function deactivate(db: SupabaseClient<any>, userId: string, fpr: string) {
  const { data, error } = await db
    .from('machines')
    .update({ deactivated_at: new Date().toISOString() })
    .eq('user_id', userId)
    .eq('fingerprint_sha256', fpr)
    .is('deactivated_at', null)
    .select('fingerprint_sha256');
  if (error) throw error;
  if (!data || data.length === 0) {
    return json({ error: 'no active machine with that fingerprint' }, 404);
  }
  console.log('deactivate', JSON.stringify({ userId, fpr }));
  return json({ deactivated: fpr }, 200);
}
