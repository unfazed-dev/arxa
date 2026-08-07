// @ts-check
import { getCookie, setCookie } from 'hono/cookie';

// The session id is an opaque bearer key (128-bit random; all data lives
// server-side) — there is no payload to tamper with, so a signed cookie adds
// nothing here. Switch to hono's signed cookies if the cookie ever encodes data.
// tradeoff: single-process in-memory session store — right for a one-user
// prototype server; the productionize docs name this as a swap point.
const sessions = new Map();

/**
 * @param {import('./types').Context} c
 * @param {import('./types').Next} next
 */
export async function sessionMiddleware(c, next) {
  let sid = getCookie(c)['kdh_sid'];
  if (!sid || !sessions.has(sid)) {
    sid = crypto.randomUUID();
    sessions.set(sid, {});
    // secure everywhere except localhost (global crypto works on Node ≥19 + Workers).
    const secure = !['localhost', '127.0.0.1', '[::1]'].includes(new URL(c.req.url).hostname);
    setCookie(c, 'kdh_sid', sid, { path: '/', httpOnly: true, sameSite: 'Lax', secure });
  }
  c.set('kdh_session', { id: sid, data: sessions.get(sid) });
  await next();
}

/** @param {import('./types').Context} c */
export function sessionOf(c) {
  return c.get('kdh_session');
}

// Small scalar prefs (theme, accent, role) — a JSON cookie, <4 KB (ADR-0004).
/**
 * @param {import('./types').Context} c
 * @returns {import('./types').Prefs}
 */
export function prefsOf(c) {
  try {
    return JSON.parse(getCookie(c)['kdh_prefs'] ?? '{}');
  } catch {
    return {};
  }
}

/**
 * @param {import('./types').Context} c
 * @param {Partial<import('./types').Prefs>} prefs
 */
export function setPrefs(c, prefs) {
  setCookie(c, 'kdh_prefs', JSON.stringify(prefs), {
    path: '/',
    maxAge: 31_536_000,
    sameSite: 'Lax',
  });
}
