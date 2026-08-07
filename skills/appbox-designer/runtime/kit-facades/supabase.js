// kit-facades/supabase.js — Supabase client facade for ejected web apps.
//
// Behind the same Repository/Facade seam the fixture repositories implement.
// ViewModels depend only on Facades, so swapping the fixture reader for this
// changes nothing above it. Fails at boot (not at first request) if env is
// missing — a named error beats a mysterious 500.
//
// Install: npm install @supabase/supabase-js
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (server-side, secret)
//
// Realtime bridge: prefer Database Webhooks (HTTP POST into the Worker) over
// a Supabase websocket client inside a Durable Object — outgoing websockets
// cannot hibernate (pinned, billed DO). The webhook republishes onto
// runtime/realtime.js.
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) {
  throw new Error(
    'supabase facade requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars. ' +
    'Get them from https://supabase.com/dashboard/project/_/settings/api'
  );
}

export const supabase = createClient(url, serviceKey);

/**
 * Generic table query helper — mirrors the fixture repository's all() shape.
 * @param {string} table - Supabase table name
 * @param {Object} [opts] - { select, filter, order, limit }
 * @returns {Promise<unknown[]>} resolved rows (typed by Supabase SDK)
 */
export async function queryAll(table, opts = {}) {
  let q = supabase.from(table).select(opts.select ?? '*');
  if (opts.filter) q = q.match(opts.filter);
  if (opts.order) q = q.order(opts.order.column, { ascending: opts.order.ascending ?? false });
  if (opts.limit) q = q.limit(opts.limit);
  const { data, error } = await q;
  if (error) throw new Error(`supabase query failed: ${error.message}`);
  return data ?? [];
}
