// kit-facades/stripe.js — Stripe facade for ejected web apps.
//
// Uses the official stripe npm package (fetch-based, works on Workers).
// Fails at boot if STRIPE_SECRET_KEY is missing.
//
// Webhook handler: on Workers use constructEventAsync (async SubtleCrypto) on
// the raw body, respond 200 immediately, broadcast via ctx.waitUntil, and
// dedupe on event ID (Stripe retries on slow responses → duplicate events).
// The webhook republishes onto runtime/realtime.js.
//
// Install: npm install stripe
// Env: STRIPE_SECRET_KEY (server-side, secret)
//      STRIPE_PUBLISHABLE_KEY (client-side, publishable — emitted to client config)
import Stripe from 'stripe';

const secretKey = process.env.STRIPE_SECRET_KEY;
if (!secretKey) {
  throw new Error(
    'stripe facade requires STRIPE_SECRET_KEY env var. ' +
    'Get it from https://dashboard.stripe.com/apikeys'
  );
}

export const stripe = new Stripe(secretKey);

/**
 * Verify a Stripe webhook signature and parse the event.
 * On Workers: pass the raw body (await req.text()) and the signature header.
 * @param {string} rawBody - raw request body (not parsed)
 * @param {string} signature - Stripe-Signature header value
 * @param {string} endpointSecret - your webhook signing secret
 * @returns {Promise<Stripe.Event>}
 */
export async function verifyWebhook(rawBody, signature, endpointSecret) {
  return stripe.webhooks.constructEventAsync(rawBody, signature, endpointSecret);
}
