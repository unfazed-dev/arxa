# Eject web productionization — implementation plan (v2)

Status: approved strategy + approved amendments, awaiting implementation
(external agents).
Worktree: `.kimi-code/worktrees/arxa-designer-feature` (branch
`arxa-designer-feature`).
Date: 2026-08-06. v2 amends v1 with six verified research reports (htmx 4
extension source, signals runtimes, SSE on edge, 2026 frontier scan,
resumability landscape, resumability mechanics).

## Strategy (decided, do not re-litigate)

`arxa design eject` evolves from "copy the artifact onto the Dart design
server" into a **re-platforming**: it emits a standalone Hono app that runs
natively on a JavaScript runtime and deploys to **Cloudflare Workers/Pages**
and **Vercel**. The artifact itself — format, registry, lint contract — is
untouched and stays the Flutter-mirrorable SSOT. One artifact, two exits.

Decisions locked in the grill session:

1. Scope = harden the eject path only. Flutter remains the primary target.
2. Bar = ejected app is **ownable by a dev team**: type-checked, tested,
   one-command deploy, human-editable.
3. Handoff = **one-way eject**. No round-trip, no regeneration zones.
4. Platform = real JS runtime (Workers first, Vercel second, Node for local).
   The Dart design server + headless-Chrome worker stays **design-time only**.
5. Kits = existing MVVM facade seam + **official npm SDKs** (supabase-js,
   stripe, mapbox-gl) + emitted env wiring.
6. Engine = **htmx 4**. Correction from source-verified research: in v4,
   **morphing (idiomorph) is core; SSE is the bundled, rewritten `hx-sse`
   extension** (`hx-sse:connect`, fetch+ReadableStream, auto-reconnect with
   `Last-Event-ID`) — not core. htmx 2.x stays vendored for existing
   artifacts until they opt in.
7. Islands = named-islands registry unchanged as the *contract*; machinery
   upgraded at eject: a first-party **`hx-island` htmx-4 extension loader**,
   esbuild per-island ESM chunks + import map + SRI, **island state
   serialized into HTML so islands resume** (see "Resumable islands"),
   signals micro-runtime for glue islands.
8. Typing = **JavaScript + JSDoc + `tsc --checkJs`** as the gate;
   route-manifest codegen emits `.d.ts` typed route helpers + zod-typed form
   actions. Template→TSX conversion deferred to an opt-in `--tsx` eject mode
   (out of scope for this plan).
9. Governance = lint + coverage gates unchanged; every web feature must ship
   without touching the artifact contract.

### Positioning (v2 addition — the competitive frame)

The ejected product does not try to be a better React. It wins the segment
where SPA frameworks are overkill — content-driven, CRUD-heavy,
bounded-interactivity business apps:

- **Payload/TTI**: htmx (~14 kB) + a ~150-line loader + islands that load on
  condition and *resume* — no framework boot, no hydration. Precedent at
  scale: Google's Wiz (Search/Photos/YouTube) and Marko (eBay).
- **Stability**: no framework upgrade treadmill in domain code (htmx 2
  supported in perpetuity; v4 skipped a breaking 3.0 by design).
- **Security surface**: no serialized client-component protocol —
  React2Shell (CVE-2025-55182, pre-auth RCE in RSC deserialization) is a
  vulnerability class HTML-over-the-wire does not have.
- **AI-pipeline fit**: server-centric hypermedia is the architecture LLM
  agents generate and repair most reliably — and no competitor's artifact
  also compiles to Flutter.

Explicit non-goals: Figma-class editors, offline-first, CRDT collaboration,
dense drag-everything dashboards — SPA territory, past the island ceiling.
Against SvelteKit specifically: their edge is ecosystem + total typing
coverage (Remote Functions shipped Aug 2025, still experimental/buggy); our
edge is no-build-step domain code, resumable islands vs hydration, the
unowned convention/codegen layer, and the Flutter exit. The "htmx at scale"
published-evidence gap persists since 2022 — **publish our own ejected-app
numbers** as cheap differentiation.

### Resumable islands (v2 addition — the unclaimed niche)

Research verdict: resumability's benefits decompose, and the pieces worth
adopting are cheap. Verified mechanics:

- **Delegated lazy handlers** (Qwikloader design, source-read): one
  capture-phase listener per event type on `document`, bubble-path attribute
  walk, `import()` + cache. ~100–150 lines. **No event replay queue** —
  capture-phase listeners at the document root cannot miss events; replay
  exists only for frameworks whose listeners attach after content
  (jsaction's constraint; jsaction itself is archived into Angular
  internals — do not adopt).
- **State-in-HTML resume**: per-island `<script type="application/json">`
  with `<`-escaping as the floor; `devalue` (`uneval`, 5.7 kB, XSS-safe)
  only when Date/Map/cycles actually appear in island state. Handlers
  receive parsed state instead of re-deriving it (~30 lines total). Qwik's
  full graph serializer (cycles, DOM refs, closures-as-QRLs) exists because
  Qwik serializes functions — we never do; skip it.
- **The niche is empty**: no hypermedia player ships islands that resume
  from server-serialized state — not is-land, Enhance, datastar
  (`data-persist` is localStorage, not server state), or Angular. "Resumable
  islands" is a claim only this stack can make.

## Current machinery (verified facts)

- Eject: `designEject()` at `arxa/lib/design_tools.dart:1208-1303` — today
  it copies the tree, narrows `runtime/vendor/` by scanning HTML for
  `/assets/vendor/*` refs (hard-fails if htmx is not referenced), writes a
  narrowed manifest + README. No package.json, no JS runtime, no smoke test.
- Design server: `arxa/lib/design_server.dart` owns HTTP, sessions
  (`kdh_sid` cookie, in-memory `_sessions`), locale (`?lang=` > prefs cookie >
  Accept-Language), timers, hot reload, static files. Per request it calls
  `_worker.dispatch(method, path, headers, body, {locale, session, timers})`.
- JS execution: `arxa/lib/design_server/worker_assets/worker_shim.js`
  (267 lines) — a hand-ported Hono-equivalent shim running in headless
  Chrome. `__boot` imports `<origin>/app.routes.js`; per request it builds a
  fake Hono `c` (`req.query/param/header/parseBody`, `c.html/text/redirect/
  setCookie/header/status`, `c.get/set`) and a helper object `h`
  (`render, form, session, prefs, locale, t, setPrefs, timers, noContent,
  stopPolling, refresh, location`).
- Templates: **Nunjucks** (`worker_assets/nunjucks.min.js`, synchronous
  prefetched loader), autoescape on, `'file.html#macro'` fragment renders.
  Globals: `t` (ICU-plural-subset over `__arb`), `icon` (lucide inliner).
- Fixtures: `services/repositories/fixture_reader.js` uses `node:fs`
  `readFileSync(new URL(rel, import.meta.url))` — the **only** Node builtin
  any artifact touches. Remapped to `fs_shim.js` in the worker via import
  map.
- Route table: `app.routes.js` exports `[method, path, handler][]` plus
  required `shellRoots`. Handlers are `(c, h) => Response`.
- Vendor manifest: `runtime/vendor/manifest.json` rows
  `{file, package, version, integrity}` (sha384). `vendor-fetch` at
  `design_tools.dart:946` re-fetches and rewrites; `_packages` allowlist at
  lines 830–869 (includes htmx 2.0.10, idiomorph-ext, sse extension, etc.).
  First-party islands (`canvas.js`, `drag.js`, `inspect.js`, …) are
  unpinned.
- Kit system: `config/kit-registry.json` (Flutter-package-oriented:
  `{dir, package, capabilities, providers, provides}`) and
  `config/credentials.catalog.json` (rows `{module, provider, key, required,
  kind: secret|publishable, url}`). **No npm/env mapping exists today.**
- Gates reusable against any URL: `arxa design lint`, `selftest`,
  `check-wiring`, `check-ladder`, `arxa lens check/shoot/compare`.
- ADR-0008 (`docs/adr/0008-productionize-eject-harden.md` under the skill)
  deliberately excludes auth/DB/CI from eject — Phase 5 amends it (kit
  facades bring Supabase/Stripe in through the Repository seam).

Reference artifact for all phases: `.kimi-code/skills/arxa-designer/
examples/hello-hda/` (small, has l10n, timers, fragments, facade seam).

## Phase 0 — De-risking spike: artifact runs on real Hono

Goal: prove the core thesis before building any eject machinery — the
hello-hda artifact, unchanged, served by real Hono on Node.

- Write a throwaway `server.js` (lives in `tool/` or a scratch dir, NOT in
  the eject path yet) that:
  - imports the artifact's `app.routes.js` directly (it is already
    Hono-shaped; the shim only ever mimicked Hono's `c`);
  - provides the `h` helpers as a real ESM module ported from
    `worker_shim.js`: `render` via npm `nunjucks` with a FileSystemLoader
    (keep the `'file.html#macro'` fragment convention), `t` (port the
    ICU-subset from `worker_shim.js:17-73`), `icon` (read lucide SVGs from
    disk), `session`/`prefs` (in-memory Map + signed cookie), `locale`,
    `timers` (port the deadline-based semantics), `form`, `noContent`,
    `stopPolling`, `refresh`, `location`;
  - serves `/assets/*` statically; `fixture_reader.js` works unchanged
    (real `node:fs`).
- Success criteria: `arxa lens check http://localhost:<port>/` clean,
  `arxa lens shoot` at the active ladder visually matching the Dart-served
  artifact (`arxa lens compare` against goldens), locale switch + a timer
  fragment + a POST route all working.
- Deliverable: a gap list — every place the real Hono `c` diverges from the
  shim's fake `c`. This list sizes Phase 1.

## Phase 1 — Eject emits the JS runtime scaffold

Extend `designEject()` (`arxa/lib/design_tools.dart:1208`) with
`--target=cloudflare|vercel|node` (default `node`; `--target` repeatable is
fine if cheap, otherwise one target per eject).

The ejected tree gains:

- `package.json` — `hono`, `nunjucks`, `zod`, plus per-target:
  `@hono/node-server` (node), `wrangler` (cloudflare), `vercel` (vercel).
  Type-check tooling: `typescript` (for `tsc --checkJs` only — no compile
  step).
- `server.js` (node) / `worker.js` (cloudflare) — productionized version of
  the Phase 0 spike: real Hono app, static assets (`@hono/node-server/serve-
  static` / Workers `[assets]` binding), session middleware (cookie-signed;
  document the KV/Durable-Object swap point for multi-instance, do not build
  it), locale resolution ported from `_resolveLocale`.
- `runtime/helpers.js` — the ported `h` module (single module, JSDoc-typed).
- `runtime/realtime.js` — the SSE bus (v2 addition; design verified against
  htmx 4 beta6 `hx-sse` source and platform limits):
  - Endpoint convention `GET /__events?channel=<name>`; unnamed SSE messages
    swap through the element's normal `hx-target`/`hx-swap` (morph
    composes), named events dispatch DOM events — both are hx-sse v4 core
    behaviors.
  - Helper shaped like datastar's `ServerSentEventGenerator`: one thin typed
    object per request (`sse.patch(html)`, `sse.event(name, html)`), not a
    framework.
  - **Event `id:` + a short replay buffer from day one** — reconnects are
    guaranteed (deploys, evictions, Vercel's 300s/800s duration wall), and
    hx-sse resends `Last-Event-ID` automatically.
  - In-memory bus is the **Node default only**. On Workers there is no
    isolate affinity — events published on isolate A never reach clients on
    B, silently. Ship the convention; document the Durable-Object-per-
    channel adapter as the scale seam (note: DO hibernation is
    WebSocket-only; SSE connections keep a DO billed — acceptable at the
    documented seam, part of why in-memory is the default elsewhere).
- Fixtures: on `node`, keep `node:fs` reads. On `cloudflare`, eject
  generates `runtime/fixtures.js` — one ESM module re-exporting every
  fixture JSON (Workers have no fs); `fixture_reader.js` is emitted in a
  target-specific variant. Document this as the one target-dependent file.
- `wrangler.toml` / `vercel.json` — routes, assets, compatibility date, env
  var placeholders sourced from `config/credentials.catalog.json` names.
- `README.md` — replaces `_ejectReadme`: run/dev/deploy commands, the
  **one-way eject statement** ("this tree is yours; arxa will never
  re-import it"), the hardening checklist from
  `built-in-skills/productionize.md` updated for the JS runtime.

Verification: eject hello-hda for all three targets; `node server.js` +
`arxa lens check` clean locally; `wrangler dev` smoke on cloudflare
target; `arxa design lint` and `selftest` still clean on the artifact
(proves the artifact contract is untouched).

## Phase 2 — htmx 4

- `vendor-fetch` allowlist (`design_tools.dart:830-869`): add htmx 4.x (pin
  the newest 4.x beta/stable at implementation time) **and the bundled
  `hx-sse` extension** (`dist/ext/hx-sse.min.js` — SSE is an extension in
  v4, source-verified). **Remove** the `idiomorph-ext` and old `sse`
  extension rows for htmx-4 artifacts (morph is core; old sse is
  superseded), keep them for htmx-2 artifacts.
- `runtime/vendor/manifest.json` + `SRI.md`: new rows via the existing
  `vendor-fetch` machinery (jsdelivr, sha384 via `sri()`).
- Manifest records the htmx major version per artifact; eject warns when
  ejecting a 2.x artifact ("production eject expects htmx 4").
- Lint rules (`design_tools.dart:60-71`): no change to the zero-custom-JS
  contract. Verify the htmx-4 event rename (`htmx:<phase>:<system>`) and
  `:inherited` modifier against any first-party glue islands that listen
  for htmx events — update those islands, not the linter.
- Morph-init risk: **resolved**. bigskysoftware/htmx#3606 (morph swaps not
  initializing htmx attributes on new elements) was closed 2026-01-20;
  beta6 (2026-07-23) processes new content after every swap style including
  morph. Verify the pinned version is ≥ that fix.

Verification: hello-hda + `designs/arxa-studio` run on vendored htmx 4 in
the Dart design server with `arxa lens check` clean at every ladder
width; ejected app behaves identically.

## Phase 3 — Islands machinery (at eject) — rewritten in v2

The named-islands registry (`runtime/vendor/` allowlist + first-party
islands) stays the linted contract. Eject adds the production machinery.
Everything below is eject-only; the design-time server keeps eager loading.

### 3a. `runtime/islands.js` — the first-party loader (replaces is-land)

A single ~150-line file, registered as an htmx 4 extension (API verified
against beta6 source):

- `htmx.registerExtension('islands', …)`; discovery hook
  `htmx_after_process(root)` scans `root.querySelectorAll('[hx-island]')`
  (the same pattern the bundled `hx-sse` uses for `hx-sse:connect`); track
  initialized islands in a WeakSet — the hook fires per process root, so
  double-init is on us to prevent.
- Islands declare loading conditions inline:
  `<div hx-island="timer" hx-island-when="visible|idle|interaction|load">`
  (`visible` = our IntersectionObserver, `idle` = requestIdleCallback,
  `interaction` = first pointer/key event, `load` = immediate).
- **Delegated lazy handlers** (Qwikloader design): one capture-phase
  listener per event type on `document`; on event, walk the bubble path for
  `data-on:<event>="./chunk.js#symbol"` attributes, `import()` + cache,
  invoke. No replay queue — capture-phase listeners at the root cannot miss
  events.
- Teardown: `htmx:before:cleanup` disposes islands on removed subtrees
  (pairs with 3c's MutationObserver).
- Unknown `hx-*` attributes are ignored gracefully by htmx — no lint or
  runtime conflicts. `htmx.process(root)` is retained in v4 for manually
  initializing dynamically inserted island markup.
- Risk carried: these hooks are source-verified on beta6 but not
  contract-stable while 4.0 is beta — isolate all hook usage in this one
  file so beta churn has exactly one call site to fix.

### 3b. Per-island bundles + state resume

- esbuild (single Go binary, spawn from Dart like `openssl` in `sri()`)
  compiles each referenced island into an ESM chunk under
  `assets/islands/`, sha384 SRI per chunk, import map emitted into the
  ejected `ui/common/base.html`.
- **State-in-HTML resume**: each island's initial state renders as
  `<script type="application/json" data-island-state="name">` (lint-legal
  today) with `<`-escaping; the island's init receives parsed state instead
  of re-deriving/re-fetching. Floor: `JSON.stringify` + escaping. Ceiling:
  `devalue` `uneval` (XSS-safe, handles Date/Map) — only when those types
  actually appear. Retrofit `timer`/`drag`/`canvas` islands.
- This is the "resumable islands" claim: islands resume from
  server-serialized state; nobody else in the hypermedia space ships it.

### 3c. `runtime/island-kit.js` — defineIsland + signals (datastar counter)

- Vendor **alien-signals** (1.94 kB, actively maintained; its algorithm is
  ported into Vue core 3.6; `effectScope` gives one `stopScope()` per
  island). Fallback: `@preact/signals-core` (1.95 kB, `.value` API). Add to
  the `_packages` allowlist + manifest.
- ~120-line declarative binding layer on top: `data-text`, `data-show`,
  `data-attr:*`, `data-on:*` scoped inside the island; direct-DOM in-place
  binding (the sprae/petite-vue/datastar pattern — resumes server HTML,
  never re-renders; template libs like arrow-js/vanjs are disqualified).
  Effects run once at init writing the same values the server rendered —
  idempotent, no flash.
- **Teardown (the one real footgun)**: signals never auto-dispose. Copy
  datastar's `engine.ts` pattern — one MutationObserver on the root +
  per-island dispose set (~20 lines). Idiomorph preserves matched element
  identity, so effects survive morphs and die on removal.
- Total ≈ 2.5–3 kB gzip on top of htmx, vs datastar's ~11.8 kB for the
  equivalent capability. Post-eject, dev teams register their own islands
  with one `defineIsland(name, fn)` call — they own the registry then.
- Designer-side: grow the first-party registry with parametrized
  micro-islands covering the inline-reactivity 80% (toggle, tabs, counter,
  form-state, derived-text). Named islands, so the lint contract holds.

Verification: ejected hello-hda loads zero island JS until an island's
condition fires (assert via `arxa lens net`); SRI mismatch on a tampered
chunk fails closed; island state survives a morph swap (effect stays
subscribed, no re-init flash); `arxa lens check` clean.

## Phase 4 — Typing + the codegen moat

- Ejected `tsconfig.json`: `checkJs: true, allowJs: true, noEmit: true,
  strict: true`. `npm run typecheck` = `tsc -p .`.
- JSDoc sweep: every emitted runtime module (`runtime/helpers.js`,
  `runtime/realtime.js`, `runtime/island-kit.js`, `server.js`/`worker.js`,
  kit facades) ships fully annotated (`@param`, `@returns`, `@typedef` for
  `AppSession`, `Helpers`, `RouteContext`, `IslandContext`). The artifact's
  own `app.routes.js` / viewmodels are ejected verbatim — annotate them
  only where eject already transforms them.
- **Route-manifest codegen** (the moat): eject parses `app.routes.js`'s
  route table (it is a static array — parse, don't eval) and emits
  `runtime/routes.d.ts` + `runtime/routes.js`: typed helpers
  (`routes.timer.tick()` → `"/timer/tick"` with param checking), so
  viewmodels write `h.render(..., { tickUrl: routes.timer.tick() })`
  instead of string literals. Nobody ships this for hypermedia stacks; it
  is the SvelteKit-`resolveRoute` parity item. Position it against
  SvelteKit Remote Functions (typed RPC, experimental): our moat is the
  *convention layer*, not typed calls alone.
- **Form actions**: convention + helpers for zod-validated POST handlers —
  parse with zod, on failure return 422 + re-rendered form partial with
  errors and prior values. Ship as `runtime/forms.js` with JSDoc types.
  Benchmark the UX against **Unpoly's form-validation conventions** (the
  Carson-endorsed reference); one worked example in the ejected README.
  Generating schemas *from* templates is out of scope.

Verification: `npm run typecheck` clean on the ejected hello-hda; renaming
a route in `app.routes.js` breaks typecheck (the falsifiability test);
`arxa design selftest --negative` still green on the artifact.

## Phase 5 — Kits for web

Extend the kit SSOTs additively (Flutter fields untouched):

- `config/kit-registry.json`: each kit gains an optional `web` object:
  `{npm: "package@version", facade: "services/facades/<kit>_facade.js",
  islands: [...], envFrom: [<credentials.catalog keys>]}`. Start with three
  reference kits: **supabase** (`@supabase/supabase-js`), **stripe**
  (`stripe` — fetch-based, works on Workers), **maps** (mapbox-gl /
  leaflet already vendored — decide per the kit's existing provider).
- `config/credentials.catalog.json`: reuse existing key names
  (`STRIPE_SECRET_KEY`, …) — eject maps `kind: secret` → server env var,
  `kind: publishable` → emitted client config. `.env.example` +
  `wrangler.toml [vars]`/secret comments generated from these rows.
- Facade emission: eject copies a maintained facade template per kit
  (living under the skill at `runtime/kit-facades/<kit>.js`, JSDoc-typed,
  behind the same facade interface the fixture repositories implement) into
  the ejected tree. Design-time keeps fixture facades — the designer never
  sees real credentials.
- **Realtime bridges** (v2 addition, gotchas verified): Supabase → prefer
  **Database Webhooks (HTTP POST) into the Worker**, not a Supabase
  websocket client inside a Durable Object (outgoing websockets cannot
  hibernate — pinned, billed DO). Stripe → on Workers use
  `constructEventAsync` (async SubtleCrypto) on the raw body, respond 200
  immediately, broadcast via `ctx.waitUntil`, and **dedupe on event ID**
  (Stripe retries on slow responses → duplicate events). Both republish
  onto the `runtime/realtime.js` bus.
- Amend ADR-0008: auth/DB are no longer "not generated" when a kit provides
  them — they arrive through the kit facade seam. CI pipelines remain out
  of scope.

Verification: eject hello-hda with `"kits": ["supabase"]` declared;
typecheck clean; facade reads `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`
from env; missing env fails at boot with a named error, not at first
request.

## Phase 6 — Deploy + acceptance

- `npm run deploy` per target (`wrangler deploy` / `vercel deploy`); README
  walkthrough from eject to a live URL in <10 minutes.
- Acceptance gate for the whole program (run in CI on this branch):
  1. `arxa design lint` + `selftest` clean on hello-hda and arxa-studio
     (artifact contract untouched);
  2. eject both artifacts for `cloudflare` and `node`;
  3. `npm run typecheck` clean in each ejected tree;
  4. `arxa lens check` + ladder `shoot` against the locally served
     ejected app, `compare` against the Dart-served goldens;
  5. a deployed Workers URL passes `arxa lens check` (manual step,
     recorded in evidence);
  6. (v2) capture and publish the payload/TTI numbers of the ejected demo
     vs the same app on a mainstream SPA stack — the "htmx at scale"
     evidence gap is ours to fill.

## Explicitly out of scope

- Template→TSX conversion (`--tsx` mode) — deferred until the JSDoc rung
  proves out; needs its own plan (Nunjucks→JSX fidelity is the risk).
- Round-trip / regeneration zones — rejected by decision 3.
- datastar as the engine — rejected by decision 6 (its good ideas are
  absorbed: signals, morph, SSE conventions, engine teardown pattern).
- Full resumability machinery — QRL capture arrays, graph serialization,
  event replay queues, service-worker prefetch: ceremony at our island
  sizes (mechanics research verdict). We adopt the contract pattern, not a
  resumable runtime.
- Auth/DB/CI generation beyond kit facades (ADR-0008, amended).
- Multi-instance session store (KV/Redis) and DO-backed SSE bus —
  documented seams only.
- Changing the artifact format, registry schema, or lint contract.

## Risks (ranked)

1. **Timer semantics** — the Dart server owns deadline timers; porting them
   to a JS runtime changes polling/fragment behavior. Phase 0 must surface
   this early.
2. **htmx 4 beta drift** — extension hooks (`registerExtension`,
   `htmx_after_process`) are source-verified on beta6 but not
   contract-stable; all hook usage is isolated in `runtime/islands.js` (one
   call site to fix). Re-vendoring betas is cheap via the manifest/SRI
   machinery but is a recurring chore until 4.0 stable.
3. **Nunjucks loader parity** — the worker's synchronous prefetched loader
   vs npm nunjucks' async FileSystemLoader; fragment (`#macro`) rendering
   must behave identically or every partial swap breaks.
4. **Fixture strategy on Workers** — bundling fixtures as ESM is fine for
   design-scale data; a real app swaps repositories for kit facades (the
   intended path), but the ejected demo must still boot.
5. **Workers isolate affinity for SSE** — in-memory bus is silently broken
   across isolates; mitigated by making it the Node default and documenting
   the DO seam, but an ejected Workers app that grows realtime features
   will hit it. The README must say so plainly.
