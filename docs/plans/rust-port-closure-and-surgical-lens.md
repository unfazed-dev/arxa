# Rust-port closure + surgical lens — grill decisions 2026-08-21

**Status:** decisions locked 2026-08-21 (grill session, all answers confirmed).
Evidence: three research reports (FRB Aug-2026 state, Rust codegen/CDP
practices, repo ground-truth) + two follow-ups (Rust app-framework traction,
multi-target scaffolder feasibility) + one (feedback widget / a11y toolbar /
Supabase patterns). Advisor consult skipped — no API key in env, recorded
per convention, proceeded on primary sources.

## A. The Rust question — CLOSED

1. **No Rust port of the tooling.** The 2026-07-31 verdict in
   [appbox-dart-only-tooling.md](appbox-dart-only-tooling.md) stands
   (addendum appended there). Every recorded pain from the energize /
   normal-is-boring runs is language-independent; emitter language is
   orthogonal to emission targets (OpenAPI Generator precedent: Java
   emitting 50+ languages); FRB is a Dart↔Rust runtime bridge inside
   Flutter apps — irrelevant to a build-time CLI and to pure-Rust targets.
   Rust UI is not client-ready (94.4% of Rust GUI libs not
   production-ready, 2025 survey; a11y gaps; no consumer mobile flagship).
   No revisit trigger recorded — Flutter covers the platform ground.
   FRB stays back-pocket for app-side hybrid cores only.

2. **The three recorded causes get fixed in Dart, now** (W1 below):
   fresh-Chrome-per-invocation, page-settle variance, gate coverage holes.

## B. Surgical lens + designer↔lens tandem

3. **One capture, drill-down compare, uniform across media.** Every
   capture produces an *evidence bundle*: pixels + region tree + geometry
   + motion frames, whatever the source (live site, design artifact,
   static image, video clip). Region tree from DOM `inspectAttrs` when a
   DOM exists; from the existing skeleton/OCR analyzers when it doesn't.
   Compare runs coarse-to-fine on the SAME capture — whole view first,
   then down the region tree by cropping — zero extra Chrome passes.
   Verdicts are structured: divergent node + geometry/computed-style
   delta, never just a pixel score.

4. **The capture manifest is the tandem contract.** Designer emits, per
   surface: states × viewports × regions, each state carrying the
   interaction script that reaches it (promotes the `lens_click_burst`
   pattern to data). One lens verb runs the whole manifest; verdicts are
   machine-readable for the designer's fix pass.

5. **Bounded auto-loop.** Verdict → designer fix → lens re-verify,
   up to 3 rounds per surface. Humans see survivors + the auto-fix trail.

## C. Codegen tie-ins

6. **Region identity in emitted code:** scaffolder stamps stable widget
   keys / Semantics mirroring the same vocabulary, so built Flutter apps
   expose the same region tree via the VM service and design-vs-built
   drill-down compares node-to-node.
7. **Golden snapshot corpus for emitters:** committed emitted-file
   snapshots per fixture registry; CI regenerates and fails on diff
   (locks the existing sorted-emit discipline into a gate).
8. **Lens evidence may feed generation:** measured geometry/spacing from
   the design artifact can inform emitted layout values.

## D. The abx- vocabulary

9. **One controlled vocabulary, three consumers.** A versioned
   `dictionary.json` in the designer runtime; every emitted class/id is
   `abx-*` and drawn from it. Capture-manifest region keys and scaffolder
   widget keys use the same terms — the "unified mapped context".
10. **Enforced as design-lint gates, not docs:** (a) every class/id is
    `abx-*` or on the vendored-library allowlist; (b) provenance scan —
    no class/id string appearing in the scanned reference corpus may
    appear in output (the normal-is-boring verbatim-copy incident).
11. **Trail-leaving growth:** the designer never invents a term silently;
    it proposes, the dictionary gains the term + one-line rationale, then
    the gate passes.

> **Amendment 2026-08-21 (same day, later session):** the semantic prefix
> is **`arxa-`**, not `abx-`, and the vocabulary is the **arxa
> dictionary** — superseded by the arxa rename in
> [arxa-harness-and-distribution.md](arxa-harness-and-distribution.md)
> (decision 11 there). Decisions 9–10 above read with `arxa-` wherever
> `abx-` appears. Changed before the dictionary or its gates were built
> (W4 pending), so no artifacts migrate.

## E. Tooling discipline

12. **Using-sessions never write into appbox.** Gate-enforced read-only
    `appboxd/` during client-project work (the `tool/tmp_*.dart` and
    `/tmp` py/mjs scripts pattern ends). Gap-filler: a first-class
    `appbox lens eval <url> <js>` verb against the warm session, output
    under the project's evidence dir. Recurring evals are promotion
    candidates, promoted to real verbs only in appbox-dev sessions.

> **Amendment 2026-08-21 — scope is the headline, not the example.** This
> decision's headline ("never write into appbox") and its mechanism clause
> ("read-only `appboxd/`") disagreed on scope. Ratified in favour of the
> headline, and implemented as an **allowlist** rather than a wider denylist:
> in a using-session the whole checkout is read-only except `docs/`,
> `designs/`, `logs/`, where findings are recorded. `appboxd/` was only ever
> the example that produced the `tool/tmp_*.dart` litter — a using-session
> editing `skills/`, `gates/` or `appbox-studio/` is the same defect.
> Enforced per-tool-call by `hooks/appbox-guard.js` (`WRITABLE`) across all
> three harnesses; rationale and the holes this closed are in
> [arxa-harness-and-distribution.md](arxa-harness-and-distribution.md).
> The `lens eval` gap-filler above is unaffected and still owed by W1.

## F. Client-facing islands

13. **Feedback dial (the appbox FAB):** first-party island (ADR-0009
    form) baked into every design artifact. Default on; operator-only
    toggle; clients cannot hide it (watermark role). Art-dial design:
    radial icon-button options, draggable, animated. Supabase Auth
    sign-in gate: design locked until sign-in; on auth the dial animates
    in, with sign-out. Comment, change-list, draw-over (overlay shade +
    canvas), history sidebar. Model: the pub.dev `feedback` package's
    navigate/draw mode toggle, ported to a vanilla-JS shadow-DOM island.
14. **Central Supabase:** one operator-owned project, `design_feedback`
    table, rows tagged {client, project, artifact-version, route,
    viewport}; `auth.uid()`-keyed RLS; realtime `postgres_changes` for
    the operator moderation view. Chat and per-user features ride the
    same auth later.
15. **Lock depth — server-verified on deploys:** the Cloudflare Worker
    serving deployed previews verifies the Supabase JWT before serving
    artifact HTML; the island only owns the sign-in UX. Local
    `appbox design serve` stays open.
16. **Built apps join later:** the pub.dev `feedback` package wired to
    the same pipeline — separate stage, not now.
17. **A11y toolbox:** a SEPARATE, decoupled island (coffee-tech
    "UserAccess"-style: contrast modes, text scaling, stop animations,
    reading rail, dyslexia font, hide images, cursor size…), built for
    clients who request it. The dial may host a demo entry so a client
    can experience it and confirm the request. Framed strictly as a UX
    preference layer — never compliance (FTC fined accessiBe $1M for
    that claim; EAA auditors reject overlays); artifacts must pass the
    real a11y gates regardless.

## G. Media + content (added 2026-08-21, same session)

18. **Real media, licensed:** the designer always sources images/video from
    the stock APIs, never scrapes or copies reference-site media.
    **Pexels is primary** for images AND video — its license permits baking
    downloaded files into delivered client artifacts; one prominent
    "Photos provided by Pexels" credit per artifact + per-photo
    photographer credit. **Unsplash is secondary** (when Pexels search
    falls short) — always hotlinked from the Unsplash CDN (never vendored),
    with the download-event ping per placement and UTM-tagged
    photographer + Unsplash credits, per the API guidelines. Neither
    provider's assets may feed anything resembling a stock-gallery
    feature; avoid identifiable-people shots in endorsement-like contexts.
19. **Asset ledger:** every placed asset is recorded — provider, asset id,
    photographer name + profile URL, page URL, (Unsplash)
    download_location — so credits render from data and compliance is
    auditable per artifact.
20. **Credentials:** `UNSPLASH_ACCESS_KEY`, `UNSPLASH_SECRET_KEY`,
    `PEXELS_API_KEY` are cataloged under `designer/media` in
    `config/credentials.catalog.json`; values live in the OS vault via
    `appbox credentials set` (done 2026-08-21). Never in a tracked file.
21. **Content pass + LLM fallback:** the project's copy is generated ONCE
    at intake/story-map time into a `content.json` artifact (headlines,
    body, CTAs, empty-states per surface, keyed by abx dictionary terms);
    the designer consumes it deterministically. If a slot has no entry,
    the designer may ask the LLM once and MUST write the result back into
    `content.json` — the next run is deterministic. No generic lorem-style
    text library (canned filler is the content twin of the
    semantics-copying defect).

## Workstreams (ordering)

- **W1 — lens core (unblocks everything):** warm Chrome session owned by
  the daemon (kills launch-per-invocation), settle protocol
  (`document.fonts.ready`, double-rAF, animation freeze, optional CDP
  virtual time for gate captures), `lens eval` verb, read-only gate on
  `appboxd/` in using-sessions. Delete the `tool/tmp_*.dart` probes once
  eval lands; promote `lens_click_burst` / `lens_footer_states` into
  verbs or manifest states.

> ### Amendment 2026-08-21 — W1 re-ordered on measured evidence
>
> Research (6 parallel agents, official docs + installed source) plus direct
> measurement against the current lens. **Reordering W1: settle protocol
> first, warm Chrome second.** The two items were listed as peers; they are
> not. One is provably broken and provably fixable, the other carries an
> undocumented risk to the tool's core purpose.
>
> **1. Two W1 items are already done.** The `appboxd/` read-only gate shipped
> as `hooks/appbox-guard.js` in H1 (wider than asked — whole checkout, allowlist
> of `docs/designs/logs`). The `tool/tmp_*.dart` probes are gone; they were
> never committed. Remaining probe: `lens_click_burst.dart` (untracked).
>
> **2. `lens eval` is nearly free.** `CdpSession.evaluate` already wraps
> `Runtime.evaluate` (`appboxd/lib/cdp.dart:625-644`). The `eval` verb exists
> but is bound only to the Flutter VM path (`lens_cli.dart:1020`). Wiring it to
> the web path is a CLI-surface change, not new capability.
>
> **3. The settle defect, measured — `verified`.** `navigateAndSettle`
> (`cdp.dart:607-623`) is a flat `Future.delayed(settleMs)`, default 1500ms.
> No fonts signal, no rAF, no network idle. Observed on this machine:
>
> | probe | result |
> |---|---|
> | static page × 5 captures, fixed settle | **1 distinct hash** — byte-identical |
> | animated page × 5, fixed settle | **1 distinct hash** — byte-identical |
> | animated page at 500/1500/2500/4000ms | **4 distinct hashes** |
> | **variable-load page × 5, fixed 1500ms settle** | **2 distinct hashes** |
>
> The mechanism is a fixed timer racing a variable page: animations are live
> and captured mid-flight, so a constant settle is phase-locked only while load
> time is constant. The last row varies load time alone (a busy-wait of
> 100–800ms before render, standing in for network/font/CPU jitter) and
> reproduces the nondeterminism. This is *not* randomness in Chrome — the first
> three rows prove the launch path itself is byte-stable.
>
> **4. Warm Chrome is the risky half — `unknown`, and no doc will settle it.**
> No official source (Chromium, CDP, Puppeteer, Playwright) documents whether a
> reused browser renders identically to a freshly-launched one. Font-shaping,
> GPU raster, and shader caches all warm up. Since the lens exists to compare
> pixels, this must be measured before the daemon owns a browser: capture N
> times in one warm browser and diff against N fresh-launch captures of the
> same page. Additional constraints the docs *do* name:
> - `--remote-debugging-pipe` cannot be attached to by a later, unrelated
>   process (FDs 3/4 belong to the spawning parent). A daemon+CLI split must
>   use `--remote-debugging-port`, or the daemon proxies.
> - Chrome ≥136 refuses remote debugging against the default profile, so the
>   daemon runs **one** `--user-data-dir` for its whole lifetime — one disk
>   cache, one visited-links table, shared across every capture.
> - `Target.createBrowserContext` isolates cookies/storage but **not** disk
>   cache or visited links (Playwright documents visited-links as impossible to
>   clear). A fresh context is not a fresh render environment.
> - No CDP event exists for full browser death — only `Target.targetCrashed`
>   for renderers. Liveness = the WebSocket closed, plus your own reconnect.
> - Multi-day memory growth has **zero** official guidance. Set a recycle
>   policy from your own measurements, not from blog posts.
>
> **5. The settle sequence to build** (ordered; each step names what it misses).
> Sources are official docs — full report with per-claim URLs and HOT/WARM/COLD
> grades at
> [docs/research/deterministic-screenshot-capture.md](../research/deterministic-screenshot-capture.md).
> 1. Pre-navigation init script: seed `Math.random`, fix the clock, inject
>    `!important` zero-duration animation/transition overrides. Must be
>    pre-navigation — **transitions outrank `!important` in the cascade** once
>    running, so a last-second override cannot stop one already in flight.
> 2. Wait for `load` — **not** network-idle (Playwright marks that DISCOURAGED).
> 3. `await document.fonts.ready`, freshly. Spec: the promise fulfils once and
>    further fonts may load after it.
> 4. Freeze what remains in-page: `document.getAnimations()` → `pause()` **and
>    pin `currentTime`** (pause alone leaves an arbitrary phase); plus
>    `svg.pauseAnimations()` for SMIL and `video.pause()` — `getAnimations()`
>    covers CSS animations/transitions/WAAPI only. **GIF/APNG have no pause API
>    at all** — a genuine hole, same one Playwright has.
> 5. Resolve lazy images without racing scroll: `captureBeyondViewport`, or
>    `await img.decode()` per image. No equivalent exists for CSS
>    `background-image`.
> 6. Double-rAF (a heuristic — not documented anywhere official), then
>    `checkVisibility({contentVisibilityAuto:true})`.
> 7. **Stability loop: capture, wait, capture again until two consecutive
>    captures match.** This is what Playwright actually does, and it is the only
>    step that does not depend on getting the signal list right — build it even
>    if 1–6 are incomplete. Failure mode to accept: a stable-but-wrong state
>    passes.
> 8. Pin once per session: `deviceScaleFactor`, `setScrollbarsHidden(true)`,
>    `overflow-anchor: none`.
>
> **Virtual time is excluded**, contrary to the original W1 text: it is
> Experimental, ships a `maxVirtualTimeTaskStarvationCount` anti-deadlock knob
> as its own admission of the failure mode, and — decisively — does not touch
> `requestAnimationFrame` at all, which is exactly the timing that matters here.
>
> **6. The designer↔lens gap is a missing artifact, not missing verbs.** The
> designer writes `structure.json` (screens/routes); the lens writes
> `shoot.json` (what it captured). Nothing states *what should be captured*.
> `lens shoot` is the only verb that enumerates anything (a hardcoded 390/744/
> 1280 ladder, no states); `lens states` needs a hand-typed trigger selector. No
> designer verb emits a surface list, and no lens verb consumes one. That
> missing file is W3's capture manifest — W1 does not need to solve it, but
> should not foreclose it.

> ### Amendment 2026-08-21 (later) — W1 BUILT. Three plan claims were wrong.
>
> Commits `d20ef451`, `e828fb48`, `5aea507d`. Everything below was measured on
> this machine, 4–5 captures per page, a fresh Chrome for each, with the old
> path run in the SAME pass as the control.
>
> | page | flat 1500ms | loop only | freeze + floor + loop |
> |---|---|---|---|
> | static | 1 distinct | 1 distinct, 338ms | 1 distinct, 1863ms |
> | animated | **5 distinct** | 5 distinct, TIMEOUT ×5 | **1 distinct**, 1862ms |
> | variable-load | 4 distinct | 2 distinct | **1 distinct**, 2178ms |
>
> **Correction 1 — the plan's animated row was wrong.** It recorded "1 distinct
> hash — byte-identical" and concluded animated pages were phase-locked and
> therefore fine. They are not: 5 of 5 distinct. This is the *larger* of the two
> defects and the plan had it filed as a non-issue.
>
> **Correction 2 — step 7 alone does not work.** The plan said to build the
> stability loop first because it "does not depend on getting the signal list
> right". True, and insufficient: an infinite animation never stops changing, so
> the loop cannot converge. It burned the full 6s timeout on all 5 runs and then
> captured an arbitrary frame — worse than the flat timer in both time and
> determinism. Steps 1/4 are prerequisites, not polish.
>
> **Correction 3 — pinning the phase is not enough, and this one is not in any
> doc.** A page whose animation is provably pinned (`currentTime` 0, computed
> transform identity, verified every run via the new `lens eval`) still gave 3
> of 4 distinct, worst case 13,345 pixels (4%). Isolated by differential: flat
> colour, gradient-only, and *static*-transform pages are all byte-identical;
> only animation+gradient varies; and dropping the `animation` property on that
> same page takes it to 4/4 identical. **An element that merely HAS an animation
> is promoted to its own compositor layer, and that layer rasters differently
> run to run.** So `freezeAnimations()` commits the frozen computed values
> inline as `!important` and *then* removes the animation. Committing first is
> what makes it safe — a bare `animation: none` would discard the end state
> `animation-fill-mode: forwards` was holding.
>
> **What shipped.** `CdpTab.freezeAnimations()`, `settleUntilStable()`,
> `settleForCapture()` and `navigateAndSettleForCapture()`. Sequence: freeze →
> floor → loop → freeze again → short loop. The second freeze exists because a
> transition fired by late-arriving data did not exist at the first. `settleMs`
> becomes the FLOOR, so the new path never captures earlier than the old one.
> Cost: ~24% slower, fully deterministic.
>
> **Six pixel paths migrated**, and the split is principled rather than
> alphabetical: `captureGolden`, `compareGolden`, `lens check`, `lens shoot`,
> both `gate_freeze` renders. The motion verbs (`anim`/`record`/`flipbook`/
> `burst`/`states`) stay on `navigateAndSettle` — they exist to observe motion
> and the capture settle destroys it. So do the **data** verbs
> (`dom`/`tokens`/`a11y`/`net`/`crawl`/`skeleton`), for a reason worth writing
> down: **`freezeAnimations` mutates the DOM.** It writes inline `!important`
> declarations onto animated elements. Correct for a screenshot, corrupting for
> an observation — `lens dom` would report inline styles that are nowhere in the
> source. Pixels here, data there.
>
> **A fourth correction, this one to the implementation, not the plan.** The
> first migration pass had all six callers *discard* `converged`. The settle
> detected non-convergence correctly and then production could not observe it —
> detection nobody consumes is the same as no detection. This is not
> hypothetical here: the amendment above already records that **GIF and APNG
> have no pause API**, so nothing can freeze them; same for a `setInterval`
> repaint or a buffering video. Those pages burned the timeout, captured an
> arbitrary frame, and `gate lens` reported PASS on a nondeterministic golden.
> Fixed in `81bb90f1`: `settleForCapture` warns on stderr *itself* (so a seventh
> call site cannot forget), `captureGolden` **throws** rather than writing a
> golden from an unsettled page (`allowUnstable` opts out), `compareGolden`
> fails with the reason *before* reaching the pixel verdict, both `gate_freeze`
> renders add it to `errors`, `lens check` adds it to failures, and `lens shoot`
> records `settled`/`settleMs` per rung in `shoot.json` so which rung was
> unreproducible survives in the evidence rather than only in the exit code.
>
> **MIGRATION DEBT — and it cannot be exercised here.** A golden captured under
> the flat timer on a page with any animation will now differ; static goldens
> are unaffected (measured identical under both paths). But this repo has **zero
> lens goldens**: `appbox gate lens` reports "no `lens` config block — gate
> skipped", and the single committed golden PNG
> (`appbox-studio/test/golden/goldens/home_view_default.png`) is a Flutter widget
> golden, which this change does not touch. So the debt lands entirely in
> downstream projects. Recapture there via `recaptureGoldens`, and expect the
> new `LensUnstableCapture` throw to surface any surface that was never
> reproducible in the first place — that is the debt being *found*, not a
> regression.
>
> **Verified 2026-08-21: the debt has no live target.** Checked both
> downstream projects directly — `clients/energize` (`landing/appbox.json`,
> `studio/appbox.json`: zero `lens` blocks) and `clients/normal_is_boring`
> (no `config/appbox.config.json`; `appbox gate lens` reports it cannot find
> a repo root). No lens-gate goldens exist anywhere downstream, so there is
> nothing to recapture today. The goldens that DO exist downstream
> (normal_is_boring `moodboard/reference/golden/*/…skeleton.json` +
> `review/replica-check/*.png`) are moodboard/review artifacts, not lens-gate
> goldens. The debt materializes only when a downstream project first adds a
> `lens` config block — at which point goldens are captured fresh under the
> settle-aware path anyway, and `LensUnstableCapture` surfaces any
> never-reproducible surface at capture time. Nothing to migrate; closed.
>
> **`lens eval` shipped** (`eval <url> <js-expr>`), and immediately earned itself
> — corrections 1 and 3 above were both diagnosed with it. Deliberately not
> routed through `_emitJson`: that gates the exit code on `certified`, and you
> reach for `eval` precisely when a page is misbehaving.
>
> **`lens click-burst` shipped**, promoting `tool/lens_click_burst.dart`. Fills
> what `burst` cannot see: `burst` frames from page load, so click-triggered
> motion (transitions, overlays, drawers) is invisible to it. A missed selector
> is a failure with zero frames written — a silently empty burst reads
> downstream as "this interaction has no animation".
> `tool/lens_footer_states.dart` is NOT promoted: it is project-specific
> (mod-footer, `#smooth-wrapper`), so it belongs to W3's manifest, not to a verb.
>
> **Warm Chrome — the `unknown` is now answered, conditionally: YES.** Measured
> across three page kinds chosen for the caches that warm up (font-shaping, GPU
> raster/shader, flat control) × four arms (cold-A, warm-same-tab, warm-new-tab,
> cold-B). **Every warm capture was byte-identical to cold.** The measurement
> carries its own controls: negative controls proving the instrument can see a
> 1-pixel/1-channel difference, a render-richness floor so a blank page cannot
> pass by drawing nothing, and the cold-A/cold-B pair proving the machine itself
> is reproducible — without which a warm match would prove nothing. Conditions
> held fixed, not proven invariant: Chrome 151.0.7922.170, one viewport, one
> settle, and a warm window only ~26s deep. **A daemon holds Chrome for hours;
> that depth is untested and is the condition it will exceed first.** Full report:
> [docs/research/warm-vs-cold-chrome-determinism.md](../research/warm-vs-cold-chrome-determinism.md).
>
> **The throw had to be caught, not just thrown (`85d86723`).** An uncaught Dart
> exception exits **255 with a stack trace**, but `lens` promises "0 ok / 1 fail
> / 2 env/usage" and a gate promises "0 pass / 1 fail / 2 not-applicable". A
> merely-unreproducible surface was crashing both — the exit-code inversion trap
> from the other direction. `lens shot` now exits 1 with the message and writes
> no PNG (verified live; the settling-page control still exits 0 and writes).
> `gate lens` passes `allowUnstable` on the **evidence** capture — evidence is
> diagnostic, not a reference, and when a surface never settles you want the
> picture of it more than ever — so the failing verdict comes from
> `compareGolden` and arrives *with* evidence. `--recapture` catches per surface
> and continues, so the operator sees every unreproducible surface rather than
> the first, and the run cannot abort halfway leaving some goldens rewritten and
> some not; any refusal makes the gate FAIL, because the operator's next move is
> `git add goldens/` and a green "RECAPTURED" that skipped a surface is the same
> false pass as ever.
>
> **Cost, measured on the real gate:** `appbox gate freeze` PASSES in **5m34s
> for 150 route/viewport renders** (~2.2s each) against
> `designs/appbox-studio-v2`. It was minutes before this change and it is
> minutes after. The dominant term is the 1500ms floor, not the stability loop
> (which converges in ~340ms on a settled page) and not the `fullPage` polling.
> **The obvious lever — lower the floor, since the loop now adapts — is
> deliberately NOT pulled.** The floor exists because the loop's failure mode is
> converging on the "before" state of a page still doing async work; that is
> measured (variable-load went 1 → 2 distinct when the floor was 150ms).
> Trading it for ~2.5 minutes without re-running the determinism table would be
> exactly the mistake this workstream exists to stop making.
>
> **Two daemon constraints found by accident, which is the best way to find
> them.** While the depth probe was running, its operator killed a stuck run
> with `pkill -9 -f "appbox-cdp-"` and `rm -rf …/appbox-cdp-*`.
> 1. **The temp-profile prefix is SHARED.** `cdp.dart:125` creates every
>    browser's profile with `Directory.systemTemp.createTemp('appbox-cdp-')`,
>    so that pattern matches *every* Chrome any `CdpClient.launch()` in this
>    repo has started — not just the one you meant. A daemon holding one Chrome
>    for hours is a single `pkill -f appbox-cdp-` away from dying, from any
>    script on the machine. The scoped reap already exists and must be the only
>    one used: `_pidsOwningProfile(dir, browserOnly: true)` matches the exact
>    `--user-data-dir=<dir>`, and its own comment records the near-miss —
>    *"Whole dir, not a prefix: `appbox-cdp-AB` must not claim `…-ABC`'s pid."*
>    A dir with no owning pid is a true orphan and safe to delete alone.
> 2. **A SIGKILLed run can never clean up after itself**, so the daemon needs
>    orphan reaping at startup — and that reap is exactly the scoped-ownership
>    check above, not a prefix match. This compounds with the already-recorded
>    constraint that **no CDP event reports full browser death** (only
>    `Target.targetCrashed`, for renderers): a closed WebSocket is the only
>    liveness signal, so the daemon cannot distinguish "Chrome was killed by an
>    unrelated script" from "Chrome crashed" — it can only notice the socket
>    closed and rebuild. Design for that, and log which profile dir it owned so
>    the orphan is attributable afterwards.
>
> ### Warm Chrome — CLOSED 2026-08-21. The daemon is unblocked.
>
> Four arms, each closing the previous one's weakest condition. Full report:
> [docs/research/warm-vs-cold-chrome-determinism.md](../research/warm-vs-cold-chrome-determinism.md).
>
> | arm | depth | drift | memory |
> |---|---|---|---|
> | warm vs cold, 3 page kinds × 4 arms | 15 captures | identical | — |
> | depth, one browser | **700 captures / 21m39s** | **0** | flat, −13MB over 530 |
> | at the real settle rate | 200 captures / ~1000 shots | **0** | flat, max rise 4MB |
> | **animated pages** | 180 captures / ~900 shots | **0** | flat, max rise 4MB |
>
> **The fourth arm is the one that mattered**, and it exists because the probe
> flagged its own blind spot: `freezeAnimations` had reported
> `committed: 0` on every capture of the first three arms — *every warm-Chrome
> result had been measured on pages where the machinery under test does
> nothing.* The fourth ran an 18-animation infinite page and a 24-animation
> `fill: both` page. Still zero drift. So the compositor-promotion effect that
> made animated pages nondeterministic does **not** survive the freeze's
> de-promotion pass, and reusing a warm browser does not reintroduce it.
>
> **Recycle policy: ~900–1000 SCREENSHOTS verified flat**, denominated in
> screenshots because `settleForCapture` costs ~5 per capture and any workload
> converts through that. On the capture axis, 700 verified. Neither axis found
> a ceiling; the binding limit is whichever a real workload reaches first.
>
> **Measurement discipline worth reusing.** The growth test is *max sustained
> rise*, not a fitted slope — least-squares misread three real curve shapes
> here (warmup, oscillation, step), each time describing the shape rather than
> a trend. The classifier was validated against a synthetic *growing* curve
> before its negative result was accepted, so "no growth" came from something
> able to say otherwise. `summedRSS` is labelled an upper bound because Chrome
> shares mappings and the double-count grows with process count — the very
> signal being read.
>
> **It also found a real defect in the settle API** (`d86d4d37`).
> `settleForCapture` returned the SECOND freeze's map; the first pass strips
> `animation` from every element, so the second reports all zeros on a page it
> froze perfectly. `frozen` read identically whether the freeze did everything
> or nothing — this project's oldest failure shape, built into the API meant to
> avoid it. Now returns the first as `frozen`, the second as `frozenLate`. The
> existing test asserting `freezeAnimations` counts honestly passed throughout:
> it exercises the method, and the defect was in the caller. **Test the caller.**
>
> **W1 CLOSED 2026-08-21.** The daemon shipped in `5edba1bd`, on the design in
> [lens-daemon.md](lens-daemon.md): no daemon process at all — a detached
> Chrome plus a state file, with CDP-over-WebSocket as the protocol, because
> `connect()` and the already-detaching `open -g` launch path made a supervisor
> unnecessary. Its prerequisite (`0d1039df`) found that the graceful
> `Browser.close` had never once executed: `close()` set `_closed` before
> calling `send()`, which throws when `_closed`, inside a bare `catch (_) {}`.
>
> **And the measurement corrected the premise.** Chrome launch is 0.46s of a
> `lens shot`; the `dart run` JIT floor is 1.45s — three times larger, never
> measured before the daemon was scoped. Shipping a compiled `appbox` binary
> outranks any further daemon work.
>
> *(historical)* **Still open in W1:** the daemon itself. The blocking unknown is gone, but the
> constraints from the earlier amendment stand — `--remote-debugging-port` not
> `-pipe`, one `--user-data-dir` for the daemon's life, `Target.createBrowserContext`
> does not give a fresh render environment, no CDP event for browser death.
> Before shipping it, extend the warm probe's depth until the window matches the
> intended session length.
- **W2 — evidence bundle + drill-down compare**, uniform across the four
  media kinds; structured verdict format.
- **W3 — capture manifest:** designer emit + lens manifest runner +
  bounded auto-loop wiring.
- **W4 — abx dictionary + gates** + scaffolder region identity + emitter
  golden-snapshot gate.
- **W5 — feedback dial + Supabase** (schema, RLS, realtime, worker JWT
  middleware in the deployer, operator toggle).
- **W6 — a11y toolbox island** + dial demo entry (request-driven,
  build on first client request).
- **W7 — media + content:** Pexels/Unsplash fetch in the designer with
  the asset ledger + credit rendering; content pass at intake/story-map
  emitting `content.json`; designer consumes ledger + content
  deterministically (LLM fallback writes back).

W1→W3 is the dependency spine; W4 can run parallel after W2's region
tree exists; W5/W6/W7 are independent of W1–W4 (W7's content pass hooks
into the intake/story-map stage).
