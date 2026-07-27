// frozen_clock.mjs — node --import preload that pins wall-clock time for the
// duration of an emit_htmx render pass.
//
// WHY: the htmx design tree reads the wall clock while rendering
// (services/facades/player_facade.js: `startedAt: Date.now()` on session
// creation, `restEnd - Date.now()` for the rest countdown), so train.player
// renders `0:00` on one request and `0:01` on the next. That single volatile
// node would make emit's write-on-diff no-op impossible: every run would
// rewrite the surface and dirty `git status`.
//
// The fix is determinism at the SOURCE, not a loosened diff: freeze the clock
// so the whole tree renders "at a fixed instant" and every time-derived value
// is reproducible. Stripping the volatile node instead would hide real drift
// in any OTHER time-derived value that appears later.
//
// Scope is deliberately narrow — only the two zero-argument readings of "now":
//   * Date.now()
//   * new Date()  /  Date()
// Date.parse, Date.UTC, and `new Date(<args>)` are untouched, so date
// arithmetic on explicit inputs still behaves normally. Timers are unaffected
// (node's timers use monotonic hrtime, not Date), so the server still boots,
// serves, and shuts down as usual.
//
// The epoch is a fixed constant, NOT "the time this preload loaded" — two
// separate emit runs must produce byte-identical output, and they only do if
// both processes agree on the same instant.
//   2026-01-01T00:00:00Z — arbitrary, stable, and comfortably in the tree's
//   own "present" so nothing renders as absurdly past or future.
const FROZEN_MS = Date.UTC(2026, 0, 1, 0, 0, 0);

const RealDate = Date;

const FrozenDate = function Date(...args) {
  // `Date()` called without `new` returns a string in the real implementation.
  if (!new.target) return new RealDate(FROZEN_MS).toString();
  if (args.length === 0) return new RealDate(FROZEN_MS);
  return new RealDate(...args);
};

FrozenDate.prototype = RealDate.prototype;
FrozenDate.now = () => FROZEN_MS;
FrozenDate.parse = RealDate.parse;
FrozenDate.UTC = RealDate.UTC;
Object.setPrototypeOf(FrozenDate, RealDate);

globalThis.Date = FrozenDate;
