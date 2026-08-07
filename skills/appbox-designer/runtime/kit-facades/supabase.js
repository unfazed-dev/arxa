// @ts-check
// kit-facades/supabase.js — Supabase client facade for ejected web apps.
//
// Behind the same Repository/Facade seam the fixture repositories implement.
// ViewModels depend only on Facades, so swapping the fixture reader for this
// changes nothing above it.
//
// Env is passed in explicitly — never read at module scope: on Workers
// process.env does not exist (bindings arrive as the fetch handler's `env`),
// so a module-scope read kills the isolate at import time. Call createSupabase
// once at boot (process.env on node, ctx.env on Workers); it fails THEN, with
// a named error listing every missing var — not at first request with a 500.
//
// Install: npm install @supabase/supabase-js
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (server-side, secret)
//      SUPABASE_WEBHOOK_SECRET (shared secret for the Database Webhooks bridge)
//
// Realtime bridge: prefer Database Webhooks (HTTP POST into the app) over a
// Supabase websocket client inside a Durable Object — outgoing websockets
// cannot hibernate (pinned, billed DO). The webhook republishes onto
// runtime/realtime.js: configure the webhook in the Supabase dashboard with
// an `x-webhook-secret` header, then wire a route:
//
//   const supa = createSupabase(env);
//   // ['POST', '/webhooks/supabase', supa.handleDatabaseWebhook]
import { createClient } from '@supabase/supabase-js';
import { publishEvent } from '../../runtime/realtime.js';

/**
 * @param {Record<string, string | undefined>} env - process.env on node, ctx.env on Workers
 */
export function createSupabase(env) {
  const url = env.SUPABASE_URL;
  const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY;
  const missing = [
    ['SUPABASE_URL', url],
    ['SUPABASE_SERVICE_ROLE_KEY', serviceKey],
  ].filter(([, v]) => !v).map(([k]) => k);
  if (missing.length > 0) {
    throw new Error(
      `supabase facade: missing env vars: ${missing.join(', ')}. ` +
      'Get them from https://supabase.com/dashboard/project/_/settings/api'
    );
  }

  const client = createClient(/** @type {string} */ (url), /** @type {string} */ (serviceKey));

  /**
   * Generic table query helper — mirrors the fixture repository's all() shape.
   * @param {string} table - Supabase table name
   * @param {{ select?: string, filter?: Record<string, unknown>, order?: { column: string, ascending?: boolean }, limit?: number }} [opts]
   * @returns {Promise<unknown[]>} resolved rows (typed by Supabase SDK)
   */
  async function queryAll(table, opts = {}) {
    let q = client.from(table).select(opts.select ?? '*');
    if (opts.filter) q = q.match(opts.filter);
    if (opts.order) q = q.order(opts.order.column, { ascending: opts.order.ascending ?? false });
    if (opts.limit) q = q.limit(opts.limit);
    const { data, error } = await q;
    if (error) throw new Error(`supabase query failed: ${error.message}`);
    return data ?? [];
  }

  /**
   * Database Webhooks HTTP handler (the realtime bridge). Validates the shared
   * secret header, then republishes the change onto the SSE bus: channel
   * `db.<table>`, event `db.insert|db.update|db.delete`, data = the record.
   * Clients listen with hx-sse on /__events?channel=db.<table>.
   * @param {import('hono').Context} c
   */
  async function handleDatabaseWebhook(c) {
    const secret = env.SUPABASE_WEBHOOK_SECRET;
    if (!secret || c.req.header('x-webhook-secret') !== secret) {
      return c.text('unauthorized', 401);
    }
    /** @type {{ type?: string, table?: string, record?: unknown }} */
    const payload = await c.req.json();
    const table = payload.table ?? 'default';
    const type = String(payload.type ?? 'unknown').toLowerCase();
    publishEvent(`db.${table}`, `db.${type}`, JSON.stringify(payload.record ?? {}));
    return c.text('ok');
  }

  return { client, queryAll, handleDatabaseWebhook };
}
