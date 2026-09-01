# stripe-webhook — deploy + dashboard runbook (the operator half)

The function (`index.ts`) is the ONLY writer of `subscriptions`/
`entitlements` (schema RLS: read-own-rows for users, writes service-role
only). Signature-verified (HMAC-SHA256, timing-safe, 5-minute replay
window); deployed **without** Supabase JWT verification — the caller is
Stripe.

## 1. Stripe dashboard (manual, once per environment)

1. **Products/prices per the tiers** (runbook §5): Pro (~$20–40/seat/mo)
   and Scale ($149/mo/org, +$49/app/mo beyond 3). CRITICAL: set each
   price's **lookup_key** to exactly `pro` / `scale` — the webhook derives
   the tier from it and 400s (with a named error) on anything else.
2. **Webhook endpoint**: `https://smjuargdrbpaptduqdgf.supabase.co/functions/v1/stripe-webhook`
   with events `customer.subscription.created`, `customer.subscription.updated`,
   `customer.subscription.deleted`, `checkout.session.completed`.
3. Copy the signing secret (`whsec_…`).

## 2. Deploy (repo root)

    supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_…
    supabase functions deploy stripe-webhook --no-verify-jwt

## 3. Checkout contract (when the checkout flow is built)

Embed the Supabase user id so renewals resolve even if metadata is lost:

    metadata: { user_id: '<supabase auth uuid>' }

on BOTH the checkout session and the subscription. Fallback: the webhook
resolves renewals by `stripe_customer_id` from the mirrored row.

## 4. Verify

    # Stripe CLI forward + trigger (dev):
    stripe listen --forward-to localhost:54321/functions/v1/stripe-webhook
    stripe trigger customer.subscription.updated

Expected: 200 `{mirrored, tier, status, entitlement}` and a row in
`subscriptions` + `entitlements`. Negative checks: missing signature → 400
`invalid signature`; tampered body → 400; price without a lookup_key → 400
naming the fix; unknown event type → 200 `{ignored: …}`.

## Behavior notes

- **Idempotent**: all writes are primary-key upserts — Stripe's retries are
  safe.
- **Dunning stays in Stripe** (runbook §5): the entitlement row mirrors
  `past_due`/`canceled` verbatim; the client's 30-day offline grace is a
  separate clock.
- **Fail-closed**: no `STRIPE_WEBHOOK_SECRET` → 500 (an unauthenticated
  webhook would let anyone mint entitlement rows).