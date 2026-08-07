// @ts-check
// Server-held deadlines for the load-polling timer pattern (ADR-0004):
// the client never decrements — each poll renders `deadline − now`.
//
// Keyed by `${sid}:${timerId}` so concurrent sessions don't collide. The sid
// is carried via AsyncLocalStorage (set by the route-dispatch wrapper in
// router.mjs), so the frozen `h.timers.start(id, seconds)` API needs no `c`.
import { AsyncLocalStorage } from 'node:async_hooks';

const store = new Map(); // `${sid}:${timerId}` → { deadline }
const sidALS = new AsyncLocalStorage();

// router.mjs wraps each handler call: runForSession(sid, () => handler(c, h)).
/**
 * @param {string} sid
 * @param {() => unknown} fn
 */
export function runForSession(sid, fn) {
  return sidALS.run(sid ?? '', fn);
}

/** @param {string} id */
const scopedKey = (id) => `${sidALS.getStore() ?? ''}:${id}`;

/** @type {import('./types').Timers} */
export const timers = {
  /** @param {string} id @param {number} seconds */
  start(id, seconds) {
    store.set(scopedKey(id), { deadline: Date.now() + seconds * 1000 });
  },
  /** @param {string} id @param {number} seconds */
  extend(id, seconds) {
    const t = store.get(scopedKey(id));
    if (t) t.deadline += seconds * 1000;
  },
  /**
   * @param {string} id
   * @returns {number | null}
   */
  remaining(id) {
    const t = store.get(scopedKey(id));
    if (!t) return null;
    return Math.max(0, Math.ceil((t.deadline - Date.now()) / 1000));
  },
  /** @param {string} id */
  stop(id) {
    store.delete(scopedKey(id));
  },
};
