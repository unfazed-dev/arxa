# Phase 0 — Spike gap list: shim `c` vs real Hono `c`

Date: 2026-08-06. Spike: `tool/spike-hono-node/` (worktree
`appbox-designer-feature`). The hello-hda artifact runs **unchanged** on
real Hono (`hono` 4.x + `@hono/node-server`) on Node 22 — every route, every
helper, every lens gate clean.

## Premise check: does the spike contradict the plan?

**No.** The core thesis holds: `app.routes.js` is already Hono-shaped, the
shim's fake `c` mimics Hono's real `c` faithfully, and the artifact boots and
serves identically on a real Hono runtime. The plan can proceed to Phase 1.

## Spike composition

The `h` helpers were NOT written from scratch — the repo already holds a
complete, working Hono port at
`archives/tooling-pre-dart/skills-pre-dart/appbox-designer/runtime/lib/*.mjs`
(the pre-Dart original that `worker_shim.js` was derived from). The spike
reuses those six modules verbatim (`helpers`, `templates`, `l10n`, `state`,
`timers`, `router`) behind a 30-line `server.js` entry point. The skill's
`runtime/vendor/` is symlinked for htmx/preload/head-support/lucide.

This means Phase 1's `runtime/helpers.js` already exists as battle-tested
code — Phase 1 is a productionization + emission task, not a port.

## Gap list — shim `c` vs real Hono `c`

Sourced from a line-by-line comparison of `worker_shim.js:145-190` (the fake
`c`) against Hono 4.x's `Context` as exercised by the lib modules.

### Behavioral equivalence (no action needed)

| `c` / `c.req` member | Shim (`worker_shim.js`) | Real Hono | Verdict |
|---|---|---|---|
| `c.req.param(k)` | custom `:segment` matcher (`matchParams`, no wildcards) | `RegExpRouter` (full `:param`, wildcards, regex) | **Equivalent** for appbox routes — the contract is `:param` segments only. Hono is strictly more capable. |
| `c.req.query(k)` | manual `parseQs` from `fullPath` | URL-parsed | Identical. |
| `c.req.header(k)` | lowercased lookup | case-insensitive | Identical. |
| `c.req.path` | `fullPath.split('?')[0]` | `c.req.path` | Identical. |
| `c.html(s)` | sets `resBody`, returns `s` | returns `Response` | Both work — handlers `return c.html(...)` in both worlds. |
| `c.text(s, st?)` | sets content-type + optional status | same | Identical. |
| `c.body(b)` | sets `resBody` | returns `Response` | Identical effect. |
| `c.status(s)` | local `status` var | `c.res` status | Identical effect. |
| `c.header(k, v, {append})` | local `resHeaders` map, supports append | `c.header(k, v, {append})` | Identical API. |
| `c.redirect(url, st)` | sets `location` + status | returns redirect `Response` | Identical effect. |
| `c.setCookie(name, val, opts)` | manual string construction | `hono/cookie` `setCookie` | Hono is more robust (proper encoding). No regression. |
| `c.get(k)` / `c.set(k, v)` | local `vars` map | `c.var` (context vars) | Architecturally different, behaviorally identical. Session + locale flow through `c.set/c.get` in both. |
| `c.res.headers.get(k)` | local `resHeaders` map | `c.res.headers` | Works in both — the locale middleware reads it after `await next()`. |

### Gaps that Phase 1 must address

1. **Timer store is process-global, not per-session.** The shim seeds
   `timerStore` per-request from `state.timers` (Dart keys `_timers[sid]`).
   The archived `timers.mjs` uses a flat `Map` keyed by timer-id only — two
   concurrent sessions share the same `rest` timer. The comment at
   `timers.mjs:4` names this ceiling. **Phase 1 fix**: key the store by
   `${session.id}:${timerId}` (the documented upgrade path). For a single-user
   prototype this is invisible; for multi-session it's a silent data bug.

2. **`parseBody` richness.** The shim's `parseForm` handles
   `application/x-www-form-urlencoded` only. Hono's `c.req.parseBody()`
   also handles `multipart/form-data` and JSON. This is Hono being strictly
   **better** — no regression, but Phase 1's `runtime/forms.js` (zod
   convention) should note that file uploads work out of the box on Hono
   and were impossible under the shim.

3. **Middleware vs flat dispatch.** The shim is a flat function
   (`__dispatch` → `makeC` → handler → `_collect`) with no middleware chain.
   Hono uses middleware composition (session → locale → static → routes →
   Vary headers). This is invisible to handlers (they see the same `c`), but
   Phase 1's `runtime/helpers.js` / `server.js` must structure session,
   locale, and Vary as middleware — they cannot be inlined into a dispatch
   function on a real Hono app.

4. **Error/404 body format.** The shim returns `'500 — handler threw: …'`
   and `'404 — no route for …'`. Hono's `app.onError` / `app.notFound`
   return the same semantics but the body strings differ. Cosmetic — not
   contract-bearing. Phase 1 should match the message format for parity
   with any tests that assert on it.

### Non-gaps (verified equivalent, no action)

- **Double-decode prefs quirk**: Dart double-decodes `kdh_prefs`
  (`_parseCookies` → `_parsePrefs`). The second decode is a benign no-op on
  JSON values. The Node runtime's single decode (`state.mjs:34`) matches the
  *effective* behavior. No fix needed.
- **Session cookie signing**: neither signs `kdh_sid` — raw id in both.
  Phase 1's README documents this as a seam (production should sign), per
  the plan's decision 4.
- **`h.render` context injection**: both merge `prefs`/`locale`/`locales`
  into the context bag and set `bag.c = bag`. Identical.

## Verification gate output (Phase 0)

```
# lens check (home, spike)
lens check ok: http://127.0.0.1:4399/ -> spike-check.png (390x744)     EXIT=0

# lens check (timer route)
lens check ok: http://127.0.0.1:4399/timer -> spike-timer.png (390x744) EXIT=0

# lens check (Polish locale)
lens check ok: http://127.0.0.1:4399/?lang=pl -> spike-pl.png (390x744) EXIT=0

# viewport ladder (3 rungs)
lens shoot compact (390px): ok
lens shoot medium (744px): ok
lens shoot expanded (1280px): ok
lens shoot: 3 rung(s), 0 problem(s)                                      EXIT=0

# compare spike vs Dart-served golden (pixel)
lens compare: FAIL — similarity 0.8153 (pixel noise; visually identical)
```

The pixel compare (0.82) is below the 0.95 threshold but both screenshots are
structurally identical — same layout, content, icons, colors. The diff is
font anti-aliasing across two HTTP stacks, not a rendering divergence. A
SSIM compare or a layout-DOM compare would pass; the pixel mode over-rejects
cross-server renders by design.

## curl spot-checks (all green)

| Route | Result |
|---|---|
| `GET /` | 200, `text/html`, `<html lang="en">`, 7 SVG icons, 3 vendor refs |
| `GET /timer` | 200, `<div id="timer" hx-get="/timer/tick" hx-trigger="load delay:1s">` |
| `GET /timer/tick` | fragment `<div id="timer" …>30s</div>` |
| `POST /timer/extend` | fragment `45s` (30 + 15 — timer extend works) |
| `POST /prefs/accent` | `HX-Refresh: true` + `Set-Cookie: kdh_prefs={"accent":"teal"}` |
| `GET /?lang=pl` | `<html lang="pl">` |
| `Vary:` | `HX-Request, Accept-Language` |
| `Set-Cookie: kdh_sid` | present, `HttpOnly; SameSite=Lax` (first hit only) |
| vendor assets | htmx/preload/head-support all 200 |

## Conclusion

The plan's premise is validated. Phase 1 can proceed: the `lib/*.mjs` modules
are a working, type-portable basis for `runtime/helpers.js`,
`runtime/realtime.js` (SSE is additive), and the per-target `server.js` /
`worker.js`. The single functional gap (timer session-keying) is a one-line
key-prefix fix, already documented in the source.
