# Capability map — `tools/probe-*.mjs` → `appbox design probe`

Full audit of every studio probe (`tools/probe-*.mjs` + the shared
`tools/_probe_base.mjs`) against the Dart harness — `appboxd/lib/probes/` over
`appboxd/lib/cdp.dart`, dispatched by `appbox design probe <name…|all>`.

This map is the audit trail for the retirement: no `.mjs` file is archived
until its row here says where every one of its sections went. A section that is
not ported gets a written reason, not silence.

Status legend:

- **ported** — the section runs in Dart and agrees with the `.mjs` original on
  the same served tree.
- **ported (partial: …)** — landed with a recorded ceiling, named in the row.
- **dropped** — not ported, with a one-line reason.
- **pending** — not yet attempted (wave C).

## Harness — `tools/_probe_base.mjs` → `appboxd/lib/probes/probe_base.dart`

| `_probe_base.mjs` export | Dart | status |
|---|---|---|
| `resolveBase(argv)` | `resolveTarget(args, env:)` → `ProbeTarget` (`probe_base.dart`) | ported — all three rules; pure, so `test/probe_base_test.dart` covers them without a subprocess |
| `requireDisposableProject(base)` | `disposableVerdict(json, base)` + `checkDisposableProject(base)` | ported — reads `boundProject`, never `current` |
| `waitFor(page, fn, {timeout,label})` | `probeWaitFor(session, expr, label:)` over `CdpSession.waitForFunction` | ported — returns false and reports, never throws; drains `__vtBusy` after the condition holds |
| `waitQuiet(page, {quietMs,timeout})` | `waitQuiet(session, quietMs:, timeoutMs:)` | ported — same two-identical-samples rule, same `count:length` sample |
| `trackTransitions(page)` | `trackTransitions(session)` over `CdpSession.addInitScript` | ported — same `__hxSettled` / `__vtBusy` counters, same skipped-transition settle |
| `ck(name, ok, extra)` | `ProbeReport.check(name, ok, [detail])` | ported — byte-identical line shape, asserted in `probe_base_test.dart` |
| suite trailer | `ProbeReport.finish()` | ported — `==== ALL PASSED ====` / `==== N FAILED ====`, exit 1 on any fail |

### Verbs added to `cdp.dart` for the harness

Per the plan's "gaps go into cdp.dart, not around it". All additive; no
existing method changed, so `lens.dart` / `gate_lens.dart` are untouched.

| verb | why it had to be in the engine |
|---|---|
| `waitForFunction(expr, {timeout, polling})` | condition polling with a bounded timeout — the engine had only `navigateAndSettle`'s fixed `Future.delayed` |
| `waitForSelector(sel, {timeout, visible})` | presence/visibility wait; `clickSelector`'s precondition |
| `hover(x, y)` | pointer arrival without a press; `:hover` reveals act on it |
| `clickSelector(sel, {timeout, synthetic})` | click by selector. **Hover-then-click is the uniform default, not an option** — CDP has no equivalent of Playwright's actionability checks, and several studio controls are `:hover`-revealed. The element box is re-measured *after* the hover, because revealing a rail shifts layout and the pre-hover centre can point at something else by press time. `synthetic` dispatches the element's own `click()` for controls no pointer can reach |
| `drag(fromX, fromY, toX, toY, {steps = 14})` | press → N interpolated moves → release. `steps` is a correctness knob, not smoothness: a two-point drag is invisible to drag-threshold detection, so a resize probe built on one reports a working divider broken. Default matches what the studio's resize interactions were tuned against |
| `dragSelector(sel, {dx, dy, steps})` | the same, from an element's centre by a delta |
| `fillSelector(sel, value)` | set value **and** fire `input`/`change` — assigning `.value` alone is invisible to htmx and `hx-preserve` |
| `computedStyle(sel, props)` | computed-style read, null when the element is absent |
| `getResponseBody(requestId)` | one body by id; null when Chrome no longer has it |
| `recordNetworkBodies()` → `CdpNetworkBodies` | bodies captured on `Network.loadingFinished` — the earliest moment one exists and the latest it is guaranteed to. Collecting events and fetching bodies at the end is the obvious shape and the broken one: the page has navigated by then and the buffer is dropped, so the bodies that matter are exactly the missing ones. Records carry `encodedLength` (wire bytes) alongside the body, since a payload-size assertion wants the former and `body.length` is post-decompression |
| `addInitScript(source)` | `Page.addScriptToEvaluateOnNewDocument`; `trackTransitions` cannot exist without it |

**Not added**: iframe/frame piercing. No ported probe needs it yet and its shape
is not yet specified; `inspect`/`explode` in wave C are the likely first callers.
(Drag was on this list until wave A2's inventory specified it — `steps: 14` from
`panel-resize` — at which point it stopped being speculative and went in.)

## Probes

| `.mjs` probe | sections | Dart module | status |
|---|---|---|---|
| `probe-composer-draft.mjs` | 2 shells × 2 checks: draft survives an unrelated swap; textarea clears after send | `probe_composer_draft.dart` (`composer-draft`) | **ported** — see parity evidence below |
| `probe-panel-contract.mjs` | 12 | — | pending (wave C) |
| `probe-panel-resize.mjs` | — | — | pending (wave C) |
| `probe-shell-chrome.mjs` | — | — | pending (wave C) |
| `probe-no-reload.mjs` | — | — | pending (wave C) |
| `probe-boost.mjs` | — | — | pending (wave C) |
| `probe-context-sync.mjs` | — | — | pending (wave C) |
| `probe-inspect.mjs` | — | — | pending (wave C) |
| `probe-explode.mjs` | — | — | pending (wave C) |
| `probe-flowwalk.mjs` | — | — | pending (wave C) |

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
