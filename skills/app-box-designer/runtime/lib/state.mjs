import { getCookie, setCookie } from 'hono/cookie';
import { randomUUID } from 'node:crypto';

// tradeoff: single-process in-memory session store — right for a one-user
// prototype server; the productionize docs name this as a swap point.
const sessions = new Map();

// Reload continuity (serve.mjs hot reload): the worker snapshots on shutdown
// and restores on boot, so a code change no longer drops live sessions.
export function snapshotSessions() {
  return Object.fromEntries(sessions);
}
export function restoreSessions(obj) {
  for (const [k, v] of Object.entries(obj ?? {})) sessions.set(k, v);
}

export async function sessionMiddleware(c, next) {
  let sid = getCookie(c)['kdh_sid'];
  if (!sid || !sessions.has(sid)) {
    sid = randomUUID();
    sessions.set(sid, {});
    setCookie(c, 'kdh_sid', sid, { path: '/', httpOnly: true, sameSite: 'Lax' });
  }
  c.set('kdh_session', { id: sid, data: sessions.get(sid) });
  await next();
}

export function sessionOf(c) {
  return c.get('kdh_session');
}

// Small scalar prefs (theme, accent, role) — a JSON cookie, <4 KB (ADR-0004).
export function prefsOf(c) {
  try {
    return JSON.parse(getCookie(c)['kdh_prefs'] ?? '{}');
  } catch {
    return {};
  }
}

export function setPrefs(c, prefs) {
  setCookie(c, 'kdh_prefs', JSON.stringify(prefs), {
    path: '/',
    maxAge: 31_536_000,
    sameSite: 'Lax',
  });
}
