# 09 — Serving prototypes without a Node install

**Goal.** app_box serves the htmx prototype with **~1 MB** of added weight and
**zero prerequisites** for the buyer.

**Blocks:** 12, 14. **Depends on:** 08.

## The decision, and the evidence

The prototype's `_viewmodel.js` files **are** the server logic, so dropping JS
means rewriting all 97 ui files — the from-scratch work we are avoiding.

Bundling a JS runtime was measured and rejected: **no JS runtime binary gets
under ~90 MB.** (Bun smallest and fastest — ~18 MB idle, ~52k req/s; Deno most
self-contained; Node SEA most awkward.)

**Chosen: Dart `HttpServer` + `flutter_js` running the existing viewmodels
unchanged.** `flutter_js` uses **JavaScriptCore on Apple platforms — a system
framework, zero added bytes** — and QuickJS elsewhere at roughly **1 MB**
overhead. Only `server.js` and `harness.js` routing are replaced; the
viewmodels, services, models and 37 surfaces are untouched.

## Steps

- [x] **9.1** Add `flutter_js` to `app/`. Confirm which engine binds on macOS
      (JSC vs QuickJS) and record it — it changes the size claim, not the design.
      **Bound: JavaScriptCore** (a system framework on macOS — zero added bytes;
      confirmed via the flutter_js macOS podspec, which has no JS-engine
      dependency, and `FlutterJsPlugin.swift` is a stub; the Dart FFI layer calls
      JavaScriptCore.framework directly). QuickJS is used only off-Apple (~1 MB).
**Scope note.** "No Node" constrains **the buyer's machine only**. The designer
(plan 01) legitimately requires Node — Hono, nunjucks and Playwright, ~22 MB of
dev dependencies — because that is where render and console checks run. Do not
propagate this plan's constraint upstream to the designer; doing so would
disable the gate that catches a surface whose fonts 404.

- [x] **9.2** Implement the HTTP layer in Dart against the routing contract in
      the designer's `runtime/lib/router.mjs` (plan 01 step 1.11) — **not**
      against an ad-hoc route table. Design-time and shipped runtimes agree by
      construction. `GET` returns rendered fragments, `POST` mutates. Bind to
      `127.0.0.1` on an **OS-assigned port** (`port: 0` in config) — never a
      fixed port (R3).
- [x] **9.3** **Pre-bundle the viewmodels at freeze time.** The viewmodels use
      ES modules; embedded engines resolve modules poorly. Bundle each entry to
      a single IIFE as a build step. This is a build step, not a rewrite —
      do not restructure the viewmodels to suit the engine.
- [x] **9.4** Expose fixture reads as a host function from Dart into the engine,
      replacing Node's `fs`. The viewmodels' `readFixture` contract stays
      identical.
- [x] **9.5** Serve `surfaces/`, `assets/` and the design-system CSS from the
      Dart server, with correct MIME types. Asset paths are **relative to the
      surfaces directory** — a prefix bug here previously 404'd every font and
      video while three verification layers reported success.
- [ ] **9.6** Emit a **heartbeat** on the paired channel while serving. Plan 12's
      FAB depends on channel state, never on whether a WebView painted.
      **Env-blocked:** the channel is built in plan 12 (a dependency of this
      plan), which is not yet implemented. The embedded server is channel-agnostic
      today (it serves over loopback HTTP); wiring the heartbeat waits for plan 12.
- [x] **9.7** Implement stop-server cleanly: release the port, kill the engine
      isolate, and report stopped over the channel.
- [x] **9.8** Keep a **Node fallback path** behind a config flag for local
      development, so a developer with Node can run the producer natively and
      compare output byte-for-byte against the embedded engine.

## Done-when

1. The reference producer's 37 surfaces render **identically** under the
   embedded engine and under Node — compare rendered HTML byte-for-byte.
2. Interactive routes work: a `POST` mutation updates a fragment.
3. **Every asset resolves.** Assert by resolving each rewritten URL to a real
   file — not by grepping for leftover strings. Checking only for un-rewritten
   URLs is vacuous against the failure that actually happened: every URL was
   dutifully rewritten to a path that did not exist.
4. Added bundle size is measured and recorded. If it exceeds ~5 MB, stop and
   report — the premise of this plan was leanness.
5. Killing the server surfaces as **dead** on the channel within one heartbeat
   interval.
6. No Node on `PATH` → the app still serves prototypes.
