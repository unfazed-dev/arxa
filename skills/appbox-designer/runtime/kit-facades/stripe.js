// @ts-check
// kit-facades/stripe.js — Stripe facade for ejected web apps.
//
// Uses the official stripe npm package (fetch-based, works on Workers).
//
// Env is passed in explicitly — never read at module scope (on Workers
// process.env does not exist; bindings arrive as the fetch handler's `env`).
// Call createStripe once at boot; it fails then, with a named error listing
// the missing vars.
//
// Install: npm install stripe
// Env: STRIPE_SECRET_KEY (server-side, secret)
//      STRIPE_PUBLISHABLE_KEY (client-side, publishable — emitted to client config)
//      STRIPE_WEBHOOK_SECRET (webhook signing secret — the realtime bridge)
//
// Webhook bridge: constructEventAsync on the raw body (async SubtleCrypto —
// the only variant that works on Workers), respond 200 immediately, broadcast
// via ctx.waitUntil, dedupe on event ID (Stripe retries on slow responses →
// duplicate events). Republishes onto runtime/realtime.js: channel `stripe`,
// event = the Stripe event type. Wire a route:
//
//   const stripeFacade = createStripe(env);
//   // ['POST', '/webhooks/stripe', stripeFacade.handleWebhook]
import Stripe from 'stripe';
import { publishEvent } from '../../runtime/realtime.js';

// Bounded dedupe set — FIFO eviction. Stripe retries for ~3 days, but the
// window that matters is seconds-to-minutes; 500 ids covers a burst replay.
// Deliberate ceiling: in-memory, single-process — a multi-instance deploy
// needs the dedupe in shared storage (KV/Redis), same as the SSE bus.
const SEEN_MAX = 500;
/** @type {Set<string>} */
const seenEvents = new Set();

/** @param {string} id @returns {boolean} true if this id was already processed */
function isDuplicate(id) {
  if (seenEvents.has(id)) return true;
  seenEvents.add(id);
  if (seenEvents.size > SEEN_MAX) {
    const oldest = seenEvents.values().next().value;
    if (oldest !== undefined) seenEvents.delete(oldest);
  }
  return false;
}

/**
 * @param {Record<string, string | undefined>} env - process.env on node, ctx.env on Workers
 */
export function createStripe(env) {
  const secretKey = env.STRIPE_SECRET_KEY;
  const webhookSecret = env.STRIPE_WEBHOOK_SECRET;
  const missing = [
    ['STRIPE_SECRET_KEY', secretKey],
    ['STRIPE_WEBHOOK_SECRET', webhookSecret],
  ].filter(([, v]) => !v).map(([k]) => k);
  if (missing.length > 0) {
    throw new Error(
      `stripe facade: missing env vars: ${missing.join(', ')}. ` +
      'Keys: https://dashboard.stripe.com/apikeys — ' +
      'webhook secret: https://dashboard.stripe.com/webhooks'
    );
  }

  const stripe = new Stripe(/** @type {string} */ (secretKey));

  /**
   * Webhook handler: verify → 200 now → broadcast in the background.
   * @param {import('hono').Context} c
   */
  async function handleWebhook(c) {
    const signature = c.req.header('stripe-signature');
    if (!signature) return c.text('missing stripe-signature header', 400);
    const rawBody = await c.req.text();
    /** @type {Stripe.Event} */
    let event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        rawBody, signature, /** @type {string} */ (webhookSecret));
    } catch (e) {
      return c.text(`invalid signature: ${e instanceof Error ? e.message : e}`, 400);
    }
    if (isDuplicate(event.id)) return c.text('ok'); // Stripe retry — already broadcast

    // Respond 200 immediately; the broadcast rides waitUntil so a slow or
    // frozen isolate (Workers) still completes it after the response ships.
    const broadcast = Promise.resolve().then(() =>
      publishEvent('stripe', event.type, JSON.stringify(event.data.object)));
    // Hono's executionCtx getter THROWS on runtimes without one (node-server)
    // instead of returning undefined — probe it in a try.
    /** @type {((p: Promise<unknown>) => void) | undefined} */
    let waitUntil;
    try {
      const ec = c.executionCtx;
      if (ec?.waitUntil) waitUntil = (p) => ec.waitUntil(p);
    } catch { /* no ExecutionContext on this runtime */ }
    if (waitUntil) waitUntil(broadcast);
    else await broadcast; // node: no executionCtx — publish before responding
    return c.text('ok');
  }

  return { stripe, handleWebhook };
}
