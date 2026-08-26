# answers.json as the flows SSOT, + canvas undo/redo in the design shell

Closes task #30 and fills the `chrome.actions` slot left empty by
`docs/plans/views-explode-lens-interflow-and-shell-panels.md`.

Settled by grill, 2026-08-02. Six decisions, all confirmed.

> **Note (2026-08-05).** The `probe-explode.mjs` checks cited below were
> archived to `archives/tooling-pre-dart/` (2026-08-03, `97df1b5`), and their
> Dart successor `probe_explode.dart` was deleted with the views-lens
> components container (`7babc79`); the hand-off/feedback assertions live on
> in `probe_flowwalk.dart` §E. `explode.js` is likewise deleted (ADR-0002
> amendment 2026-08-05).

---

## The premise #30 was written on was wrong

Task #30 said "six write sites, re-emit overwrites rather than merges." The code
does not support that:

| Claimed | Actual |
|---|---|
| `writeFlows` ×4 `design_facade`, ×2 `intake_facade` | 4 in `design_facade`; **0** in `intake_facade` (it calls `writeProjectFixture` directly — 2 sites) |
| those sites overwrite | all 6 are **read-modify-write** on the current file — none clobber |
| — | the **only** clobbering write is `IntakeEngine.emit` (`intake_cli.dart:132`), reachable only from `arxa intake emit`. The studio never shells out to it. |

So there is no clobber in the studio. There is a **drift**: the studio writes
`flows.json` and never writes back to `answers.json`, so the two files have
diverged and a legitimate re-emit would revert the newer one.

---

## D1 — `emit` stays a pure function of `answers.json`

`DESIGN-ARCHITECTURE.md:29` already binds this: *"identical answers produce a
byte-identical registry, flows, and seeds."* A merge inside `emit` would make
its output depend on prior file state, so the merge option is excluded by a
documented invariant, not by preference.

`answers.json` is the SSOT. `flows.json` is a pure emit. **No change to
`intake.dart`'s emit path.**

## D2 — the studio dual-writes

Each site that mutates flows writes the same array to **both** files.

New helper in `services/repositories/project_repository.js`:

```js
export const writeAnswers = (answers) => writeProjectFixture('intake/answers.json', answers);
```

**This is byte-identical by construction**, verified against the three
transforms in `emitFlows`:

- the **spread** (`...(e as Map).cast<String, dynamic>()`) copies every authored
  key in authored order;
- `'action': e['action'] ?? 'push'` re-assigns an *existing* key, so it keeps its
  position;
- `_edgeFeedback` only fires when nothing is declared — a dual-write declares it.

So `emitFlows(answers)` reproduces exactly what the studio wrote. **No JS
reimplementation of emit rules. No second validator.**

### Sites (7, not 6)

| # | File | Function |
|---|---|---|
| 1 | `design_facade.js:234` | `applyEntry` (undo/redo replay) |
| 2 | `design_facade.js:758` | `moveInFlow` |
| 3 | `design_facade.js:773` | `addToFlow` |
| 4 | `design_facade.js:790` | `removeFromFlow` |
| 5 | `intake_facade.js:~610` | `confirmFlowProvenance` |
| 6 | `intake_facade.js:~620` | `confirmAllFlows` |
| 7 | **`arxa/lib/intake.dart:1031`** | **`IntakeEngine.confirmFlow`** — writes `flows.json` only. Under D4 this makes `arxa intake flows confirm` turn the gate red. Dual-write here too. |

Site 7 was not in #30's list and is the one a Dart-side reader would miss.

## D3 — guard the one operation that can write `answers.json` invalid

`intake.dart:269` is a hard stop:

```dart
if (edges is! List || edges.isEmpty)
  errs.add('$where: edges must be a non-empty list (a flow is a chain)');
```

`excise` on a 2-screen flow produces exactly that (`incoming` or `outgoing` is
null → `stitch = []`, `rest = []` → `flow.edges = []`). Harmless in `flows.json`
today because nothing validates it live. Under D2 it reaches `answers.json`,
`validateIntake` fails, and `emit` returns `EmitResult.failure` **before any
`_write`** — the project's intake is bricked until the file is hand-repaired.

Audited every other operation; none can produce an invalid answers file:

| op | worst case | verdict |
|---|---|---|
| `moveInFlow` → `rewire` | rebuilds pairwise from a chain of unique ids | count preserved, still linear |
| `addToFlow` → `appendTo` | refuses on `chain.includes(id)` or empty chain | +1 edge, no dup incoming |
| `removeFromFlow` → `excise` | **2-screen flow → `edges: []`** | **the only hole** |
| `confirmFlowProvenance` / `confirmAllFlows` | `inferred` → `founder` | both in the enum |
| `applyEntry` undo/redo | replays the above | inherits their guarantees |

**Fix:** refuse the removal when the **post-excise edge count would be 0**.

Write the guard against the *outcome*, not the precondition. "The flow has ≤1
edge" is a different condition: it also blocks removing a screen that isn't in
the flow at all (harmless — `excise` already returns `null`), and it reads as if
edge count alone decides, which invites a future 3-edge case to be mis-reasoned.
The predicate is one helper; the `disabled` attribute in `design_viewer.html`
derives from that same helper rather than duplicating `chain.length <= 2` in the
template.

Rejected: porting `validateIntake` to JS. It would guard four failures the code
cannot produce and add a third copy of a contract whose drift is already a scar
(`intake.schema.json`'s own `edge` description documents the last one).

Side effect worth having: it closes a pre-existing dead-end. A flow at 0 edges
can never be refilled today, because `appendTo` bails on `!chain.length`. Under
this guard that state becomes unreachable rather than needing a repair path.

## D4 — one check in `arxa gate intake`

`gate_intake.dart` (323 lines) already resolves both project paths and already
takes `--project`. It does **not** read `flows.json` at all. That gap is the
natural home.

**Check:** when both files exist, `flows.json` must equal `emitFlows(answers)`
— **compared structurally, not byte-for-byte.**

Byte comparison would flap. D2's byte-identity argument covers the *emitter*
preserving authored key order, but the studio's mutators build fresh edge
objects with their own order: `excise`'s stitch emits
`{from, to, trigger, action, element}` and `appendTo` emits
`{from, to, trigger, action}`. Once D4's repair writes an edge in one order and
a later `excise` rewrites it in another, the spread faithfully preserves the
*new* order and a byte compare goes red on two semantically identical files.
Compare parsed structures.

**It is red-first for free.** Portalo's files diverge today:

| edge | `answers.json` | `flows.json` |
|---|---|---|
| `auth→home` | `"Sign-in success"` / `system` | `"continue"` / `push` / `element` |
| `checkout→orders` | `"Order placed"` / `replace` | `"Track your order"` / `push` |
| `product→cart`, `cart→checkout` | — | `feedback` blocks |

So the check goes red on real data on its first run, then green after the repair.
That is proof the check works, not just that it compiles.

**Repair scope is one project.** `~/.arxa/projects/` holds `foxglove-demo` and
`portalo`; only portalo has both files. One `POST /__project_write` of
`answers.json` with the flows array back-propagated. **No new `arxa intake
adopt` command.**

Direction: **`flows.json` → `answers.json`**. `flows.json` is the newer truth
(corrected chain, `element`, both toasts). Running `arxa intake emit` to
reconcile would revert all of it — the exact destruction #30 was opened about.

## D5 — the auth edge: `flows.json` wins whole

`portalo.auth → portalo.home` disagrees on meaning, not wording. The schema
defines `system` as *"non-gesture edge … **never a button**"*, so
`action: system` + `element: "button:Continue"` is self-contradictory. A
two-edge split is **illegal** — `_validateFlows` rejects a second outgoing edge
per screen.

Resolution: `"continue"` / `push` / `element: "button:Continue"`.

It is the only reading that matches what the screen renders. `probe-explode.mjs`
passes green today on two assertions the alternative breaks:
`[data-el="button:Continue"]` resolves in the auth iframe, and the explode lens
reads `fires: Onboarding → portalo.home` off it. Under `action: system` the flow
walk loses its exact match, falls back to fuzzy-matching `"Sign-in success"`
against the DOM, hits nothing, and the walk stalls at auth.

`system` is defensible as *product* truth. The prototype does not model real
auth — it models a Continue button. Encoding an intent the artifact does not
implement is how these two files diverged in the first place.

## D6 — `chrome.actions` = canvas undo + redo, nothing else

Exclusion zone (anything here is the wrong layer):

| Layer | Owns |
|---|---|
| hover toolbar (per tile) | pin · inspect · flow-mode · move earlier/later · remove-from-flow · add-to-flow; in flow mode: advance · close |
| mini panel (bottom bar) | lens tabs · bg swatches · fullscreen exit |
| composer | **chat** undo/redo · model menu |

**Canvas undo/redo is fully built and has no button:**

- `design_facade.js:522` computes `undoRedo.canvas.{canUndo, canRedo}` —
  rendered nowhere
- `routes.design.js:24-25` route `POST /design/undo/:stack` and `/redo/:stack`
- `facade.undo`/`facade.redo` (`:824`/`:836`) accept `stack`
- `composer.html:112` hardcodes `/design/undo/`**`chat`**

Every flow edit from the last slice — move, add, remove, plus `rewire`'s
per-screen trigger snapshot and `excise`/`restore`'s verbatim edge memory —
pushes onto a stack nobody can pop. This is not a naming exercise; it is
finishing a wire that already runs end to end.

Two entries in the slot, `hx-post` to `/design/undo/canvas` and
`/design/redo/canvas`, disabled off the flags already in the viewmodel. Reuse
`miniPanel.undo` / `miniPanel.redo` — no new l10n keys.

### D6 is blocked by a regression I shipped in Slice 5

**The top panel vanishes on a lens switch.** A mini-panel lens tab
(`mini_panel.html:71`) does `hx-get` → `GET /design/viewer` →
`prototype_viewmodel.js:38` renders `#viewerSwap` →
`prototype_view.html:65` is `{% macro viewerSwap(c) %}{{ dv.designViewer(c.viewer) }}{% endmacro %}`
— **one argument. No `chrome`.** `design_viewer.html:227` guards the whole
`<header class="dv-topbar">` on `{% if chrome %}`, so it morphs away.

Blast radius is the topbar only. `.dv-botbar` (`:349`) is unguarded, so the mini
panel, lens tabs, bg swatches and fullscreen exit survive; only the title, the
status pill, and — once D6 lands — the undo/redo buttons disappear. Undo would
work exactly once per lens switch.

`probe-explode.mjs` misses it by construction: section C performs the swap but
only asserts hand-offs and feedback, then section D re-navigates to `/design`
fresh before checking panels — i.e. it checks the panels only in the one state
where they are guaranteed present.

**Fix before D6:** build the `chrome` object once and pass it from both
fragments. It is currently assembled inline at `prototype_view.html:32` from
`c.counts`, `c.run.state` and `t('protoFoot')`; verify the `viewer` handler's
context carries those before deciding whether it moves into the viewmodel or
into a macro.

**Probe must assert the disabled direction too.** `facade.undo` renders
`${VIEW}#panelsSwap`, and `panelsSwap` → `panels(c)` → the `designViewer(…, {…})`
call at `:32`, so the topbar *is* inside that fragment and disabled state does
update for free. But "enabled after an edit" passes even when the state is
stale — assert **disabled after undoing back to an empty stack** as well.

**Delete `is-danger`.** `grep is-danger designs/arxa-studio/assets/css/*.css`
returns zero hits — the template branches on a class that styles nothing.
Neither undo nor redo is destructive. Delete the branch rather than invent a
destructive action to justify it.

Rejected: export, open-in-new-tab, re-emit. Re-emit in particular becomes a
**no-op by construction** under D1+D4 — a button for it would do nothing
observable.

---

## Red-first proof per decision

| D | The check that must go red before the fix |
|---|---|
| D2 | new gate check (D4) red on portalo; green after repair |
| D3 | dart test: `validateIntake` on an answers doc with `edges: []` → the non-empty error. Then a JS check that `removeFromFlow` on a 1-edge flow leaves the file unchanged. |
| D4 | run the gate against portalo before the repair |
| D5 | `probe-explode.mjs` already asserts both halves; it must stay green through the repair |
| D6 | probe: `.dv-topbar` contains two enabled-after-an-edit history buttons posting to `/canvas`, not `/chat` |

---

# D7+ — inspection coverage, state views, the inspector pane

Second grill, same session. **D1–D6 are settled and dispatched as tasks #32–#36;
this section is additive and must not renumber them.**

## D7 — inspection coverage bar: C, with a B toggle

Measured coverage today, portalo (12 surfaces, 32 annotations):

| surface | annotated / text-bearing candidates |
|---|---|
| home | **1 / ~11** |
| category | 2 / ~7 |
| checkout, account | 4 / ~8 |
| product, cart, auth, orders | 5 / ~6–11 |
| splash, startup | 0 / ~3 |

The rule that permits this is `design_tools.dart:107`:

```dart
if (interactive > 0 && annotated == 0)
```

**The coverage bar is literally "at least one."** `home.html` passes with 1
annotation on 11 elements.

`_interactiveRe` (`<a href` | `<button`) cannot be the tightened predicate: the
prefix vocabulary already in use is `button` 9 · `card` 6 · `hero` 5 ·
`summary` 4 · `list-row` 2 · `tab` · `row` · `nav` · `media` · `list` · `field`
— roughly 20 of 32 are **content**, not interactive. The reported gap
(`Free shipping · 30-day returns`, `product.html:40`) is a bare `<p class="muted">`
and an interactive-only rule would never catch it.

**Decision: C** — every element rendering a leaf text node or icon —
**with a toggle to B** (interactive + text-bearing block whitelist).

The toggle lives in the **mini panel under an `advanced` flag**, built as a
**reusable advanced-flags slot** for later features, not a one-off checkbox.

## D8 — the designer GENERATES annotations, lint enforces

C-level coverage is ~150 annotations × 4 attributes ≈ 600 hand-written
attributes for portalo alone. Enforce-only makes every future surface ~4× the
markup.

`arxa-designer` emits `data-el` + `data-inspect-role` + `-style` + `-fn`
deterministically from tag, text and class; hand-authored values win where
present; lint verifies.

Rejected: generating at **render** time in the stub renderer. It breaks the
`element` join — `flows.json` edges point at `data-el` values and
`emit_structure.dart:100` validates them; values that exist only post-render
cannot be referenced upstream.

## D9 — derived `data-inspect-fn` carries an inferred marker

`fn` is prose ("Explains the material and care details for this piece"). `role`,
`style` and `data-el` are mechanical; `fn` is not.

The generator emits all four. A derived `fn` is **marked inferred**; lint
reports it; the inspector shows it as unconfirmed.

This is not a new pattern — it is the house *derive + confirm* pattern, already
used three times: `_edgeFeedback` stamps `inferred: true`, derived flows get
`provenance: 'inferred'`, `emitRegistry` carries `statesProvenance`. Emitting
unmarked prose would be the §22 violation that `element` was deliberately kept
away from.

Bonus: the marker gives D7's advanced toggle something to filter on —
"show only unconfirmed annotations" falls out for free.

## D10 — state views are a `?state=` variant of the SAME surface file

Portalo declares **12 state variants across 8 screens** and nothing renders any:
`startup` loading · `auth` error · `home` loading+empty · `category`
loading+empty · `product` loading+error · `cart` empty · `checkout`
loading+error · `orders` empty.

**Decision: a query param on the existing surface** — `product.html?state=loading`
swaps the affected regions.

**This is a universal arxa-designer rule, not a portalo repair.** Every app
the designer produces must render every state its registry declares. That makes
it three artefacts, not one:

1. the designer **emits** the `{% if state == … %}` regions for each declared state
2. a **lint rule** fails a surface whose registry entry declares a state it has
   no branch for (and vice versa — an orphan branch)
3. the **skill docs** state the rule so intake never has to ask for it

Rejected, with reasons:

- **Separate files** (`product.loading.html`): duplicates the base markup 12×,
  so every `data-el` annotation duplicates too — under D7's coverage bar that is
  ~150 → ~350 annotations with no sync mechanism, and base edits silently skip
  the variants.
- **Viewer-side overlay**: bypasses annotated markup entirely, so state views
  would have **zero** inspectable elements — reintroducing the exact gap D7
  exists to close. It also cannot feed the build: `kit/state` is a real Flutter
  kit and a studio-drawn skeleton describes nothing the generator consumes.

Cost, stated honestly: surface files gain conditional regions, so `product.html`
grows a branch around its content area. That is real complexity in a
human-authored file — paid **once per screen**, against the separate-file
option's duplication paid **12 times**.

Existing mechanism, no new transport: the tile iframe src is already
`…?vp={vp}&embed=1&still=1&inspect=1`. `&state=loading` is the same channel.

## D11 — toast renders on the DESTINATION surface via `?toast=`

`feedback` is on the edge, so a toast is not a state variant. The flow walk
appends `?toast=` when it takes an edge carrying feedback; the destination
renders it. The schema's own wording picks the end — *"a consequence of moving"*
— so it belongs where you land.

Same three artefacts as D10 (designer emits the region, lint checks it, docs
state it). That is what makes "users don't think about it during intake" true
rather than aspirational.

Constraints from [Material](https://m2.material.io/design/components/snackbars.html):
one at a time · single line · no icons · auto-dismiss ~4s · `aria-live` ·
Escape dismisses · **positioned above bottom navigation** (portalo has a tab
bar, so this is live) · a fatal error is a dialog or inline message, **never** a
toast — which is exactly the screen-`error`-state vs edge-`feedback` split.

## D12 — `states` derived from kits; authored wins; derived marked inferred

Measured: **7 of 10 portalo screens under-declare**, and `account` declares none
despite two kits.

| screen | kits imply | declared | gap |
|---|---|---|---|
| home, category | loading, empty, error | loading, empty | **error** |
| product, checkout | loading, empty, error | loading, error | **empty** |
| cart, orders | loading, empty, error | empty | **loading, error** |
| account | loading, empty, error | **none** | **all three** |
| startup | *(no kits)* | loading | declares *more* than derived |

The `startup` row is why derivation cannot be total: it declares a correct
`loading` that no kit implies, and pure derivation would silently delete it.

The kit→state map becomes a **published artefact** in `kit-catalog.md` beside
the 24-kit table, so intake, designer and lint read one source. **No such map is
documented anywhere today** (zero hits).

Also fix the drift found here: `surfaceStates` is closed in Dart
(`intake.dart:59`) and **open** in the schema (`"items": {"type": "string"}`) —
the same contract-pair scar as `edgeKeys`.

## D13 — retry is an affordance, not a fourth state

`states` is *a way a screen can look*; a retry button is a control and a pull is
a gesture. `surfaceStates` stays `['loading','empty','error']`.

`AdaptiveRefresh` already exists (`blueprint.dart:2230`, wrapping
`RefreshIndicator.adaptive`). `retry`/`onRetry`/`AsyncValue` appear **nowhere**
in blueprint — pull-to-refresh has a widget, retry-after-error has nothing.

Three lint rules, the third of which came from research and I had missed:

1. an `error` region with no retry control fails
2. an async screen with no refresh wrapper fails
3. **`error` and `empty` regions must be scrollable** — `RefreshIndicator` cannot
   detect a pull gesture otherwise, so users cannot pull-to-refresh out of the
   very states where they most need to

Two retry affordances are required in the error state, not one: the pull gesture
**and** an explicit button, because the pull is not discoverable on an error
screen.

Two further findings that constrain the emitted markup:

- `AsyncValue` models **three** states (loading/error/data); `empty` is
  `data + isEmpty`, **not a peer**. The designer emits `empty` *inside* the data
  branch.
- **A refresh is not the loading state** (`skipLoadingOnRefresh: true`, else
  pull-to-refresh flashes a full-screen spinner). `?state=loading` is first-load
  only.

## D14 — inspector pane: hover previews, click locks, click again releases

B (both retarget, no lock) is unusable **by geometry**, not by preference: the
activity panel is on the left and the artboards are in the middle, so the
pointer path from a tile to the pane crosses other annotated elements and would
rewrite the pane several times en route.

Corroborated by the Adobe XD cautionary case — *"when you double-click a
component, the state picker Property Inspector disappears"* — which is task #36
with different nouns.

Locked is a **visible** state on the pane, never an invisible mode.

## D15 — click LOCKS; the pin moves into the pane

Click currently pins to composer context (`inspect.js:139` POSTs
`/design/chat/context/element`). Leaving pin on click means one gesture does two
things and users pin elements merely to read them, polluting the very context
the name-chip mirrors. Pin becomes its own control on the pane.

The on-screen overlay reduces to the element name alone — **verified as a pure
deletion of `inspect.js:84–95`**: `inspect.js:136` sends `name = el.dataset.el`
and `composer.html:79` renders `{{ el.name }}` verbatim, so the overlay and the
composer chip are already the same string.

## D16 — server holds the SELECTION, the island re-derives the CONTENT

Server-rendering the card is **impossible**, not merely undesirable:
`data-el="hero:{{ t('portalo.product.aurelia') }}"` is unresolved server-side
and per-locale. That is the same wall that forced `explode.js` to read the
rendered DOM; `data-inspect-role/style/fn` have the same shape.

So: session stores `{screenId, name}` (the shape `elementContext`,
`activityView`, `panelSize` and `inspect` already use); the island re-fills from
the iframe DOM after every swap. The lock survives the `#panels` morph that a
pin or an undo triggers.

**Costs a second ADR-0002 amendment.** `inspect.js` runs *inside* the stub
document and the pane is in the *parent*, so filling it means
`window.parent.document.querySelector('#panel-left-body')` — a **child-side
island writing the parent's DOM**. ADR-0002 documents `explode.js` as the first
*parent-side* island reading a *child's* DOM; this is the inverse direction and
is not covered. Two boundary crossings in one week on a boundary whose point is
being crossed rarely and namedly — accepted, because the alternative is a lock
that evaporates whenever anything else on the page updates, which is not a lock.

Pane mechanism: `design_facade.js:603` gates `activityView` to
`['screens','artifacts','files']` and `:628` builds the carousel
(`href: /design/panel/${id}`, hx-swaps `#panel-left-body`). A fourth pane is an
entry in that set, a route, and a fragment — the frame already refreshes head
and bar out-of-band.

## D17 — the screen-level card

Declared **and** derived `states` with `inferred` marks · kits · outgoing edges
with their feedback · missing-state warnings from D12's kit map · annotation
coverage (`n/m`, unconfirmed count).

From design-system guidance: *"label properties with the same names the code
library uses so hover-inspect doubles as documentation"* — which is why `data-el`
prefixes align to kit vocabulary. And *"route every panel edit through the undo
stack"* — if the card ever gains edit controls they go through
`pushCanvasUndo`, never a direct write.

## D18 — `feedback` gains an `action`

Material treats the action as the defining feature of a snackbar — *"ideally
with an Undo/Retry action"*. The schema has `{kind, text, inferred}` and **no
action slot**.

`{kind, text, action?, inferred}`. Contract-pair change: `intake.schema.json`
**and** `feedbackKeys` in `intake.dart`, changed together.

Note the correction this supersedes: narrowing `kind` to `success|info` was
**wrong** — recoverable errors are core snackbar material. The incoherence
argument only held for the edge axis, and the real defect it exposed was the
missing action, not the enum.

## D19 — the arxa error manager (HTML+JS and Dart/Flutter)

**Most of the Flutter half already exists** — this is a consolidation and a
taxonomy, not a green-field build.

Already present in `blueprint.dart`:

| what | where |
|---|---|
| feedback dispatcher — `error(msg)` / `success(msg)` → `_show(msg, isError:)` | `:589–599` |
| `showAdaptiveToast` — ShadToaster on shadcn, Material elsewhere | `:2398–2440` |
| inline field error (`errorText`), VM-driven, strategy-dependent render | `:1584–1620` |
| `AdaptiveRefresh` | `:2230` |
| the standing rule: **"a HUMAN message — never a raw error object (the bad-state leak)"** | `:589`, `:2398` |

So Flutter already has **three** error placements — inline field · screen state ·
toast — which is the taxonomy, undocumented. Writing it down is most of the work.

Two real gaps found:

1. **Kind drift.** `feedbackKinds = ['success','error','info']` (intake) vs
   blueprint's boolean `isError`. The design layer permits `info` that the
   Flutter layer **cannot render**. Reconcile in the same change as D18.
2. **The studio's HTML+JS half fails silently.** `base.html:10` htmx-config sets
   `{"code":"[45]..","swap":false,"error":true}` — 4xx/5xx are flagged as errors
   and deliberately not swapped. `422` swaps, so validation renders. But there
   is **no error surface and no 500 page** anywhere in the studio
   (`find -iname '*error*'` returns font files only). A failed request today
   produces no swap and no message: nothing at all.

Scope, since "related actors" is broad: the manager is a **published contract**
(placement taxonomy + the human-message rule + the kind enum) that
`arxa-designer` emits against, `arxa-lint` enforces, `arxa-scaffolder`
and `arxa-builder` consume via the kits, and `arxa-reviewer`/`arxa-tester`
check. `kit/core` already owns *"error/theme services"* and `kit/state` owns
*"async state vocabulary (idle/loading/error); retry policy"* — the kit update
is to expose them against the written taxonomy, not to invent a service.

`_kFeedbackError = Color(0xFFE53935)` is a ponytail-marked literal because no
semantic danger token is compiled. A taxonomy with typed severities needs that
token — flag it, don't silently keep the literal.

---

## Not in scope

- Task #31 (two Chrome flakes under parallel test load) — unrelated.
- Task #6 Slice B (story-mapper + moodboarder wiring) — pre-existing.

---

# Execution log — 2026-08-02

Built by an 8-way fan-out. Rollback point: git tag `pre-fanout`
(`cd1892c9`), plus the untracked files and a full portalo copy in the
session scratchpad.

## What the build refuted

Four things in the sections above turned out to be wrong once measured. They
are corrected in place; recorded here so the corrections aren't re-litigated.

1. **D6's routes already existed.** `POST /design/undo/:stack` and
   `/design/redo/:stack` were live at `routes.design.js:24-25` with handlers at
   `prototype_viewmodel.js:71-75` — the mini panel had been posting to them all
   along. D6 was render-side only; no route was added.

2. **The #36 defect was broader than measured.** `.dv-botbar-foot`
   (`design_viewer.html:357`) is `{% if chrome and chrome.foot %}`-guarded, so
   the foot line vanished on every swap too. Only the `<footer>` element is
   unguarded, which is why the bottom bar *looked* intact. One fix covers both.

3. **Two of the predicted portalo divergences do not exist.** `product→cart`
   and `cart→checkout` genuinely agree: `deriveFeedback` fires on the mutation
   words `add`/`checkout` and produces an identical
   `{kind:'success', text:<trigger>, inferred:true}` on both sides. The real
   divergence list was `flow-onboarding` edge 2 (action/element/trigger) and
   `flow-browse-buy` edge 4 (action/trigger) — five, not the predicted set.

4. **D16 costs no second ADR-0002 amendment.** `inspect.js:139-161` already
   POSTs client-measured data to a parent endpoint and then fires
   `p.htmx.ajax` against the parent. The templated-`data-el` wall stops the
   server *deriving* element metadata; it does not stop it *rendering*
   metadata the client measured and sent. So the pane is server-rendered from
   a POSTed payload joined with registry/flows — no new island, no amendment.
   Two agents reached this independently.

## The gap this work exposed

D10/D11 make the designer contractually responsible for placing loading /
error / retry / toast automatically in every app it designs. That contract now
has a lint (`design_tools.dart`), a written taxonomy (arxa-designer), and a
Flutter renderer (`blueprint.dart`) — **but no emission point**:

- `blueprint.dart:2715` `_tplView` emits only
  `body: const Center(child: Text(name))` behind `@arxa-extension-point` +
  `TODO(builder)`.
- `_tplViewModel` emits a bare `BaseViewModel` with **no `refresh` method**, so
  a generated retry button has nothing to call.
- `AdaptiveRefresh` (`:2230`) has exactly **one** call site repo-wide:
  `generate_view.dart:497`.

`_tplFeedbackService()` returns a generated source string with `$genMarker`, so
these are unambiguously generator templates — the absence is in what gets
generated, not in an unpolished helper. Writing the contract did not make it
fire. Tracked as its own task.

## Verified vs unverified

Verified this session: `dart analyze lib/` clean; 263 tests pass across the
eight touched files; the one failure
(`design_server_test.dart: serving (Chrome worker) (setUpAll)`) re-ran clean
twice in isolation and is task #31's parallel-load flake; `is-danger` has zero
occurrences studio-wide; `canRemoveFrom` is one helper behind all five call
sites; both viewer render paths call one `stageViewer` macro.

Verified in a browser by an independent pass, against a **fresh** server on a
dedicated port (not the shared long-lived instance, which serves stale code):
the inspector pane's full D14–D17 behaviour — arm, hover preview, click-locks,
locked-wins, the lock surviving a whole panel morph as session state, pin
adding a chat chip without reloading the iframe, unlock falling back to last
hover, and the 204 no-op when the pane isn't active. `probe-explode`,
`probe-flowwalk` and `probe-shell-chrome` all pass against that instance.

D17's screen card shipped **unreachable** and was then fixed. `inspectorFor`
chose `element ? null : screenCardFor(...)`, but `inspectorScreenId` had a
single write site inside `selectElement`, which always set a hover name in the
same call — so `element` was never null when the id was set, and the branch was
dead code. Fixed by threading the viewer's already-computed `active` screen in
as a fallback (`d.inspectorScreenId ?? fallbackScreenId ?? null`), so the card
renders the moment the pane opens rather than only "between hovers". Reusing
`viewer.active` matters: deriving a second notion of "current screen" would
have been a fresh way for the pane and the canvas to disagree. 22/22 checks.

**Still unverified in a browser:** the OOB error surface. Everything else
browser-facing has now been exercised.

**The probe failures are a timing race, not state contamination.** Two wrong
theories were built and discarded here; the sequence is worth keeping because
both were plausible and both were refuted by cheap evidence.

- *Wrong theory 1 (chained-probe session contamination).* Refuted: `_sessions`
  is keyed per `kdh_sid` (`design_server.dart:191`, `:407-412`, `:437`) and
  every `chromium.launch()` gets a fresh cookie jar, so separate probe
  processes never share a session.
- *Wrong theory 2, stated here as "established" and now withdrawn
  (hot-reload staleness).* The claim was that `_sessions`, a `final` instance
  field of the Dart `DesignServer`, survives a JS **worker** reload, so a
  session shaped by old code is read by new. Refuted by two observations it
  cannot explain: the failure **reproduces on a cold boot**, and it is
  **non-deterministic** — one failure followed by two clean passes on the same
  untouched server. State contamination is deterministic for a given sequence.
- *`_timers` — ruled out as the cause here, but it is a REAL latent vector.*
  An earlier note in this file called it dead code. **That was wrong**, and the
  error is instructive: the grep behind it covered only the studio's facades
  and viewmodels and missed `worker_shim.js:116-118` → `lib/timers.mjs`. It has
  three call sites. Unlike `_sessions` it is genuinely **global and unscoped** —
  `design_server.dart:421` hands `Map<String, dynamic>.from(_timers)` to every
  request regardless of `sid`, and `:429-431` clears and refills it wholesale
  from the response. It carries toast/notification bookkeeping, structurally
  unrelated to the undo/redo stacks these probes assert (those live in
  per-session `_sessions`), so it does not explain this failure — but it will
  bite the first time a probe asserts timer-derived state across a chain. Its
  own ticket. *"Ruled out by use, not shape" was the right method; the grep was
  simply too narrow, which is the failure mode that method invites.*

**THE EVIDENCE BELOW IS COMPROMISED — read this first.** Every probe in
`tools/` resolves its target as `process.env.ARXA_BASE || 'http://localhost:4319'`
and **none of them reads `process.argv`**. So every `--port NNNN` passed while
investigating this was a silent no-op, and runs believed to be hitting isolated
cold-booted servers were hitting the shared long-lived 4319 instead. The
"cold boot, 1 failure in 6" figure — the single fact that discriminated between
the two hypotheses — cannot be trusted. **Root cause is therefore UNPROVEN, not
settled.** It is recorded below because the reasoning is sound *if* the
measurement holds; it must be re-measured with `ARXA_BASE` set explicitly and
the resolved base printed before any conclusion is drawn from it.

What survives regardless, because it is a property of the code rather than of
any run: `probe-shell-chrome.mjs:140-144` really does `waitForTimeout(1400)`
then read synchronously, which is a latent race whatever server it points at;
the same shape is suite-wide; and the fix (`waitForFunction` on the real
condition, bounded timeout) is correct on those grounds alone.

A flag that looks supported and is silently ignored is worse than no flag. The
probes should accept `--port`/`--base`, print the resolved base at startup, and
hard-error on an argument they cannot honour.

**Candidate cause (unproven): a fixed delay racing variable server latency.**
`probe-shell-chrome.mjs:140-144` clicks undo, waits a bare
`waitForTimeout(1400)`, then reads `.dv-shell-act[1].disabled` synchronously.
`facade.undo` is async and performs a file write; under load (observed 3.5 load
average, 19 concurrent chrome+dart processes) the POST and morph exceed 1400ms
and the assertion reads mid-transition. Hot-reload only ever made it *more
likely*, by adding latency. The same fixed-timeout-then-read shape is
suite-wide — flowwalk, boost, explode, composer-draft, inspect.

Fix is `page.waitForFunction` on the real condition with a **bounded** timeout:
the goal is to stop reading mid-transition, not to wait forever — an unbounded
wait converts a real regression into a hang.

**Open hypothesis:** task #31 is titled "flakes under parallel test **load**".
The variable here is load. #31, #48 and #50 may be one class.

**The corollary that cuts hardest:** a probe run that PASSES on an idle machine
is weaker evidence than it reads as, because the race hides. Several "all
checks passed" results recorded during this work were taken on an unloaded
machine. That does not make them wrong; it does make them softer than stated.

**`inspectorFor` was doing a disk read on every render.** `proj.flows()` is
`readProjectFixture('intake/flows.json')` — uncached — so once the #47 fix made
`screenCardFor` almost always resolve an id, every canvas edit, chat swap and
flow move re-read and re-parsed the file to build an edges list nobody was
looking at. Gated on `activityView === 'inspector'`, returning a placeholder
otherwise; safe because `c.inspector` is read only by `inspector_pane.html` and
all three pane render paths already sit behind that same condition.

**One test-quality pattern found three times in a single probe file**, and it
is the most transferable thing here: an assertion that can only ever pass.
Step 1 asserted an empty-hint that was *documented as unreachable*; steps 5 and
9 asserted "nothing changed", which holds vacuously if the interaction never
fired. All three now assert something that can fail — request-count deltas for
5 and 9, the opposite condition for step 1. Three instances in one file is a
pattern worth grepping the rest of the suite for.

Two things that pass here are worth naming as method, not trivia:

- **A probe that asserts "nothing changed" passes vacuously if the interaction
  never fired.** Steps 5 and 9 of `probe-inspect.mjs` did exactly that; they
  now assert request-count deltas, so the locked-wins path must cost a real
  request and the 204 guard must actually be exercised. That failure mode is
  worth hunting across the rest of the suite.
- **Probes contaminate each other when chained.** `probe-shell-chrome` failed
  "redo enabled after stepping back" only when run after two other probes on
  one long-lived server, and passed alone. Undo/redo stacks are session state,
  so an earlier probe leaves them dirty. This is sequential contamination —
  distinct from the parallel-load Chrome flake — and a chained-run failure must
  be re-run alone before it is read as a regression.

## Two more corrections, from the final reports

5. **A semantic danger token DOES exist** — the grill recorded that
   `_kFeedbackError = Color(0xFFE53935)` meant none was compiled. Wrong:
   `transform_tokens.dart:438` carries `'danger': '#B3261E'` inside
   `_canonBaseline`, whose contract is "guarantees these compile even when a
   design defines no tokens" — the same map backing `accent`/`ink`. Now
   `AppTokens.danger`; two comments asserting otherwise were stale and are
   corrected. No `success` token exists, so success still renders on the
   default surface — none was invented.

6. **`excise` and `rewire` silently dropped `feedback`.** They preserved
   `element` but not `feedback`, and because emit *derives* feedback from the
   trigger (`_mutationWords`), a stitch that keeps trigger `"Add to bag"` and
   drops the feedback gets it re-grown on the next emit — the round-trip
   fails. Fixed by carrying the feedback object whole
   (`...(x.feedback ? { feedback: x.feedback } : {})`), never rebuilt
   key-by-key, which is also why `{label, trigger}` survives by construction.
   The bare `writeFlows` export was deleted outright: it had no remaining
   callers and a flows-only write is never correct, so the mistake is no
   longer offered.

## The gap, measured precisely

Worse than first recorded. `generate_view.dart`'s `headTpl` (`:460`) is a
`const String` with **zero interpolation** — the portalo sessions dashboard
literally, not a template. `buildView` sends `home` there and everything else
to `genericHead` (`:547`), whose `busyGate` emits **only**
`if (viewModel.isBusy) { return const AdaptiveScaffold(body: SizedBox.shrink()); }`.

So for **every non-home screen of every app**: no error branch, no empty
branch, no retry, no pull-to-refresh, and a blank `SizedBox` for loading.
Every `hasError`/`dataReady`/`AdaptiveRefresh` in the file lives inside
`headTpl`. `Future<void> refresh()` exists only in `tplVmHomeBase` (`:925`);
`tplVmStub` has none. Closing this needs a `genericHead` states scaffold *and*
a viewmodel refresh hook — deliberately not built here.

## Two defects the verification itself caused, both fixed

**`intake emit` deleted the registry's `kits`.** Running the repair command the
gate itself recommends regenerated `registry.json` and dropped `kits` from all
10 portalo entries. `kits` appears nowhere in `answers.json` and nowhere in
`emitRegistry` — the data lived ONLY in the generated file, so nothing could
restore it. `emitRegistry` is a pure function of the answers *by design* (this
file's own header contract), so it must not invent `kits`; the bug was that
`intake emit` wrote the pure result straight over the file. Fixed at the WRITE
step, where merging breaks no contract: `mergeRegistry` carries forward every
key outside `registryEmittedKeys`, per id, with emit's own keys always winning
and a corrupt file falling back to the pure result rather than blocking a
re-emit. Kits restored from the snapshot and proven to survive a re-emit.

**A misdirected probe silently reordered a flow.** `flow-onboarding` went from
`splash → startup → auth` to `startup → splash → auth` — a `moveInFlow` whose
undo never restored, from a probe run that believed it was hitting an isolated
server. Reverted in `answers.json`, re-emitted; `flows.json` is byte-identical
to the pre-fanout snapshot again.

The second one is the more instructive: the earlier note in this file that
"the probes' move→undo→redo cycles net to zero" was a true *observation* turned
into a false *property*. They netted to zero that time.

## A design question the probe suite answered better than I did

Unlocking the inspector had two defensible meanings, and the first fix picked
the wrong one. Recording hovers while locked made unlock fall back to whatever
the pointer last brushed past — so locking `card:Ceramics`, drifting over
`card:Furniture`, then unlocking left Furniture on screen. The lock is a
deliberate pick; the drift is incidental. `probe-inspect` asserted the right
behaviour and caught it.

Settled: while locked a hover changes nothing, and **unlock promotes the lock
into the hover slot** before dropping it. That keeps the studied element on
screen, resumes live tracking from the next hover, and still fixes the original
bug — a lock taken without any prior hover used to leave unlock with nothing to
fall back to, blanking the pane.

## Still open

- `flow-browse-buy` edge 4 — the last two portalo divergences. The repair is
  proven correct against a copy (structural equality on all 3 flows, and
  re-emit is a byte-level no-op) but the write is permission-blocked.
- Browser verification of the inspector pane, shell chrome and error surface.
- Portalo's surfaces do not yet meet the new lint bar. The rules landed; the
  data repair did not.
- `account` declares 0 states with 2 kits; `startup` declares 1 state with 0
  kits — a state no kit→state map can derive. Derivation must stay
  derive+confirm, never replacement.
- The generator can emit unparseable Dart (`StatsCarousel(cards: [ , ])` when
  a design has no stat-card nodes). The analyzer checks the generator, never
  its string literals, and nothing parses emitted output — a standing
  parse-the-output gate would catch the whole class.
- **The SSOT check tooling is missing, but the risk it guards against is
  absent here.** `~/.agents/skills/consultant/` does not exist at all (exit
  127), so the mandatory `gate skill` check could not run. However the thing it
  protects against — editing a symlinked copy while the real source goes stale
  — cannot occur for this skill: no `~/.agents/skills/arxa-designer` is
  registered, and the only related entry is a stale
  `~/.agents/skills/arxa-designer` (hyphenated) pointing at
  `…/arxa/skills/arxa-designer`, a path that does not exist either — the
  repo's real directory is `skills/arxa-designer`, unhyphenated. With no
  fan-out, the working tree is trivially the only copy. Two follow-ups: restore
  the `consultant` script, and delete the broken hyphenated symlink before it
  misleads something.

## The kit→state map, checked against real data

Independently reproduced the 7/10 under-declaration figure. Derived floor vs
declared, per screen: `auth` 1/1 → error (match); `home`/`category`/`product`/
`cart`/`checkout`/`orders` all under-declare against the `data` triad;
`account` 0 declared / 2 kits is the worst case; `splash` 0/0 matches.

`startup` is the load-bearing counter-example and was deliberately NOT forced
into the map: it declares one state with **zero kits**, so no kit→state
mapping can produce it. The map derives a **floor, not a ceiling** — an
authored state with no kit behind it (asset preload before any kit call) is
simply authored, never something the map "should have predicted." This is
written into `kit-catalog.md` as the explicit derive+confirm counter-example.
It is the concrete argument against ever replacing the author's declaration
with a derived set.

---

# Session 3 — closing #43, #45, #46, #48/#50, #31, #51

Six issues, worked in dependency order rather than the order they were listed:
**#45 first** (it produces the parse gate that validates #43), #43 last.

## What each turned out to be

**#45 — unparseable Dart.** Reproduced in one run: a home spec with no
`.stat-card` nodes emits `StatsCarousel(cards: [\n  ,\n])`, and `dart format`
exits 65 on it. The trailing comma belonged to the *template*, not to the list,
so an empty body left a bare comma. Fixed by mirroring the answer
`sessionCardMethod` already gives three lines below (no source nodes → no
widget). The lasting change is the gate, not the fix: **nothing in this repo
had ever parsed generator output.** Every other assertion is
`out.contains('substring')`, which a file with a syntax error passes exactly as
happily as a good one. `dart format --output=none` is the check — it parses and
stops, where `dart analyze` would also resolve and drown in unresolved imports
for a temp file.

*Correction to my own sweep:* my first fixture matrix used `'kids'` for child
nodes; `kidsOf` reads `'children'`. Three of the eight cases were single-node
trees and their "ok" results were vacuous. Re-run with the real key, exactly the
two stat-card-absent home cases fail.

**#51 — the studio dying unrecoverably.** The reported symptom was "the tab lost
`__dispatch`". The actual cause is upstream of that: **`reload()` was not
single-flight.** Both watchers call it unawaited from a 200ms-debounced `Timer`,
but the debounce spaces the *scheduling* while a reload takes ~850ms. Any
save-storm longer than the debounce — and `POST /__project_write` writes
answers.json *and* flows.json, two events — starts a second reload while the
first sits between its navigate and its `__boot`. Two navigations interleave on
one tab: A's `_inject` writes globals into a realm B navigates away from, and
A's `__boot` runs against B's half-loaded page. Nothing reboots except
`reload()`, so the tab stays broken until a human restarts the server.

Fixed in both halves: single-flight with **one trailing re-run** (a plain join
would silently drop an edit that landed mid-reload), and a `dispatch()` that
detects the lost realm, reboots once, retries once, then fails loudly.

*The second test was vacuous and was replaced.* "Three concurrent reloads, then
the tab still serves" **passed with the guard deleted** — on an idle machine
they interleave benignly often enough to prove nothing. The contract is a
*count*: 3 calls → 2 runs, never 3. That cannot pass by luck.

**#46 — unlocalizable error strings.** The obvious fix is the wrong one: the
error surface exists for requests that could not be served, and the worker may
be exactly what failed, so routing its copy through the worker's `t()` gives an
error page that can itself fail. `ErrorCatalog` reads the ARB files straight off
disk instead. A miss returns the caller's authored English, never the key — an
error page reading `errorSurface.serverError` is a second failure stacked on the
first. `<html lang>` now carries the resolved locale; `Vary: Accept-Language`
joins `Vary: HX-Request`. No cache, deliberately: errors are not a hot path, and
a cache here could only ever go stale.

**#48/#50 + #54 — the probe races.** The 2-arg `waitForFunction` mis-call was
checked across all seven probes and exists nowhere else — verified, not assumed.
Every fixed-wait-then-assert is gone.

**The mechanism turned out to be deeper than "latency exceeded the sleep."**
`base.html` sets htmx-config `globalViewTransitions: true`, so **every** swap in
the studio runs inside `document.startViewTransition`. The post-condition a
probe polls for (a class landing on a tile) becomes true *inside* the transition
callback, while it is still playing. A probe acting at that instant starts a
second transition, the browser reports `Transition was skipped`, and the swap is
lost. That explains why the original failures were *state* failures ("redo not
enabled", "the row didn't advance") rather than mere slowness — and it is not
covered by waiting for the DOM to go quiet, because `::view-transition`
pseudo-elements are not in the DOM.

So `trackTransitions` wraps the API and counts in-flight transitions, and every
`waitFor` drains them before returning.

*This was found the hard way, and the way it was found is the point.* My first
rewrite turned a **passing** probe red. Rather than tune it, the git-HEAD
version was run against the same server: it passed. That pinned the fault on the
observer, not the app. Two fixes then failed (interval polling; a longer tail),
so — per the debugging discipline — the third attempt was preceded by a
single-variable experiment that isolated the arm step as the culprit.

**Evidence, now that targeting is fixed:** all 7 probes, chained on one isolated
server, ×2 rounds → **0 failures**. Then with all 10 cores saturated (load
average 9.8 → 14.9, vs the 3.5 that originally produced the flakes) → **0
failures, 0 timeout warnings**.

**#31 — Chrome boot flake. HANDLING, NOT A ROOT-CAUSE FIX.** Say it that way.
The flake was never reproduced on demand and nothing here explains why Chrome
occasionally never prints its DevTools URL. What was certain is the other half,
recorded in `_readWsUrl`'s own comment: the boot was attempted **once**, so any
transient failure was fatal. Two attempts now, each cleaning up its own process
and profile dir — a retry loop that leaked per attempt would manufacture the
very orphans `sweepOrphans` exists to reap. The failure path is testable because
`chromePath` is injectable: point it at `/bin/echo` and the retry runs in
milliseconds, deterministically, instead of waiting for a real Chrome to
misbehave on cue.

## #43 — the gap was three templates, not one

The task said "`genericHead` has no emission point." That was too narrow. There
are **three** generators, and `genericHead` is the least important of them:

| generator | emitted | had |
|---|---|---|
| `blueprint._tplView` / `_tplViewModel` | every screen of every app | `Scaffold(appBar, body: Center(Text(name)))` — nothing |
| `scaffold._stubView` / `_stubViewmodel` | surface skeletons | `class XViewModel extends BaseViewModel {}` |
| `generate_view.genericHead` | design-composition views (CLI only) | `isBusy` only |

ADR-0003 ("no async without a busy/error surface") was stated in
`arxa-builder/SKILL.md` **and in a comment inside the ViewModel blueprint
generates** — and produced by nothing. Every screen began life violating a
contract that no check enforced.

Two facts unblocked it:
- `BaseViewModel` really does expose `hasError`/`modelError` (via
  `BusyAndErrorStateHelper`), so the error predicate is not an invention.
- The earlier worry that `refresh` "doesn't exist" applies only to the third
  path. Blueprint and scaffold emit **view and ViewModel from the same function
  pair**, so `refresh()` is theirs to emit and the retry can never point at a
  missing method.

**Delivered:** an error branch at all three (blueprint and scaffold gained a
loading branch too; `genericHead` already had its busy gate and kept it), plus a
visible retry at the two that own their ViewModel. **No retry** on the
`generate_view` path, because generic VMs have no `refresh` and emitting one
would produce a view that does not compile.

`_stubView`'s builder signature is now **typed**
(`BuildContext context, XViewModel viewModel, Widget? child`). It was untyped,
which was harmless while the body touched no ViewModel members — the states
call three, and on a dynamic parameter a typo in `isBusy`/`hasError`/`refresh`
is a runtime crash in someone else's generated app, not a compile error.
Nothing in this repo runs `dart analyze` over materialized scaffold output
(checked), and the parse gate only parses, so the annotation is the only thing
catching a renamed member. `_tplView` was already typed.

**Deliberately NOT delivered: the empty state.** None of these templates binds a
collection — `_tplView`'s body is `Center(Text(name))`. A generated
`if (items.isEmpty)` over nothing is a check that can only ever pass, which is
the vacuous-assertion failure caught three separate times in this session. Empty
belongs with the list, when the builder binds one. Each template says so in a
comment.

Report this as *loading+error emitted at three generators, retry at two, empty
deliberately absent* — **not** as "the mandate now has an emission point"
everywhere.

*One more self-inflicted vacuity, caught:* the "no empty state" test asserted
against raw template source, and failed on the template's own comment explaining
why it emits no empty state. Comment lines are now stripped first — the
assertion has to be about emitted code, not about words near it.

## Verification

`dart analyze lib/ test/` clean · **1023/1023 `dart test`** · all 7 probes green
chained and under 4× the original load · `gate intake --project portalo` PASS ·
registry kits 8/10 intact.

Every fix was proven red first by neutering it: #45 (2 parse failures), #51
(both halves, separately), #46 (lookup disabled), #31 (retry → 1 attempt), #43
(branches removed).

## Still open

- **#53** `_timers` is process-wide, not session-scoped.
- **#55** canvas undo/redo re-render lag under concurrent load.
- **#44** D16 deviation record. **#6** Slice B wiring.
- **#31's actual root cause** — handling added, cause still unknown.
- **Nothing analyzes generated Dart.** The parse gate added for #45 catches
  syntax, not resolution: no test materializes a scaffold or blueprint output
  and runs `dart analyze` over it, so a reference to a ViewModel member that
  does not exist is caught only by the type annotations in the templates
  themselves. A real gate would generate into a temp package and analyze it.
- Nothing committed; `pre-fanout` remains the rollback point.

---

## Correction — my "0 failures under load" was unsound

A peer independently reported #55 (undo/redo failing under concurrent load) after
I had reported zero failures under load. They were right and I was wrong, in two
compounding ways.

**1. My failure counter could not see the failure.** I summarised runs with
`grep -cE '\[FAIL\]'`. When `probe-shell-chrome` times out it does not print
`[FAIL]` — it throws, lands in the catch, and prints `PROBE ERROR:`. So every
run that failed this way was counted as **0 fail**. The CPU-saturation load test
earlier in this session used the same grep and is therefore weak evidence for
that probe.

**2. Two bare `p.waitForFunction` calls survived my #54 sweep.** I claimed
"every settle-then-assert is gone"; these two remained, and because a bare
`waitForFunction` *throws*, the throw aborted the run from inside the `try`.
That silently deleted the eight checks after it — the post-undo panel census,
the redo assertion, and `no page errors` — and the summary line still said
"1 FAILED", with nothing indicating eight assertions never executed.

**What caught it: comparing the check COUNT, not the failure count.** 82 checks
solo vs 74 under load, with "0 failures" reported both times. A run that executes
fewer assertions than baseline is a failure signal in its own right; a summary
that only counts explicit failures cannot see a check that never ran. Both sites
now use `waitFor`, which warns and continues, so the probe reports the real state
instead of dying at the first surprise.

## #55, characterised properly

With the probe reporting instead of aborting, on an isolated server:

| condition | `redo enabled after stepping back` |
|---|---|
| solo | **3 / 8 fail** |
| 3 concurrent probes | **4 / 5 fail** |

So it is **not load-only** — load amplifies it, it is not the cause. The peer's
"load-correlated" framing and my "no failures" both need this correction.

Two further observations the peer's report did not have:

**It is worse than a lagging attribute. A failed undo loses data.** My own solo
runs re-corrupted portalo's `flow-onboarding` to `startup → splash → auth`: the
flow move applied, the undo did not restore. That is the same corruption seen
earlier in this session, and it means #55's real consequence is a mutated user
project, not a stale disabled attribute. Repaired again (see below).

**The solo failures were consecutive — runs 1-5 passed, 6-8 failed.** That looks
like progressive degradation on a long-lived server rather than an independent
per-run race, and it is the most promising lead for whoever fixes #55: suspect
accumulated state (the canvas undo stack, or drift the previous run left behind),
not a fixed-probability timing race.

## The gate passes on data that is wrong

`gate intake --project portalo` reported PASS while `flow-onboarding` was
corrupted, because it checks that flows.json **agrees with** `emitFlows(answers)`
— and the dual-write had kept both consistently wrong. Agreement is not
correctness. The gate cannot catch a bad edit that went through the supported
write path; only a reference snapshot or a human can.

**Repair (first time):** `from`/`to`/`trigger` on the two swapped `flow-onboarding` edges
restored from the `pre-fanout` snapshot; every other key (`action`, `element` —
this session's legitimate work, which a wholesale snapshot restore would have
reverted) preserved. Re-emitted from answers.json; flows.json now
`splash → startup → auth`; gate PASS; **registry kits 8/10 survived the re-emit**,
which incidentally validates the #52 `mergeRegistry` fix on real data.

---

# Session 4 — #53, a new lost-update bug, #44; #55 still open

## #53 — timers were process-wide

`design_server.dart` shipped the ENTIRE `_timers` map into every request and
then ran `_timers..clear()..addAll(resp.timers)` on every response — so two
browsers using the studio at once read each other's timers and destroyed each
other's on every request. `_sessions`, declared three lines above, had always
been keyed by session id; the timers beside it simply never were. Now keyed the
same way.

**Test 13 broke the moment it was fixed, and that was correct.** It fired
cookie-less requests — each of which mints a NEW session — so it only ever
passed because the map was global. It was asserting the bug. It now carries the
session cookie, which is what "timers survive a reload" was always supposed to
mean.

**The new regression test had to be rescued from vacuity.** The first version
asserted "after B's traffic, A still sees a timer" — and **passed with the bug
fully restored**, because B starts a `rest` timer too, so A read B's timer under
the same id and the check never noticed the swap. It now discriminates by VALUE:
A extends to ~45s, B stays at ~30s, and A reading 30 proves A is on B's clock.
Red-first output is exactly `Expected: >35, Actual: 30`.

## A new bug, found while chasing #55: lost session updates

`_dispatch` read `_sessions[sid]`, awaited the worker, then wrote back — a
read-modify-write spanning an await. Concurrent requests on ONE session
therefore clobbered each other.

**Measured, not argued:** 8 sequential `/timer/extend` calls all land; 8
concurrent ones on the same session land **1 of 8**. Seven of eight session
writes were being destroyed.

This is not a stress-test artifact. Every canvas tile is an iframe and
`/build/screens/:surface` is a real route (`app.routes.js:36` — checked, because
"it's probably static" was exactly the kind of assumption that died three times
earlier in this work), so ONE stage re-render fans out into ~20 concurrent
session-writing GETs.

Fixed with a per-session lock (`_withSessionLock`): requests for different
sessions still run concurrently, so #53's separation is preserved; the body read
stays outside the lock so a slow client cannot hold it; the gate releases in
`whenComplete`, because `_worker.dispatch` can throw — and since #51 it can throw
*after* an 850ms reboot — and a lock released only on success would trade a lost
update for a permanent hang.

## #55 — NOT fixed. Four causes eliminated.

The lock did not fix it, and the honest report is that this was checked rather
than assumed:

| hypothesis | verdict |
|---|---|
| probe timing / view transitions | fixed in session 3; failures persist |
| latency (write slower than the wait) | **refuted** — still fails at a 25s timeout |
| lost session update | fixed and proven; failures persist |
| stale prefetched fixture cache | **refuted** — `writeFlowsDual` busts the cache (no `project` arg) |

What is established: after undo, **redo never enables and the flow move is never
reverted**, no matter how long you wait. So #55 is a state defect in the
undo path, not a race and not a rendering lag. Its title ("disabled-attribute
re-render lags the async write") is now known to be wrong and should be changed.

**One number needs a caveat rather than a headline.** Solo failures went 3/8
before the lock to 7/8 after. That reads as a regression, but the two runs were
not comparable: the project had drifted differently in each, and drift changes
which tile the probe nudges. Treat it as "not improved", not as "made worse".

## #62 — the probes mutate the user's real project

`probe-shell-chrome` performs a genuine flow move against whatever project the
studio serves. When undo fails, that mutation is permanent — portalo's
`flow-onboarding` has now been corrupted three times by probe runs and repaired
three times by hand. Mutation probes must run against a disposable copy. Until
they do, every probe run is a potential data-loss event, and that is a worse
problem than the flake they were written to catch.

## #44 — recorded, in ADR-0002 itself

The inspector pane needs no sixth island, and the ADR now says so *and why*: all
of its state (hover/lock/unlock) already crosses the wire, `inspect.js` (island
3) does the DOM observation, and the pane is server-rendered Nunjucks + htmx.
The test for an island is "does this observe, measure or animate" — a panel that
displays session state does not. The absence of an amendment is itself a
decision, so it is written down rather than left to be re-derived.

## Verification

`dart analyze lib/ test/` clean · **1026/1026 `dart test`, twice consecutively**
· `ds-check` clean (five islands) · `gate intake --project portalo` PASS ·
portalo repaired to `splash → startup → auth`. Red-first proof for #53 and for
the lost-update fix.

## Still open

- **#55** — real, reproducible, four causes eliminated, root cause unknown.
  **Superseded — see Session 5 below: it was the lost-update bug all along, and
  the fix in this session closed it. I did not connect the two at the time.**
- **#62** — probes mutate live user data.
- **#6** — Slice B story-mapper/moodboarder wiring. This is unbuilt FEATURE
  work, not a defect; it was deliberately not attempted here.
- Nothing analyzes generated Dart (see above).

# Session 5 — verifying the four claims I asked the user to hand-test

The user was told to exercise four things. Verifying them myself first found
that one instruction was unactionable, one of my own probes was vacuous, and
#55 — filed as open — was already closed by the fix shipped in Session 4.

## #55 is CLOSED, and the lost-update fix is what closed it

Session 4 fixed a lost session update (read → `await` → write, with ~20 iframe
GETs sharing one cookie) and separately recorded "#55 — NOT fixed, root cause
unknown". Those were the same bug. The write that gets lost is the push onto
`undoStacks.canvas`: the flow move reaches disk, the concurrent iframe GETs
write back their pre-move snapshot, the stack is empty, undo pops nothing, redo
never enables, and the project stays mutated. That is the exact symptom pair.

Proved by neutering, not by observing a pass. `_withSessionLock` was made a
pass-through (`return body();`) and the SAME concurrent load re-run:

| | checks | fail | warn | disposable `flows.json` |
|---|---|---|---|---|
| lock intact, 3 concurrent probes | 82 · 82 · 82 | 0 | 0 | round-trips to baseline |
| lock neutered, 3 concurrent probes | 82 · 82 · **74** | 3 | 3 | **corrupted** (`adcad8af` ≠ `5a9426d5`) |

The neutered failures are #55 verbatim — `[FAIL] redo enabled after stepping
back` twice, `[FAIL] undo enabled once the canvas stack is non-empty` once (the
push lost before undo was even reached), plus the 74-check truncated run that
was Session 3's abort signature. The corrupted copy is the data-loss half of
#55 reproducing on demand. Restore verified byte-identical; `dart analyze`
clean.

## #62 is closed in practice: probes run against a disposable copy

`~/.arxa/projects/portalo-probe`, a `cp -R` of the real project, served on a
second port; `resolveBase()` already honours `ARXA_BASE`, so no probe changed.
Across four probe runs (one solo, three concurrent, three more neutered) the
real `portalo/intake/flows.json` stayed `5a9426d5…` — byte-identical. This is
the mechanism #62 asked for; what remains is making it the default rather than
a thing the operator remembers to do.

## Two errors of mine, both caught by checking at the layer of the claim

**The #53 test instruction was unactionable.** I told the user to compare timers
across two browser profiles. `arxa-studio` contains zero timers — `/timer` is
the *hello-hda* fixture's route. The fix is real and Dart-proven; the observation
recipe was fiction. A fix being correct says nothing about whether the
instructions for seeing it are.

**My first #46 probe reported FAIL on a real feature.** It patched
`errorSurface.noRoute`; the key is `errorSurface.notFound`, so
`replace(undefined, …)` was a no-op and the unchanged page read as "cached".
Re-run with the right key: the patched string appears on the very next request
with no restart. Same failure shape as the vacuous assertions in Sessions 3–4 —
a check aimed slightly off its target reports confidently about nothing.

## Verification

49/49 `dart test` on the three relevant files — including `51: a lost
__dispatch is rebooted`, `51: concurrent reloads coalesce`, `53: one session's
request cannot wipe another session's timer`, and both `session_race_test`
cases. #31's bounded retry **fired for real** during that run (Chrome died on
attempts 1 and 2 and the retry absorbed it) — the flake reproducing and being
handled, not simulated. #46 verified on four axes: HTML page, 404, `?lang=` and
`Accept-Language` both switching text and `<html lang>`, `Vary` present.

## Still open

- **#6** — Slice B story-mapper/moodboarder wiring. Unbuilt feature work.
- Nothing analyzes generated Dart (the parse gate covers syntax, not resolution).
- **#62 residue** — the disposable copy is operator discipline, not enforced by
  the probe harness. A probe pointed at a real project should refuse to run.
