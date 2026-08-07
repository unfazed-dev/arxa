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
export function runForSession(sid, fn) {
  return sidALS.run(sid ?? '', fn);
}

const scopedKey = (id) => `${sidALS.getStore() ?? ''}:${id}`;

// Reload continuity — see snapshotSessions in state.mjs.
export function snapshotTimers() {
  return Object.fromEntries(store);
}
export function restoreTimers(obj) {
  for (const [k, v] of Object.entries(obj ?? {})) store.set(k, v);
}

export const timers = {
  start(id, seconds) {
    store.set(scopedKey(id), { deadline: Date.now() + seconds * 1000 });
  },
  extend(id, seconds) {
    const t = store.get(scopedKey(id));
    if (t) t.deadline += seconds * 1000;
  },
  remaining(id) {
    const t = store.get(scopedKey(id));
    if (!t) return null;
    return Math.max(0, Math.ceil((t.deadline - Date.now()) / 1000));
  },
  stop(id) {
    store.delete(scopedKey(id));
  },
};
