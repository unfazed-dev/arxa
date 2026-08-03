# Capability map — studio probes → `appbox design probe`

> **RETIRED 2026-08-03.** The ten Node/playwright-core studio probes and their
> shared `_probe_base.mjs` are archived at
> `archives/tooling-pre-dart/tools/studio-probes/`. The live suite is
> `appbox design probe <names…|all> --port N --project P`
> (`appboxd/lib/probes/`, over the one CDP engine in `appboxd/lib/cdp.dart`).
> Nothing was deleted — the originals stay readable, and this map is the audit
> trail that approved the swap.

Full audit of every studio probe (originally `tools/probe-*.mjs` + the shared
`tools/_probe_base.mjs`, now under `archives/tooling-pre-dart/tools/studio-probes/`)
against the Dart harness — `appboxd/lib/probes/` over `appboxd/lib/cdp.dart`,
dispatched by `appbox design probe <name…|all>`.

This map is the audit trail for the retirement: no `.mjs` file was archived
until its row here said where every one of its sections went. A section that is
not ported gets a written reason, not silence.

Status legend:

- **ported** — the section runs in Dart and agrees with the `.mjs` original on
  the same served tree.
- **ported (partial: …)** — landed with a recorded ceiling, named in the row.
- **dropped** — not ported, with a one-line reason.

## Suites — contract vs studio (task #21)

Plan: `docs/plans/design-derived-contract-probes.md`. The ten probes catalogued
below are the **studio suite** — the engine's smoke test, run through its
reference design. The **contract suite** asserts the appbox opinion against ANY
served design by deriving its targets from the design's own declarations,
rather than hard-coding studio routes.

### The contract v1 set

`contract-panels` and `contract-chips`, both registered ahead of the studio ten
so `probe all` leads with them. Both walk `GET /__routes` and load every
parameterless GET route the design declares; both print per-surface counts, so
a green run states its own denominator instead of implying one.

Two exclusions, counted and printed rather than applied silently:

- **Parameterized routes** (31 of 85 GET routes in appbox-studio). A value for
  `:id` can only come from knowing the design, and inventing one asserts about
  a 404 page. Deferred to v2, where the scaffolder's per-app manifest can
  supply real values.
- **Fragment responses** (27 of 54 parameterless GETs). A partial served
  standalone has no `<head>`, therefore no stylesheet, so `getComputedStyle`
  returns UA defaults and every chip reads `display: inline`. A check that
  fails there is measuring a page that never exists in the product. Detected
  via `document.doctype`.

Two calibrations were forced by evidence and are worth keeping in mind, because
both look like leniency and neither is:

- **A mounted panel is `.panel.panel-<role>`, not `.panel-<role>`.** The base
  emits both classes; the bare role class alone is the layout SLOT the card
  fills. `/design` carries `<div class="panel-main" id="panel-main">` wrapping
  `<section class="panel panel-main panel-viewer">`, while `/intake` and
  `/build` carry the slot with no card. Counting the bare class reads that pair
  as two main panels and reds a correct composition.
- **A chip may compute `display: flex` as well as `inline-flex`.** CSS
  blockifies a flex/grid item, so a chip inside a flex container computes
  `flex` however it was authored — 161 correct chips in appbox-studio alone. An
  unstyled chip computes `inline`/`block` and still fails.

The centring rule holds a glyph only to a control that DECLARES centring
(a flex/grid container with `align-items: center`). A card-shaped button that
stacks an icon above a heading never promised to centre it vertically —
`button.level-card` sits 24px off, correctly. On appbox-studio this excludes
exactly 1 glyph of 121; the other 120 are held, worst offset 0.01px.

### Deferred to v2: `contract-no-reload`

Not built, deliberately. The plan allowed it as a stretch and required that a
version too design-variable be deferred with the reason recorded rather than
shipped vacuous — this is that record. The generic form ("plant a window
marker, click the first boosted link, assert the marker survives") needs a
boosted link that navigates, and nothing in a design's own declarations says
which link that is: route discovery yields paths, not affordances. Picking
"the first `a[href]`" would silently select a `#` anchor, an external link or a
control that opens a panel on most designs, and a marker that survives because
nothing navigated is a check that cannot fail. Revisit in v2 alongside the
scaffolder's per-app probe manifest, which can name the boosted navigation the
way the design already names its routes.

### Mutation evidence — contract suite, 2026-08-03

Each mutation was applied to the served design, the probe re-run, and the file
restored with `git checkout --` (`git status --short -- designs/` clean after
each). A check that cannot fail is not a check; these are the runs that show
these can.

| # | mutation | probe | verdict | the line it produced |
|---|---|---|---|---|
| a | commented out the base `.chip` rule in `assets/css/widgets.css` | `contract-chips` | exit 1 | `[FAIL] every chip keeps the pill box model — 175 bad: /: .chip.proj-stage.proj-stage-build — display=block, align-items=normal, radius=0.0 for height 21.8` |
| b | re-added `margin-top: .3rem` to `.status-dot` (the a02ceaa defect) | `contract-chips` | exit 1 | `[FAIL] every glyph centres within 1px of its control — 17 off: /design: span.status-dot in span.chip off by 2.39px` |
| c | duplicated the header panel mount in `ui/views/main_shell/main_shell_view.html` | `contract-panels` | exit 1 | `[FAIL] each role panel is mounted at most once per surface — /: header mounted 2 times; /dashboard: header mounted 2 times; …` |

Mutation (b) is the load-bearing one: it re-introduces the exact regression
commit a02ceaa fixed, and the gate now catches it on every surface of any
design rather than nowhere. Mutation (c) keeps the base's open/close pair
balanced, so W4 is satisfied and no static check objects — only a runtime probe
can see two header panels, which is what makes the contract suite the
behavioural sibling of the W-gate rather than a duplicate of it.

**Green runs, same binary, both designs:**

| target | result |
|---|---|
| `appbox-studio` (port 4390, project `c21-probe`) | 2/2 probes — 25 document surfaces, 68 role panels, 107 sections, 185 chips, 120 glyphs held (worst 0.01px) |
| `hello-hda` (port 4391, project `c21-hda-probe`) | 2/2 probes — discovers `/` and `/timer`, 0 panels and 0 chips, passes with loud `[skip]` vacuity lines |
| `appbox design probe all` (appbox-studio) | 12/12 probes, contract first |

`hello-hda` is the design-agnosticism proof: no `registry.json`, no panels, no
chips, and the same compiled probes pass against it without a per-design code
path. Its zero counts are printed, not hidden — the probe says out loud that it
asserted about an empty set.

**Cost to note: both contract probes are `mutates: true`.** They issue only
GETs and never click, but a design may DECLARE a state-changing GET, and
appbox-studio does (`/build/chips/pin` and its unpin sibling answer 200 and
change pinned state). Walking every declared GET surface therefore leaves the
served project changed, which is the same reasoning `probe_panel_contract.dart`
records for itself. The consequence is real and may be worth revisiting: a
universal contract gate now refuses any target not bound to a `-probe`/`-test`
project.

### Decision: route discovery uses a new `/__routes` endpoint

The plan left this open with a preference order — (a) parse an already-served
artifact, else (b) add a small introspection endpoint. Resolved to **(b)**, on
evidence rather than taste:

- **The server already holds the answer.** `DesignServer._routeTable` is
  populated at boot from `_worker.routes()` (`design_server.dart:340`) as
  `List<List<String>>` of `[method, path]`. `/__routes` only has to serialize
  what is already in memory, joining `/__projects`, `/__project_use` and
  `/__project_write` in the existing introspection family.
- **(a) does not parse cleanly from Dart.** `app.routes.js` *is* served
  (asserted at `design_server_test.dart:362`), but it is an ES module whose
  default export is built from imports and spreads (`...appRoutes`,
  `...intakeRoutes`, `...designRoutes`). Reading it from Dart means
  re-implementing JS module evaluation — which the worker already did once, at
  boot, to produce `_routeTable`. Two parsers for one fact is the shape this
  consolidation exists to remove.
- **`registry.json` is not universal.** `hello-hda` — the design the contract
  suite MUST pass against to prove design-agnosticism — has no `registry.json`
  at all. Keying discovery on it would fail the acceptance bar by construction.

## Wave-D decisions — each decided, with the reason

Four questions were settled at retirement rather than left to whoever reads
this next. All four are cases where the ports deliberately do NOT reproduce the
original's behaviour, and each is a strengthening rather than drift.

1. **The 5s redo wait stays 5s.** It never was the problem. `shell-chrome`'s
   `redo enabled after stepping back` failed intermittently because the undo
   POST was answered **404** inside a hot-reload window, not because it was
   slow — and once that 404 landed, no wait of any length could have succeeded.
   A warm undo costs 32-34ms, so 5s is ~150x the real cost. Raising it would
   have hidden a defect that silently discarded a user's undo. Root cause and
   fix: see "The hot-reload window" below.
2. **Non-zero exit on failure is uniform in Dart.** Four of the ten `.mjs`
   probes print a failure trailer and still exit 0. The ports all exit non-zero.
   See the exit-code section for which four, and for why the evidence that
   appeared to contradict it never bore on the question.
3. **The disposable-project guard is uniform in Dart.** Several `.mjs` probes
   mutate the served project without calling `requireDisposableProject`; every
   mutating port declares `mutates: true` and the harness enforces the guard.
   The extra output line is documented divergence, not drift.
4. **The trailer is harness-owned.** `flowwalk`'s bare `PASS`/`FAIL` verdict
   shape is reproduced exactly (`bareVerdicts`), but its
   `ALL CHECKS PASSED` trailer is not: one suite gets one scannable closing
   line, or `probe all` ends with a different trailer per probe.

## Harness — `_probe_base.mjs` → `appboxd/lib/probes/probe_base.dart`

> Command lines in the dated evidence blocks below are reproduced **as they
> were run**, with the pre-retirement `tools/…` paths. They are records of
> executed commands, not instructions — rewriting them would misreport what
> was run. The archived probes do **not** run in place — each resolves the repo
> root as `../` from its own location, so playwright-core no longer resolves.
> To run one, copy it and `_probe_base.mjs` back into `tools/` first; the
> archive's README has the recipe, and notes that they reject `--project`,
> unlike the Dart suite.

| `_probe_base.mjs` export | Dart | status |
|---|---|---|
| `resolveBase(argv)` | `resolveTarget(args, env:)` → `ProbeTarget` (`probe_base.dart`) | ported — all three rules; pure, so `test/probe_base_test.dart` covers them without a subprocess |
| `requireDisposableProject(base)` | `disposableVerdict(json, base)` + `checkDisposableProject(base)` | ported — reads `boundProject`, never `current` |
| `waitFor(page, fn, {timeout,label})` | `probeWaitFor(session, expr, label:)` over `CdpSession.waitForFunction` | ported — returns false and reports, never throws; drains `__vtBusy` after the condition holds |
| `waitQuiet(page, {quietMs,timeout})` | `waitQuiet(session, quietMs:, timeoutMs:)` | ported — same two-identical-samples rule, same `count:length` sample |
| `trackTransitions(page)` | `trackTransitions(session)` over `CdpSession.addInitScript` | ported — same `__hxSettled` / `__vtBusy` counters, same skipped-transition settle |
| `ck(name, ok, extra)` | `ProbeReport.check(name, ok, [detail])` | ported — byte-identical line shape, asserted in `probe_base_test.dart` |
| `flowwalk`'s bare `check` (its line 35) | `ProbeReport(bareVerdicts: true)`, declared per probe via `Probe.bareVerdicts` | ported — emits `  PASS  label` (two spaces, word, two spaces) instead of `  [PASS] label`. A flag rather than letting the probe write to the sink itself: bypassing `check` bypasses the failure count, and a probe that prints FAIL while exiting 0 is the one outcome a suite must never produce. Pinned by a test that asserts bare mode still counts and still exits 1. Applies to verdicts only — `skip`/`warn`/`error` keep harness shape |
| suite trailer | `ProbeReport.finish()` | ported — `==== ALL PASSED ====` / `==== N FAILED ====`, exit 1 on any fail |
| one `node` process per probe (implicit isolation) | one browser context per probe — `CdpClient.createBrowserContext()`, `newTab(browserContextId:)`, disposed in a `finally` by the runner; carried on `ProbeContext.browserContextId` and used by `newPage` | ported — the `.mjs` suite got a fresh cookie jar per probe for free by running a separate process each time. The Dart runner shares one browser, so without this every probe's tabs shared `kdh_sid` and a probe's result depended on which probe ran before it: with `explode` finishing on the flows lens, a second tab saw 13 walk controls where a fresh context sees 0, and `flowwalk`'s section A failed while asserting about the views lens. Per probe, not per page — pages within one `.mjs` probe shared a browser (composer-draft opens two shells), so a page-scoped context would be stricter than the original |

### Verbs added to `cdp.dart` for the harness

Per the plan's "gaps go into cdp.dart, not around it". All additive; no
existing method changed, so `lens.dart` / `gate_lens.dart` are untouched.

| verb | why it had to be in the engine |
|---|---|
| `waitForFunction(expr, {timeout, polling})` | condition polling with a bounded timeout — the engine had only `navigateAndSettle`'s fixed `Future.delayed` |
| `waitForSelector(sel, {timeout, visible})` | presence/visibility wait; `clickSelector`'s precondition |
| `hover(x, y)` | pointer arrival without a press; `:hover` reveals act on it |
| `hoverSelector(sel, {timeout})` | hover a container to open a `:hover`-gated reveal, then act on what it exposed (shell-chrome section F: hover a tile, click the tool). Distinct from `clickSelector`'s internal hover, which lands on the element being clicked rather than on its container — aiming at the revealed child instead works by accident on a rail that overlaps its container and not at all on one that does not. Does not wait for the reveal; it cannot know what the reveal is, so follow it with `clickSelector`/`waitForSelector` on the revealed element |
| `clickSelector(sel, {timeout, synthetic})` | click by selector. **Hover-then-click is the uniform default, not an option** — CDP has no equivalent of Playwright's actionability checks, and several studio controls are `:hover`-revealed. The element box is re-measured *after* the hover, because revealing a rail shifts layout and the pre-hover centre can point at something else by press time. `synthetic` dispatches the element's own `click()` for controls no pointer can reach |
| `drag(fromX, fromY, toX, toY, {steps = 14, beforeRelease})` | press → N interpolated moves → release. `steps` is a correctness knob, not smoothness: a two-point drag is invisible to drag-threshold detection, so a resize probe built on one reports a working divider broken. Default matches what the studio's resize interactions were tuned against. `beforeRelease` runs after the final move with the button still down — some state exists only during a drag (a size badge `pointerup` removes, a request attributable to the release specifically), and reading it afterwards finds nothing, which is worse than failing because the assertion then passes vacuously. The release sits in a `finally`, so a throw from the observer or from any move cannot leave the button down — one stuck button would corrupt every later interaction in the shared browser and be diagnosed inside some unrelated probe |
| `dragSelector(sel, {dx, dy, steps, beforeRelease})` | the same, from an element's centre by a delta |
| `fillSelector(sel, value)` | set value **and** fire `input`/`change` — assigning `.value` alone is invisible to htmx and `hx-preserve` |
| `computedStyle(sel, props)` | computed-style read, null when the element is absent |
| `getResponseBody(requestId)` | one body by id; null when Chrome no longer has it |
| `recordNetworkBodies()` → `CdpNetworkBodies` | bodies captured on `Network.loadingFinished` — the earliest moment one exists and the latest it is guaranteed to. Collecting events and fetching bodies at the end is the obvious shape and the broken one: the page has navigated by then and the buffer is dropped, so the bodies that matter are exactly the missing ones. Records carry `encodedLength` (wire bytes) alongside the body, since a payload-size assertion wants the former and `body.length` is post-decompression |
| `addInitScript(source)` | `Page.addScriptToEvaluateOnNewDocument`; `trackTransitions` cannot exist without it |

(Drag was on the "not added" list until wave A2's inventory specified it —
`steps: 14` from `panel-resize` — at which point it stopped being speculative
and went in. Frame piercing followed the same route in wave C, below.)

### Frame verbs added to `cdp.dart` (wave C — `inspect`, `flowwalk`)

The engine addressed one document: the main frame's. The studio renders every
screen inside an `<iframe>`, so without these a probe can assert on the box
around a screen but never on the screen. Reading a same-origin child through
the parent's `contentDocument` is the apparent way around all of this, and for
a plain DOM read it is one — `explode` section B still does exactly that, on
purpose. It is wrong for the two things island probes actually ask, and both
failure modes are silent:

- `window.parent.htmx` evaluated in the PARENT resolves against the parent's
  own window, so flowwalk's bridge check would pass whether or not code inside
  the frame could reach it — an assertion that cannot fail;
- the viewer CSS-`scale`s its tiles, so `iframeRect.left + elementRect.left` is
  off by the scale factor and the pointer lands beside the element it was
  aimed at. `test/cdp_frames_test.dart` scales its fixture by 0.5 for this
  reason: an implementation built on that arithmetic passes every unscaled
  test and fails there.

| verb | why it had to be in the engine |
|---|---|
| `frames()` → `List<CdpFrame>` | `Page.getFrameTree`, flattened root-first. Frame ids are also how a probe tells the main frame navigating (the page working) from a CHILD frame navigating (`inspect` section 7's regression: the inspected iframe reloading on pin) |
| `frameForSelector(sel, {timeout})` | resolve an `<iframe>` ELEMENT to its frame, via `DOM.describeNode`. Not by matching `frames()` on URL: two tiles routinely show the same screen, and a URL match returns whichever the tree listed first. Null for a missing element and for an element that frames nothing |
| `evaluateInFrame(frame, expr, {awaitPromise})` | `Runtime.evaluate` in the frame's own DEFAULT world. CDP has no "evaluate in this frame" command — the frame↔context pairing exists only in `Runtime.executionContext*` events, so the session now tracks them. The default world, never an isolated one: an isolated world shares the DOM but not the page's JavaScript, so `document._inspect` and `window.parent.htmx` are simply absent there and a probe pointed at one reports a working island broken. Retries once on a stale context, because arming a tile re-navigates its iframe and "resolve the frame, then read it" has a real window in between |
| `waitForFunctionInFrame(frame, expr, {timeout, polling})` | `waitForFunction`, scoped to a frame; swallows the mid-navigation errors that are ordinary while waiting |
| `hoverSelectorInFrame(frame, sel, {timeout})` | a pointer arriving on an in-frame element, which is harder than it looks and cost most of wave C's debugging. Three things had to be true together, and each was measured failing on its own: (1) coordinates come from `DOM.getContentQuads`, which reports in the MAIN frame's space with every transform applied — see the scale note above; (2) the pointer must arrive along a PATH. The first `mouseMoved` into a child document delivers `pointerover`/`mouseover` and **no `pointermove`**, because the child's pointer state is created by that very event, so an island listening for `pointermove` hears nothing; (3) the moves must be SPACED. Chrome coalesces moves landing in the same compositor frame, so a two-point approach dispatched back to back arrives as the single move it was meant not to be. Measured against the studio's inspect island: one bare dispatch produced 1 `pointerover` and 0 `pointermove`, and the inspector pane never updated |
| `clickSelectorInFrame(frame, sel, {timeout, synthetic})` | `clickSelector`'s contract inside a frame — hover-then-click with a re-measure, `synthetic` for a target no pointer can reach |

Both in-frame pointer verbs wait for a **settled** box, not merely a present
element: arming re-navigates the iframe and the studio brings the tile back
through a view transition, so an element can be present and still report a box
on its way to where it will end up. Two identical non-zero measurements 60ms
apart is the test. Without it, `inspect` section 3 failed roughly one run in
three — measured too early, pointer beside the card, and a green section 4
right after it proving the coordinates were fine by then.

## Probes

| `.mjs` probe | sections | Dart module | status |
|---|---|---|---|
| `probe-composer-draft.mjs` | 2 shells × 2 checks: draft survives an unrelated swap; textarea clears after send | `probe_composer_draft.dart` (`composer-draft`) | **ported** — see parity evidence below |
| `probe-panel-contract.mjs` | A–L, 45 static → 63 runtime checks | `probe_panel_contract.dart` (`panel-contract`) | **ported** — see parity evidence below |
| `probe-panel-resize.mjs` | A–E, 17 static → 32 runtime checks | `probe_panel_resize.dart` (`panel-resize`) | **ported** — see parity evidence below |
| `probe-shell-chrome.mjs` | A–F, 16 static → 71 runtime checks (12× `panelsOk`) | `probe_shell_chrome.dart` (`shell-chrome`) | **ported** — see parity evidence below |
| `probe-no-reload.mjs` | A–D + capability + payload cost, 10 checks | `probe_no_reload.dart` (`no-reload`) | **ported** — see parity evidence below |
| `probe-boost.mjs` | 3 sections, 7 checks | `probe_boost.dart` (`boost`) | **ported** — see parity evidence below |
| `probe-context-sync.mjs` | 30 checks, 1 section | `probe_context_sync.dart` (`context-sync`) | **ported** — see parity evidence below |
| `probe-inspect.mjs` | 1–9, 21 checks | `probe_inspect.dart` (`inspect`) | **ported** — see parity evidence below |
| `probe-explode.mjs` | A–D, 29 checks | `probe_explode.dart` (`explode`) | **ported** — see parity evidence below |
| `probe-flowwalk.mjs` | A–D + errors, 14 checks | `probe_flowwalk.dart` (`flowwalk`) | **ported** — see parity evidence below |

## Parity evidence

### `composer-draft` — 2026-08-03

Method: `designs/appbox-studio` on port 4371, bound to `portalo-probe`. Each
side got its **own fresh `cp -R` of `portalo` and its own server boot** — not
one shared server. That is the correction to an earlier run of this comparison
which used a single server for both sides: the `.mjs` run POSTs two messages
into the project, so the Dart side would have started from a tree the first run
had already mutated, and "same served tree" would have been false of the
project even while true of the server.

Readiness is polled on `GET /design` containing the composer, not on
`/__projects` answering. The render worker boots Chrome behind the API, so the
API answers several seconds before a shell renders; probing on the API signal
made **both** suites fail on a genuinely fresh copy (the `.mjs` with
`page.fill: Timeout 30000ms exceeded`, the Dart port with a missing-textarea
`ERR`). Same defect, same count, both non-zero — accidental mutation evidence,
and a trap for wave C's boot scripts.

```
$ node tools/probe-composer-draft.mjs --port 4371          $ appbox design probe composer-draft --port 4371 --project portalo-probe
probe target: http://localhost:4371  (via --port)          probe target: http://localhost:4371  (via --port)
                                                           probe target: confirmed disposable project "portalo-probe" (boundProject)
=== /design ===                                            === /design ===
  [PASS] draft survives an unrelated swap                    [PASS] draft survives an unrelated swap
  [PASS] textarea clears after send — ""                     [PASS] textarea clears after send — ""

=== /design/freeze ===                                     === /design/freeze ===
  [PASS] draft survives an unrelated swap                    [PASS] draft survives an unrelated swap
  [PASS] textarea clears after send — ""                     [PASS] textarea clears after send — ""

==== ALL PASSED ====                                       ==== ALL PASSED ====
exit 0                                                     exit 0
```

Identical but for one line, which is a **deliberate divergence**: the `.mjs`
original never calls `requireDisposableProject`, even though its second check
submits the composer and POSTs a real message into the served project. That
looks like an oversight rather than a decision — it is exactly the shape of
probe the guard was written for — so the Dart port guards, and prints the one
line the guard prints. Anyone diffing the two suites should expect it.

**Falsifiability** (a check that cannot fail is not evidence): with the draft
wiped in the page immediately before the read, both shells reported
`[FAIL] draft survives an unrelated swap` and the run exited 1 with
`==== 2 FAILED ====`. The checks read live DOM state; they do not pass
vacuously.

**Target-rule behaviour**, verified on the same binary:

| invocation | exit | output |
|---|---|---|
| `--port 4371` (checks pass) | 0 | `==== ALL PASSED ====` |
| broken assertion | 1 | `==== 2 FAILED ====` |
| `--base http://localhost:1` | 2 | refuses — "could not confirm … is serving a disposable project" |
| `--bogus 1` | 2 | refuses — "unsupported argument" naming the default it would otherwise have hit |
| unknown probe name | 2 | refuses, listing the available names |

The `~/.appbox/current` marker read `portalo` before, during and after both
runs — `--project` binds the server process without touching it, which is the
reason the guard reads `boundProject` instead.

### `panel-resize` and `shell-chrome` — 2026-08-03

Two fresh `cp -R` copies of `portalo` and two server boots, per the correction
recorded above: the Dart side on port 4383 bound to `portalo-c2-probe`, the
`.mjs` side on 4384 bound to `portalo-c2mjs-probe`. Both probes mutate, so a
shared tree would have meant the second suite started from what the first left.

**`panel-resize` — 32 checks, identical on both sides.** Every check name, every
PASS, and every detail string matched byte-for-byte, including the mid-drag
numbers (`badge=390 box=390`, `badge=500 box=500`, `badge=340 box=340`), the
node census (`276/276 original nodes still live`) and the recorded request
(`["POST /design/panel/size/activity"]`). Only the summary line differs —
`==== ALL PASSED ====` (harness house style) against `==== ALL CHECKS PASSED ====`
— plus the guard line the Dart side prints and the `.mjs` original never had.

**`shell-chrome` — 70 checks, and the one FAILURE is identical too.** Both
suites, on independent fresh trees, produced the same warn and the same single
red:

```
  [warn] timed out after 5000ms waiting for redo to re-enable after undo
  [FAIL] redo enabled after stepping back
```

This is the known intermittent (task #55), and **failing is the more common
outcome, not the rare one**. Measured over nine Dart runs on this machine: six
failed, three passed at 70/70. The single `.mjs` run failed. An earlier note
here claimed a green run as the settled result on the strength of one sample;
that was wrong, and the corrected rate is recorded instead. Anyone treating a
single green `shell-chrome` run as verification of an unrelated change should
read this row first.

What is stable across every run, pass or fail, is where it breaks: **the undo
always lands.** `undo enabled once the canvas stack is non-empty` passed in
9/9 runs, and the post-undo panel census passed in 9/9. Only the redo
re-enable inside the 5s wait is unreliable. So the arming half of section F —
including the `:hover`-gated flow-move tool that has to be revealed and clicked
for the stack to arm at all — is exercised and green every single run.

**Whether 5s is simply too tight is not answered here, and is not a parity
question.** Both suites use the same 5s, so the port matches the original
either way; the wait was ported as written because the timeout value is part of
what the check documents. Settling it needs an in-browser measurement of how
long the redo re-enable actually takes past 5s, which belongs with whoever owns
the undo/redo path. Raising the timeout in the port alone would diverge from
the original and convert a reported signal into silence.

An attempt to reproduce the sequence over raw HTTP (session cookie, POST the
flow move, POST the undo, poll `/design`) did **not** reproduce it — undo never
armed at all that way, contradicting the browser result. That is a fidelity
failure of the HTTP mimicry, not evidence about the studio, and no conclusion
is drawn from it.

> **Instruction to wave D — read before acting on a red here.**
>
> 1. **A red on `redo enabled after stepping back` is NOT a port regression.**
>    The `.mjs` original fails it too, with the same warn and the same single
>    red. Both suites agreeing *in failure* is parity evidence — arguably
>    stronger than agreeing on a pass, because it shows the Dart port
>    reproduces the original's timing sensitivity and not merely its happy
>    path.
> 2. **Do not re-run until green to "prove" parity.** This row differs
>    run-to-run on BOTH sides. Re-rolling until both land green selects for the
>    3-in-9 outcome and manufactures agreement that says nothing; the honest
>    comparison is the one already recorded here.
> 3. **Do not raise the 5s timeout to clear it.** Both suites use the same 5s.
>    Changing it on the Dart side alone diverges from the original and converts
>    a reported signal into silence.
> 4. The underlying behaviour is tracked separately as *"Root-cause: redo
>    re-enable latency after canvas undo"* — that is where a fix belongs, not
>    in either probe.

A check that fails identically on both sides is stronger parity evidence than a
green run: it shows the port reproduces behaviour rather than merely reaching
the same verdict. Both sides also ran the eight assertions *after* the timed-out
wait, which is the warn-don't-throw contract the original's own comment calls
load-bearing — on both sides the post-undo panel census, the redo assertion and
the page-error check all executed and reported. **Not chased, per the port
brief** — the 5s timeout is part of what the check documents, and raising it
would convert a reported defect into silence.

**Divergence — exit code. SETTLED IN WAVE D.** Four of the ten `.mjs` probes
print a failure trailer and still exit **0**: `probe-boost.mjs`,
`probe-composer-draft.mjs`, `probe-explode.mjs`, `probe-shell-chrome.mjs`. None
of them calls `process.exit` or sets `process.exitCode` anywhere, so node exits
0 on normal completion no matter what was printed. The other six do set a
non-zero code — `context-sync`, `no-reload`, `panel-contract` and
`panel-resize` via `process.exit(fails ? 1 : 0)`, `flowwalk` and `inspect` via
`process.exitCode`. Every Dart port exits non-zero on any failure, uniformly.

The evidence that appeared to contradict this **was never evidence about it.**
An earlier parity row recorded `explode | 29 PASS, 0 FAIL, exit 0` and was read
as "explode's exit code is fine" — but that is a *passing* run, where exit 0 is
correct for both suites. A green run cannot distinguish "exits 0 because it
passed" from "exits 0 regardless"; only a failing run can, which is why the
mutation runs below were made to fail a probe from the exit-0 set on purpose.

This is a defect in the RETIRING suite, not a port bug: four of ten probes could
not fail a CI gate. The Dart suite's uniform non-zero-on-failure is recorded as
a deliberate **strengthening**, in the same class as the uniform disposable
guard — the ports do not reproduce a bug for the sake of byte parity.

### `panel-resize`'s two mid-drag observations

`CdpSession.drag` is atomic — press, N interpolated moves, release — and the
original observes state *between* the last move and the release, twice. This is
the gap `drag`'s `beforeRelease` was added for (see the verb table above); both
call sites use it and neither reconstructs the moment from anything else:

| original | port | status |
|---|---|---|
| section E reads the width badge with the button still down | `beforeRelease` evaluates `{badge, box, min, max}` in the page | ported — verified with real values (390/500/340/500) matching the CSS limits, not nulls |
| section C brackets `p.on('request')` around `mouse.up()` | `beforeRelease` attaches the `Network.requestWillBeSent` listener; it is cancelled after the post-release settle | ported — same bracket, and every request rather than only XHR, since one assertion is "no request at all" |

Both were first landed as substitutions built from public verbs only (a
capture-phase `pointerup` listener for E, `wallTime` correlation for C) while
the verb was being added. Those produced byte-identical output to the versions
recorded here, which is worth knowing if `beforeRelease` ever has to be backed
out — but the verb is the honest mechanism and the substitutions are gone.

**Other documented divergences.** `_swapNth` reports a missing control as a
failed check where the original threw and sent the whole run into its catch
(same rationale as section F's warn-don't-throw comment). Section E's vacuity
guard is a `check`, never a `skip`: a missing sample must read red, since that
check existing is the only thing standing between a null badge and twelve
passes that assert nothing.

### `panel-contract` — 2026-08-03

Method: `designs/appbox-studio` on port 4382, bound to `portalo-c1-probe` (a
fresh `cp -R` of `portalo`), both suites against that one server. Boot readiness
was polled on `/design` actually rendering `.panel-viewer` + `.panel-composer`,
never on `/__projects` — the render worker answers the API several seconds
before a shell exists, the trap recorded under `composer-draft`.

Parity: **63 checks on each side, identical per section** — A 2 · B 8 · C 5 ·
D 1 · E 4 · F 1 · G 1 · H 4 · I 15 · J 5 · K 11 · L 6. Section headers and check
labels diff clean; the only textual difference in the whole run is the trailer.

**Documented divergences**

1. Trailer — `==== ALL CHECKS PASSED ====` (`.mjs`) vs `==== ALL PASSED ====`
   (`ProbeReport.finish`). A wave-B decision every port shares, not this probe's.
2. `mutates: true` and the guard line it prints. The `.mjs` never guards, though
   G clicks into the activity panel's FILES view and follows a file link, and
   which surface `/design` shows is server-side session state — K exists
   precisely to navigate back out of it. Same omission the guard was written for.
3. `[skip]` vs the `.mjs`'s `[SKIP]` — `ProbeReport.skip`'s casing, harness-wide.
   G's no-file-link path, which did not fire here (a file link was present).
4. Section G waited a fixed 700ms in the `.mjs`; the port waits on the file link
   itself, with no report attached so that a legitimate "no file link on this
   surface" stays silent instead of printing a `[warn]` the `.mjs` never prints.
   On a slow first render the `.mjs` can SKIP G where the port runs it — a
   one-check difference that is the port being the more correct of the two, and
   should be read that way rather than "fixed" with a reintroduced sleep.
5. Section K's comment credited "Section D" for the file read that forces the
   `.mp-file-back` navigation. It is Section G. The dependency was real, the
   label was wrong; corrected in the port.

**Interpreted rather than copied**

- Section L's "fresh isolated page" is where Playwright and CDP genuinely part
  company. `browser.newPage()` opens a new browser CONTEXT — its own cookie jar
  and storage; `Target.createTarget`, which `ProbeContext.newPage` is built on,
  opens a tab in the DEFAULT context. The straight port therefore inherited the
  session G's file read left behind: `/design` rendered that read and L counted
  **4** chips against its `>= 20` coverage floor. Restored with
  `Network.clearBrowserCookies` + `Storage.clearDataForOrigin` on the fresh page
  before the first navigation. That is a workaround at the call site, not a
  primitive: the honest fix is a `newPage` that can open its own browser context
  (`Target.createBrowserContext`), which `cdp.dart` does not expose today. Any
  ported probe whose `.mjs` called `browser.newPage()` for isolation — rather
  than merely for a second tab — inherits this same trap.
- Predicates that were a regex literal or `parseFloat` in JS moved into Dart,
  raw values still crossing the boundary so details print identically. This is
  not cosmetic for `parseFloat`: `double.tryParse('0px')` is null, which would
  quietly invert `parseFloat(min) === 0`. Conversely every `Math.round` stays
  inside the JS where the `.mjs` had it, because Dart prints `640.0` where JS
  prints `640`.

**Falsifiability** (a check that cannot fail is not evidence): not asserted by
inspection here — L's coverage check actually reported
`[FAIL] … found only 4` on the first run and `[PASS] … found 25` after the
isolation fix, same binary, same server. Section L's own mutation self-test also
fires as designed: disabling `widgets.css` in-page flips the pill contract and
reports `confirmed: chips lost their box model`, so L is not vacuous.

### `boost` and `no-reload` — 2026-08-03

**Method**: two fresh `cp -R ~/.appbox/projects/portalo` disposable copies
(`portalo-wc-probe`, `portalo-wc-test`), two independent `design serve
designs/appbox-studio` boots on dedicated ports — 4374 (`.mjs`/Node side, bound
to `portalo-wc-probe`) and 4376 (Dart side, bound to `portalo-wc-test`), each
confirmed via `GET /__projects` before running anything. `boost` (read-only)
run before `no-reload` (mutates) on each server, so `boost` never sees pinned
context-state left by `no-reload`. `~/.appbox/current` was never touched by
either boot — `--project` resolves the server's data directly from parsed
args, with precedence over `APPBOX_PROJECT` and the current-file fallback, and
never calls `useProject()`; confirmed via `/__projects` on both servers
throughout (`current: portalo` on both, unchanged by the `--project` flag).

**`boost`** — `node tools/probe-boost.mjs` against :4374 and
`design probe boost --port 4376 --project portalo-wc-test` against :4376:
check names, verdicts, and every interpolated value (`src`, `href` pairs, the
window token) are byte-for-byte identical between the two runs, including the
benign `[warn] timed out after 8000ms waiting for the home tile to become
live` — the `.mjs` original tolerates this race as warn-not-fail (proceeds
regardless, the checks after it report the real state either way), and the
Dart port's `probeWaitFor` is uniformly soft (warns via `report.warn(...)` and
returns `false` rather than throwing) — confirmed by reading
`probe_base.dart:399-414` directly, not inferred: there is no separate
hard-fail wait primitive in the harness, so `boost`'s one `probeWaitFor` call
needed no special-casing to match the `.mjs`'s tolerance. `==== ALL PASSED
====` on both sides.

**`no-reload`** — `node tools/probe-no-reload.mjs` against :4374 and
`design probe no-reload --port 4376 --project portalo-wc-test` against :4376:
all 10 checks match in name, verdict, and count on both sides (iframes
`20 -> 20` survivors, `0` re-navigations, `3` pin responses, all `[PASS]`).
One deliberate divergence, by design: section E's largest-pin-response byte
count — `115842` (`.mjs`, decoded `body.length`, post-decompression) vs
`116073` (Dart, `encodedLength`, actual wire bytes) — different numbers
because they measure different things; both land well under the 200 KB
ceiling so both `[PASS]`. `mutates: true` is declared on the Dart port where
the `.mjs` original never guarded at all (see "Registry — adding a probe
(wave C)" below) — a strengthening, not drift: `no-reload` clicks controls
that `hx-get*="context"` (POSTs into chat-context state) and one in-tile
navigation, none of which the `.mjs` ever fenced against running on a live
project.

**Falsifiability**: the guard itself was exercised, not just read. Running
`design probe no-reload --port 4319` (the live server, bound to the
non-disposable `portalo`, `current` marker untouched) refused before any
mutation with exit 2 and the guard's own remediation text (`cp -R
~/.appbox/projects/portalo ~/.appbox/projects/portalo-probe`, `--project
<name> --port <n>`, `boundProject is fixed at boot`) — confirming the
regex-gated refusal is live, not vestigial, and that a probe author pointing
`no-reload` at the wrong project gets stopped before it writes anything.

### `context-sync` — 2026-08-03

Method: `designs/appbox-studio`, two fresh `cp -R` copies of `portalo` and two
independent server boots — `.mjs` side on port 4372 bound to
`portalo-cs-a-probe`, Dart side on port 4373 bound to `portalo-cs-b-test`.
`needsBrowser: false`: no Chrome is launched for this probe at all, HTTP-only
GETs against a cookie-jar session, matching the harness note that
`context-sync` is the one case `Probe.needsBrowser`'s doc comment names by
name.

`.mjs`, port 4372, `portalo-cs-a-probe` (`/tmp/cs-mjs-clean.log`):

```
probe target: http://localhost:4372  (via --port)
probe target: confirmed disposable project "portalo-cs-a-probe" (boundProject)

=== the composer names every pinned screen the canvas marks ===
  [PASS] 1 pinned: the composer shows a context label — "context"
  [PASS] 1 pinned: one chip per pin — ["portalo.home"]
  ...
  [PASS] cleared: the composer drops the context label — null

==== ALL CHECKS PASSED ====
```

Dart, port 4373, `portalo-cs-b-test` (`/tmp/cs-dart-final.log`):

```
probe target: http://localhost:4373  (via --port)
probe target: confirmed disposable project "portalo-cs-b-test" (boundProject)

=== the composer names every pinned screen the canvas marks ===
  [PASS] 1 pinned: the composer shows a context label — "context"
  [PASS] 1 pinned: one chip per pin — ["portalo.home"]
  ...
  [PASS] cleared: the composer drops the context label — null

==== ALL PASSED ====
```

(`...` above elides checks 2–29 of 30 — the middle of the one/two-pin loop,
the unpin-via-chip block, and the views/flows/proto filmstrip loop. The next
paragraph covers what those elided checks showed, not by reprinting them but
by the `diff` result described below.)

All 30 checks — one pin, two pins, unpin-via-chip, the views/flows/proto
filmstrip-gating loop, and the final clear — matched name-for-name and
detail-string-for-detail-string (`diff` on the two runs' check bodies, target
and trailer lines stripped, is empty). One real gap turned up along the way
and was fixed rather than logged as a divergence: the three post-unpin detail
strings (`chips.length`, `stripPinned`, `tilesPinned` counts) used the
original's `→` glyph in `.mjs` but a plain ASCII `->` in the first Dart draft
— an unintended miss, not a decision, so `probe_context_sync.dart` now emits
`→` to match byte-for-byte.

Two divergences remain, both **deliberate** and both already covered by this
document's general rules rather than specific to this probe:

- **Guard line.** `.mjs` prints its own ad hoc confirmation string;
  `probe_context_sync.dart` prints `checkDisposableProject`'s line via the
  shared harness. Same fact, same enforcement, different sentence — the
  `composer-draft` section above covers why the port always prints the
  harness's line.
- **Suite trailer.** `probe-context-sync.mjs` never used `_probe_base.mjs`'s
  shared trailer to begin with — it has its own bespoke
  `` `\n==== ${fails} CHECK(S) FAILED ====` `` / `'\n==== ALL CHECKS
  PASSED ===='` printed inline (line 132), unlike
  `composer-draft`/`panel-resize`, which happened to already agree with the
  harness wording. The Dart port
  standardizes on `ProbeReport.finish()`'s `==== ALL PASSED ====` /
  `==== N FAILED ====` for every probe uniformly, per the harness table
  above — this is the same normalization, just visible here because this
  particular `.mjs` diverged from its own harness's own convention too.

**Falsifiability**: with `pins`'s first label deliberately swapped to
`'WRONGLABEL'` in the Dart port, the run reported
`[FAIL] 1 pinned: the new chip names the screen` and
`[FAIL] 1 pinned: the placeholder agrees`, exited 1, and printed
`==== 2 FAILED ====` — reverted immediately after. The checks read live
server state; they do not pass vacuously. (`readContext`'s pure-parser layer
has its own fixture-based falsifiability independent of any server —
`test/probe_context_sync_test.dart`, including a regression fixture for the
`tileTone` lookahead window matching the wrong tile when two `dv-tile`s sit
within its 80-character scan.)

### `inspect`, `explode` and `flowwalk` — 2026-08-03

The three island/iframe probes. Run against one disposable studio
(`--port 4385`, project `portalo-c4-probe`), with the server restarted onto a
fresh copy of the project between the two suites: the pin in `inspect` section
7 and the walk position left by `flowwalk` are both server state, and a second
suite inheriting them produces an asymmetric diff that reads as a port bug.

| probe | `.mjs` | Dart | check labels |
|---|---|---|---|
| `inspect` | 21 PASS, 0 FAIL, exit 0 | 21 PASS, 0 FAIL, exit 0 | identical, in order |
| `explode` | 29 PASS, 0 FAIL, exit 0 | 29 PASS, 0 FAIL, exit 0 | identical, in order |
| `flowwalk` | 14 PASS, 0 FAIL, exit 0 | 14 PASS, 0 FAIL, exit 0 | identical, in order |

Compared with the verdict prefix and the ` — detail` suffix stripped, so the
comparison is of what was asserted rather than of numbers that legitimately
differ between runs (request counters, measured boxes).

`flowwalk` sets `bareVerdicts: true`, so its 14 verdict lines match the
original byte for byte **including the prefix** — bare `  PASS  `, not
`  [PASS] `. Verified by diffing the lines with only the ` — detail` suffix
stripped. It is a harness flag rather than this probe writing to the report's
sink because `check()` is the only path to the failure count: bare lines
written directly would print `FAIL` and still exit 0.

One divergence remains, in output rather than in what is asserted:

- **Trailers are the harness's.** `==== ALL PASSED ====` for all three, where
  the originals print `ALL PASS` (inspect), `==== ALL CHECKS PASSED ====`
  (explode) and `ALL CHECKS PASSED` (flowwalk). One suite needs one scannable
  closing line, or `probe all` ends with a different trailer per probe.

Two ports are STRONGER than their originals rather than equal:

- **`inspect` waits for the island's request, not for the DOM to go quiet.**
  The island POSTs from a `pointermove` handler, and between the pointer
  arriving and the response swapping the panel the DOM does not change at all —
  `waitQuiet` samples that gap, sees two identical samples and returns before
  the request it is meant to be waiting for has been sent. The `.mjs` calls the
  same `waitQuiet` and gets away with it because Playwright's `hover()` spends
  longer on actionability checks than the round trip takes, which is a race it
  happens to win rather than a wait. The port waits on the request counter it
  already keeps, then settles.
- **`inspect` declares `mutates: true`** (section 7 pins into chat context), so
  the disposable-project guard runs from the declaration before Chrome starts,
  where the original calls `requireDisposableProject` by hand. `explode` and
  `flowwalk` declare `mutates: false`: every interaction in them is a GET —
  lens swaps via `htmx.ajax('GET', …)` and viewer-state route reads — and
  nothing is written into the served project.

`flowwalk` was ported first on purpose. Its "active tile moved to
portalo.home" check is a free oracle for the in-frame coordinate math — wrong
coordinates mean no advance, and the check goes red — so the pointer path was
validated there before `inspect`, which has 21 checks depending on it, was
allowed to rest on it.

### The isolation the `.mjs` suite had by accident

All three pass standalone. Under `probe all` they did not, and the reason is
not in any of them: **the runner shares one browser, and the studio keys its
session off a `kdh_sid` cookie**, so every probe in a run shares one server
session. Whichever viewer lens is showing, where a flow walk has advanced to,
whether the inspector is locked and what is pinned into chat context all travel
with that cookie.

The `.mjs` suite never had to think about this — one `node` process per probe
meant one browser per probe, hence one cookie jar per probe. The Dart runner is
a regression in isolation relative to it, and the first casualty was concrete:
`explode` finishes with the viewer on the flows lens, `flowwalk` runs next, and
its opening section reads flows-lens toolbars while asserting about the views
lens. Measured directly — a second tab in the shared context sees 13 "Walk the
flow" controls where a fresh one sees 0.

`cdp.dart` now has the two verbs that close it, additive and in the same style
as the frame verbs:

| verb | why |
|---|---|
| `createBrowserContext()` → `browserContextId` | `Target.createBrowserContext` — Chrome's incognito-profile equivalent, with its own cookie jar. A fresh cookie jar is a fresh `kdh_sid`, hence a fresh server session |
| `disposeBrowserContext(id)` | `Target.disposeBrowserContext`, closing every tab in it. Best-effort, so a double dispose at teardown never becomes the error a passing probe reports |
| `newTab({url, browserContextId})` | additive optional parameter; omitted, behaviour is exactly as before (the shared default context) |

Covered by `test/cdp_browser_context_test.dart`, whose first case asserts that
two default-context tabs DO share a session — so that if tabs ever isolate on
their own, the test that proves the plumbing is needed fails first rather than
the plumbing quietly becoming dead weight.

Wiring it into `ProbeContext.newPage` is the harness's call, not this file's.

## Retirement evidence

Two things had to hold before a single `.mjs` file moved: the suites agree on a
healthy tree, and they agree on a BROKEN one. Agreement on green alone is weak
evidence — two suites that both assert nothing would also agree.

### How these runs must be taken, and why

Four rules, each of which was learned by a run that violated it and produced a
number nobody could trust:

1. **Sequential, one server, quiet machine.** Two measurement runs overlapped
   once; the second was executing probes while the first was DELIBERATELY
   MUTATING `designs/appbox-studio/`. Its output recorded probes run against a
   knowingly broken studio, so it was discarded outright rather than treated as
   noisy-but-usable. Concurrency does not merely add variance here — it can
   invert what is being measured.
2. **A fresh disposable project per run.** Probes mutate the project, so a
   shared copy makes the second run start from a tree the first one changed.
   An early comparison did exactly that and had to be redone.
3. **Readiness is the control you are about to touch**, not `/__projects`
   answering. The API responds several seconds before a shell renders; polling
   it made BOTH suites fail identically for a reason that had nothing to do
   with either suite.
4. **A contaminated run is disclosed and re-run, never averaged in.** A
   disposable project was deleted mid-run by an unrelated cleanup; every run
   spanning that window is named as affected and repeated. A verdict resting on
   a contaminated run does not count, and "it probably still holds" is not a
   substitute for repeating it.

Durable evidence lives in this file. An earlier baseline was verified as 52
artifacts in the session scratchpad, reported truthfully, and then silently
expired when tmp was wiped — a verified-at-the-time claim about ephemeral
storage has a shelf life, and this file is what outlives it.

### Final parity — both suites, settled tree

Run 2026-08-03 on the settled tree — post-unification, all wave-D edits in
place, **including the chip icon-alignment fix** to `app.css` / `intake.css` /
`widgets.css` — sequentially on a quiet machine, a fresh `cp -R` disposable per
run, 20 runs, each probe once per suite, no re-rolls.

An earlier run of this same comparison, taken before that CSS fix landed, was
re-run rather than kept: a parity claim has to be about the tree being
retired, and CSS is part of what the probes assert against. Both runs produced
the same 279/279, so the fix is probe-invisible — but that is a result, not an
assumption that licensed skipping the re-run.

| probe | checks | `.mjs` | Dart | verdict lines |
|---|---|---|---|---|
| `boost` | 7 | 7 PASS / 0 FAIL | 7 PASS / 0 FAIL | identical |
| `composer-draft` | 4 | 4 / 0 | 4 / 0 | identical |
| `context-sync` | 30 | 30 / 0 | 30 / 0 | identical |
| `explode` | 29 | 29 / 0 | 29 / 0 | identical |
| `flowwalk` | 14 | 14 / 0 | 14 / 0 | identical |
| `inspect` | 21 | 21 / 0 | 21 / 0 | identical |
| `no-reload` | 9 | 9 / 0 | 9 / 0 | 1 line differs — see below |
| `panel-contract` | 63 | 63 / 0 | 63 / 0 | identical |
| `panel-resize` | 32 | 32 / 0 | 32 / 0 | identical |
| `shell-chrome` | 70 | 70 / 0 | 70 / 0 | identical |
| **total** | **279** | **279 / 0** | **279 / 0** | **10/10 agree** |

279 checks per suite, matching the pre-unification baseline's recorded 279
exactly — so the reload-tracking unification is **probe-invisible**, which is
what that comparison existed to establish.

**The one differing verdict line, stated rather than rounded away.**
`no-reload`'s payload-size check reads:

```
.mjs   [PASS] pin response under the 200 KB blow-up ceiling — 115842 bytes
Dart   [PASS] pin response under the 200 KB blow-up ceiling — 116073 bytes
```

Both PASS, both far under the ceiling; the 231-byte (0.2%) gap is a *measured
quantity* that legitimately varies between two independently booted servers,
not an assertion outcome. The check's verdict is identical. This is the only
non-identical verdict line in 279.

**`[warn]` lines match too.** `boost` emits
`[warn] timed out after 8000ms waiting for the home tile to become live` in
BOTH suites, byte for byte — including wording hand-ported into
`probe_base.dart`. The warn path was never exercised by the earlier parity
runs; it agrees.

**Trailer banners diverge in 8 of 10 — broader than first recorded.** Only
`boost` and `composer-draft` match exactly (`ALL PASSED` both sides). The other
eight print `ALL CHECKS PASSED` on the `.mjs` side against the harness's
`==== ALL PASSED ====`, and `inspect` prints no `====` trailer at all. This is
consistent with the byte-identity claim, which was always scoped to *verdict
lines*; the banner is harness-owned by decision 4 above. Recording the real
count because "panel-contract's banner differs" understates it.

### Mutation equivalence — do both suites catch the same break?

Two deliberate breakages, each run against BOTH suites, restorations verified
green afterwards.

**M1 — the chip contract kill (`panel-contract` §L).** The section's own
built-in mutation: disable the `widgets.css` `<link>` in-page and assert the
pill contract collapses. Both suites reported **2 FAILs**, and the FAIL lines
were diff-verified byte-identical *including their JSON payloads*. Exit: Dart 1,
Node 1 (`probe-panel-contract.mjs` has a `process.exit` at line 402).

**M2 — `hx-preserve` stripped from the composer textarea** (`composer.html`,
the `{% if not c.draftSent %}` guard). Both suites reported **2 FAILs**, the
same check twice — `draft survives an unrelated swap`, once per shell — with
identical failure lines. Exit: **Dart 1, Node 0.**

That last number is the point of choosing M2. `composer-draft` is one of the
four probes with no `process.exit` anywhere, so this is the **empirical**
confirmation of the exit-code defect on a second probe, reproduced twice on
independently built servers. The finding moves from "one observed, three
inferred by grep" to two observed — and it could only ever be obtained from a
*failing* run, which is exactly why a green run's exit 0 never settled it.

Both suites therefore agree on a healthy tree AND on a broken one, in both the
checks that fail and the lines they print. That pairing is the retirement
evidence; the green run alone would not have been.

**Contamination disclosed, not averaged in.** One run was invalidated when an
unrelated cleanup deleted the disposable project mid-flight (a
`PathNotFoundException` then a `CdpException`). That run was discarded and
counted nowhere; the graded runs were rebuilt from scratch on a separate
disposable copy, with all six probe sources md5-pinned before and after —
identical, HEAD `4c7d8fb` throughout. One re-run per suite is disclosed, for
exit-code capture rather than for a greener result.

## The hot-reload window — a live product defect, not a probe flake (task #19)

`shell-chrome`'s `redo enabled after stepping back` used to fail intermittently
(6/9 on one machine, 5/5 on another). It was **not** a timing tolerance and
**not** a regression in the undo path. Root-caused 2026-08-03 by measurement and
**FIXED** the same day — `design_server.dart` now defers dispatch while a hot
reload is in flight. Acceptance: **shell-chrome 9/9, 70/70 checks each, with the
watcher on**. The mechanism below is kept because it explains the check, and
because the same shape can reappear anywhere a request follows a project write.

**Mechanism.** A canvas mutation writes the project → the project watcher fires
→ a 200ms debounce → `_worker.reload()` re-navigates the worker tab → the JS
realm is wiped, so `worker_shim.js`'s `let routesTable = []` re-runs. For the
~900ms until `__boot` re-imports `app.routes.js`, `globalThis.__dispatch` still
EXISTS but the table is EMPTY, so **every request 404s**. Dart keeps dispatching
because its own boot-time copy still holds all 142 routes; only the worker's
table is gone. Measured at the moment of failure:
`LIVE worker routes=0 (dart copy=142)`. The task-#64 self-heal cannot catch it —
that matches "`__dispatch` is not a function", and here dispatch works fine and
simply has nothing to route.

**Evidence.** Two runs, same idle machine, minutes apart:

```
FAIL  812099 move -> 200 | 812274 RELOAD START | 812572 undo -> 404 | 813178 RELOAD END (904ms)
PASS  877124 move -> 200 | 877512 undo -> 200  | 877801 RELOAD START
```

The sole discriminator is whether the undo POST reaches the server before or
after `RELOAD START`. Causal control: `--no-watch` (no watcher, no reload) gives
**70/70 PASS across 3 runs** with the undo answering **200 in 32-34ms**, against
**5/5 FAIL** with the watcher on — both arms under identical load.

**Two pieces of folklore this corrects.** The `.mjs` comment's "fails under
concurrent load (task #55)" is backwards: load shifts *when* the undo lands
relative to the window, so heavy load can make it PASS (observed — a `probe all`
run went 10/10 with `shell-chrome` last). And nothing regressed in the undo
route, which is healthy at 32ms warm.

**Wave D: keep the 5s wait — decided, not deferred.** It was never the problem
and raising it could never have helped: once the 404 landed, no wait succeeded.
It stays 5s now that the fix has landed, because a warm undo is 32-34ms and 5s
is ~150x that. The check's red was real and pointed at a real defect; treating it
as a tolerance problem would have hidden a bug that silently discarded a user's
undo.

**The fix.** `design_server.dart` tracks the in-flight reload
(`_reloadInFlight`, set by `_trackedReload`) and `_dispatch` waits on it —
outside the session lock — before dispatching. It defers, it does not translate:
a route that genuinely does not exist still reaches the worker and still answers
404 *after* the wait, so the deferral cannot mask a routing bug. The grace is
3800ms (4x the slowest reload observed, covering the task-#51 boot-retry path);
beyond it the request answers **503** with a new `errorSurface.reloading` string,
never a silent 404. Three tests pin it in `design_server_test.dart`, including a
`_widenBootWindow` helper that holds `__boot` open so the window is hit on
purpose rather than by luck.

**Which probes are exposed** (analysis by the islands port agent, from the code
paths). The vulnerable shape is *any* check reading a request issued within
~1.1s of a **project** write — undo is merely the request that always
immediately follows one.

- `explode`, `flowwalk` — GET-only (lens swaps, viewer-state reads). No write,
  no window.
- `inspect` — declares `mutates: true`, but `chat_viewmodel.js` `elementContext`
  → `facade.pinElement` writes **session** data, not the project on disk, so it
  never trips the watcher. The flag is inherited from the `.mjs` original's
  `requireDisposableProject` call and earns its keep as a disposable-target
  guard; it is deliberately left set (conservative in the safe direction) and is
  **not** evidence of a project write.
- `shell-chrome` — writes the project (flow move). Confirmed exposed; this is
  the measured case.

Caveat on that analysis, stated rather than glossed: the serve log shows no
reload lines, but the server does not log reloads without instrumentation, so
absence of log lines is not confirmation — the code paths are the evidence.

Before the `.mjs` originals are archived, wave D should sweep the remaining
probes for "writes the project, then asserts on the next request", or this race
gets rediscovered as a flaky port.

## Recorded ceilings

- **`waitUntil: 'networkidle'` has no CDP equivalent.** `ProbeContext.goto` uses
  the load event plus `waitQuiet`. Arguably the better wait — it tracks the DOM
  the assertions actually read rather than a request count — but it is not the
  same wait, and a probe that depends on a late XHR settling should name that
  condition with `probeWaitFor` rather than trust `goto`.
- **`clickSelector(synthetic: true)` does not exercise hit-testing.** It is the
  faithful port of the `.mjs` `el.evaluate(e => e.click())`, and it inherits
  that call's blind spot: a control covered by an overlay still "clicks". Where
  pointer geometry is the thing under test, use the default mode.
- **`fillSelector` is not keystroke-faithful.** Playwright's `page.fill` clears
  and types, firing `beforeinput` and `input` along the real edit path;
  `fillSelector` assigns `.value` and fires `input` + `change`. Both leave the
  same value in the box, so `composer-draft` cannot tell them apart — but a
  probe asserting on a keystroke-triggered request (`hx-trigger="keyup"`,
  per-character debouncing, an `input` handler reading `event.data`) can, and
  will see the divergence rather than the regression it was looking for. Wave C
  hits this first in any typeahead or filter-as-you-type check; the fix when it
  lands is `Input.dispatchKeyEvent` per character, not a patch to `fillSelector`.
- **`fillSelector` reports a missing element by returning false, not throwing.**
  That is the right engine-level shape, but it means a probe that ignores the
  return runs its checks against a page that never had the control — reporting
  the feature broken when the truth is the probe never found it. Probes must
  treat a false fill as a hard stop; `probe_composer_draft.dart`'s `_fill`
  helper is the pattern.

## Registry — adding a probe (wave C)

Two edits, and no wave-C agent touches another's file:

1. Write `appboxd/lib/probes/probe_<name>.dart` exporting a `const Probe`:

   ```dart
   const Probe myProbe = Probe(
     name: 'my-probe',            // the CLI name; must not be `all`
     summary: 'one line for the CLI listing',
     mutates: true,               // true if it writes into the served project
     needsBrowser: true,          // false for a pure-HTTP probe (default true)
     body: _run,                  // Future<void> Function(ProbeContext)
   );
   ```

2. Add the import and one entry to `kProbes` in `appboxd/lib/probes/registry.dart`,
   positioned in run order (cheap/read-only probes first, so a broken server
   fails the suite in seconds).

Inside `_run`, `ctx` gives you `ctx.base`, `ctx.newPage()` (fresh target,
viewport, transition counters installed), `ctx.goto(page, '/design')`,
`ctx.closePage(page)` and `ctx.report`. Use `probeWaitFor` where the
post-condition can be named and `waitQuiet` only where it genuinely cannot —
an assertion that waits for the wrong condition is worse than one that waits
too long, because it passes vacuously.

`mutates: true` is the switch that makes the disposable-project guard run
before Chrome launches. Set it if the probe clicks anything that POSTs. The
guard is enforced **uniformly** from the declaration, which is a deliberate
strengthening over the `.mjs` suite: `probe-no-reload` and
`probe-composer-draft` both mutate without ever calling
`requireDisposableProject`, and that omission is precisely the case the guard's
incident rationale describes. The ports declare `mutates: true` and the harness
enforces it; the resulting extra output line is documented divergence, not drift.

`needsBrowser: false` is for a probe that talks to the server over HTTP and
never needs a page — `context-sync` is the case. The harness launches no Chrome
at all for such a run, so `probe context-sync` works on a machine with no
Chrome installed. Target rules, guard and reporting are identical either way:
one suite, one runner, with the browser as an ingredient rather than the frame.
`ctx.browser` is nullable so that a browserless probe reaching for it fails at
`dart analyze` rather than at the moment it clicks; `ctx.newPage()` and
`ctx.closePage()` raise an error naming the declaration instead.
