// @ts-check
import { getCookie, setCookie } from 'hono/cookie';

// The session id is an opaque bearer key (128-bit random; all data lives
// server-side) — there is no payload to tamper with, so a signed cookie adds
// nothing here. Switch to hono's signed cookies if the cookie ever encodes data.
// tradeoff: single-process in-memory session store — right for a one-user
// prototype server; the productionize docs name this as a swap point.
const sessions = new Map();

/**
 * @param {import('./types').Context} context
 * @param {import('./types').Next} next
 */
export async function sessionMiddleware(context, next) {
  let sid = getCookie(context)['kdh_sid'];
  if (!sid || !sessions.has(sid)) {
    sid = crypto.randomUUID();
    sessions.set(sid, {});
    // secure everywhere except localhost (global crypto works on Node ≥19 + Workers).
    const secure = !['localhost', '127.0.0.1', '[::1]'].includes(new URL(context.req.url).hostname);
    setCookie(context, 'kdh_sid', sid, { path: '/', httpOnly: true, sameSite: 'Lax', secure });
  }
  context.set('kdh_session', { id: sid, data: sessions.get(sid) });
  await next();
}

/** @param {import('./types').Context} context */
export function sessionOf(context) {
  return context.get('kdh_session');
}

// Small scalar prefs (theme, accent, role) — a JSON cookie, <4 KB (ADR-0004).
/**
 * @param {import('./types').Context} context
 * @returns {import('./types').Prefs}
 */
export function prefsOf(context) {
  try {
    return JSON.parse(getCookie(context)['kdh_prefs'] ?? '{}');
  } catch {
    return {};
  }
}

/**
 * @param {import('./types').Context} context
 * @param {Partial<import('./types').Prefs>} prefs
 */
export function setPrefs(context, prefs) {
  setCookie(context, 'kdh_prefs', JSON.stringify(prefs), {
    path: '/',
    maxAge: 31_536_000,
    sameSite: 'Lax',
  });
}
