// POST /stripe-webhook — Stripe → subscriptions/entitlements mirror
// (docs/plans/entitlement-backend-runbook.md §5). The ONLY writer of those
// tables. Deploy with --no-verify-jwt: the caller is Stripe and the auth is
// the Stripe signature, not a Supabase session.
//
// Secrets (supabase secrets set, never in the repo):
//   STRIPE_WEBHOOK_SECRET — whsec_… from the Stripe dashboard endpoint
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — provided by the runtime.
//
// Events handled: customer.subscription.created/updated/deleted and
// checkout.session.completed. Everything else 200-ignores — Stripe needs a
// 2xx to stop retrying, and unknown events are future features, not errors.
//
// user resolution: the checkout flow embeds metadata.user_id (the Supabase
// auth uuid) on the session and subscription; renewals fall back to the
// existing subscriptions row keyed by stripe_customer_id. An unresolvable
// event 200s with {ignored:'no-user'} + console.error — visible in the
// functions log, no retry storm.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

const FEATURE = 'emit.scaffold'; // runbook §5: the entitlement Stripe maps onto
const TIERS = new Set(['pro', 'scale', 'agency']); // schema check constraint
const SIGNATURE_TOLERANCE_SECS = 300; // Stripe's own recommendation

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

/** Constant-time compare of two same-length hex strings. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Verify the Stripe-Signature header against the RAW body. `t=ts,v1=sig`
 * (v1 may repeat; any match wins, per Stripe's rotation scheme). Stale
 * timestamps are rejected outright — the signature proves the body, the
 * timestamp bounds replay.
 */
async function verifyStripeSignature(
  header: string | null,
  rawBody: string,
  secret: string,
): Promise<boolean> {
  if (!header) return false;
  const parts = header.split(',').map((p) => p.trim().split('=', 2));
  const ts = parts.find(([k]) => k === 't')?.[1];
  const sigs = parts.filter(([k]) => k === 'v1').map(([, v]) => v);
  if (!ts || sigs.length === 0) return false;
  const age = Math.abs(Date.now() / 1000 - Number(ts));
  if (!Number.isFinite(age) || age > SIGNATURE_TOLERANCE_SECS) return false;
  const expected = await hmacHex(secret, `${ts}.${rawBody}`);
  return sigs.some((s) => timingSafeEqual(s.toLowerCase(), expected));
}

interface StripeSubscription {
  id: string;
  customer: string;
  status: string;
  current_period_end: number;
  metadata?: Record<string, string>;
  items?: {
    data?: Array<{ price?: { lookup_key?: string; metadata?: Record<string, string> } }>;
  };
}

/** Stripe subscription status → the entitlements status vocabulary. */
function entitlementStatus(stripeStatus: string): string {
  if (stripeStatus === 'active' || stripeStatus === 'trialing') return 'active';
  if (
    stripeStatus === 'past_due' ||
    stripeStatus === 'incomplete' ||
    stripeStatus === 'incomplete_expired'
  ) {
    return 'past_due';
  }
  return 'canceled'; // canceled | unpaid | expired and anything unforeseen
}

/** Tier from the price lookup_key, then subscription metadata; schema-constrained. */
function tierOf(sub: StripeSubscription): string | null {
  const fromPrice = sub.items?.data?.[0]?.price?.lookup_key;
  const fromMeta = sub.metadata?.tier;
  const tier = fromPrice ?? fromMeta ?? '';
  return TIERS.has(tier) ? tier : null;
}

/**
 * Resolve the Supabase user: checkout embeds metadata.user_id; renewals may
 * arrive without it, so fall back to the mirrored subscriptions row keyed
 * by the Stripe customer id.
 */
async function resolveUser(
  db: SupabaseClient,
  metadataUserId: string | undefined,
  stripeCustomerId: string,
): Promise<string | null> {
  if (metadataUserId) return metadataUserId;
  const { data } = await db
    .from('subscriptions')
    .select('user_id')
    .eq('stripe_customer_id', stripeCustomerId)
    .maybeSingle();
  return data?.user_id ?? null;
}

/** Mirror one subscription (and its entitlement row) — idempotent upserts. */
async function mirrorSubscription(
  db: SupabaseClient,
  sub: StripeSubscription,
): Promise<Response> {
  const tier = tierOf(sub);
  if (!tier) {
    // A price without a recognized lookup_key is a DASHBOARD misconfig —
    // 400 makes Stripe retry (with backoff) and the functions log names it.
    return json(
      { error: 'unrecognized tier: set the price lookup_key to pro|scale|agency' },
      400,
    );
  }
  const userId = await resolveUser(db, sub.metadata?.user_id, sub.customer);
  if (!userId) {
    console.error(
      `stripe-webhook: no user for customer ${sub.customer} — embed metadata.user_id at checkout`,
    );
    return json({ ignored: 'no-user' }, 200);
  }
  const periodEnd = new Date(sub.current_period_end * 1000).toISOString();
  const entStatus = entitlementStatus(sub.status);

  const { error: subError } = await db.from('subscriptions').upsert({
    user_id: userId,
    stripe_customer_id: sub.customer,
    stripe_subscription_id: sub.id,
    tier,
    status: sub.status,
    current_period_end: periodEnd,
    updated_at: new Date().toISOString(),
  });
  if (subError) return json({ error: `subscriptions write failed: ${subError.message}` }, 500);

  const { error: entError } = await db.from('entitlements').upsert({
    user_id: userId,
    feature: FEATURE,
    status: entStatus,
    expires_at: periodEnd,
  });
  if (entError) {
    return json({ error: `entitlements write failed: ${entError.message}` }, 500);
  }
  return json({ mirrored: sub.id, tier, status: sub.status, entitlement: entStatus }, 200);
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const secret = Deno.env.get('STRIPE_WEBHOOK_SECRET');
  if (!secret) {
    // Fail closed and loud: an unauthenticated webhook endpoint would let
    // anyone write entitlements.
    return json({ error: 'STRIPE_WEBHOOK_SECRET not set' }, 500);
  }

  const rawBody = await req.text();
  const ok = await verifyStripeSignature(
    req.headers.get('stripe-signature'),
    rawBody,
    secret,
  );
  if (!ok) return json({ error: 'invalid signature' }, 400);

  let event: {
    type?: string;
    data?: { object?: Record<string, unknown> };
  };
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: 'malformed json' }, 400);
  }

  const object = event.data?.object ?? {};
  switch (event.type) {
    case 'customer.subscription.created':
    case 'customer.subscription.updated':
    case 'customer.subscription.deleted':
      return await mirrorSubscription(db(), object as unknown as StripeSubscription);
    case 'checkout.session.completed': {
      // The subscription object rides the session; when checkout completes
      // without one (one-time purchase), there is nothing to mirror.
      const sub = (object.subscription ?? object) as unknown as StripeSubscription;
      if (!sub || typeof sub.id !== 'string' || !sub.customer) {
        return json({ ignored: 'no-subscription' }, 200);
      }
      return await mirrorSubscription(db(), sub);
    }
    default:
      return json({ ignored: event.type ?? 'unknown' }, 200);
  }
});

function db(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
}