// Server-held deadlines for the load-polling timer pattern (ADR-0004):
// the client never decrements — each poll renders `deadline − now`.
// tradeoff: process-global registry — fine for a single-user prototype;
// key ids by `${session.id}:name` if concurrent sessions ever matter.
const store = new Map();

// Reload continuity — see snapshotSessions in state.mjs.
export function snapshotTimers() {
  return Object.fromEntries(store);
}
export function restoreTimers(obj) {
  for (const [k, v] of Object.entries(obj ?? {})) store.set(k, v);
}

export const timers = {
  start(id, seconds) {
    store.set(id, { deadline: Date.now() + seconds * 1000 });
  },
  extend(id, seconds) {
    const t = store.get(id);
    if (t) t.deadline += seconds * 1000;
  },
  remaining(id) {
    const t = store.get(id);
    if (!t) return null;
    return Math.max(0, Math.ceil((t.deadline - Date.now()) / 1000));
  },
  stop(id) {
    store.delete(id);
  },
};
