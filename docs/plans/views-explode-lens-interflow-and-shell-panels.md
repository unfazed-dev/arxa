# Views explode lens, inter-flow hand-off, state/feedback contract, shell panels

Status: **planned** (grilled 2026-08-02, six decisions taken by the operator).
Supersedes nothing. Builds directly on
`docs/plans/design-viewer-per-lens-hover-and-flow-mode.md` (Slice 7, shipped
but uncommitted at the time of writing).

---

## Evidence gathered before planning

Everything below was read from the live system, not recalled. Where a premise
in the request turned out to be wrong it is corrected here rather than quietly
dropped.

### E1 — the views lens really is a single column, and it is a CSS specificity loss

Measured against the running server (`/design`, 2000×1200 viewport):

```
zoomClass : "dv-zoom dv-zoom-views"
flexWrap  : wrap
dir       : column      <-- .dv-zoom-views asks for `row`
zoomW     : 1135   canvasW: 1167
rows      : 10 rows, one 390px tile each
```

`.dv-flow-canvas .dv-zoom` (specificity 0,2,0) sets `flex-direction: column`
and beats `.dv-zoom-views` (0,1,0) which asks for `row`. The result is a
column that wraps — i.e. never wraps. The rule has been dead since it was
written. **It is deleted by this plan rather than fixed**, because decision D4
replaces the flat grid entirely.

### E0 — TWO FILES, AND I CONFLATED THEM ACROSS TWO SESSIONS

Read this before E2. `intake/answers.json` (the elicited source) and
`intake/flows.json` (the emit target) **have diverged**, and every confusion
below flows from that:

| edge | answers.json (source) | flows.json (emitted + edited) |
|---|---|---|
| auth→home | `"Sign-in success"` / `system` | `"continue"` / `push` / `element: button:Continue` |
| checkout→orders | `"Order placed"` / `replace` | `"Track your order"` / `push` |

The other 8 edges agree. **`answers.json` already holds the browse-buy chain in
the correct order** — home → category → product → cart → checkout → orders — so
the scramble in E2 never existed at source; it was introduced downstream by the
viewer's flow editor, precisely as the `rewire()` replay predicts.

**A correction of a correction, on the record.** In the previous session I
claimed auth→home read `"Sign-in success"` / `system`, then retracted it and
stated flatly that "there is no 'Sign-in success' trigger and no
`action: system` edge at all." Both readings were of *different files*. The
first was true of `answers.json`; the second was true of `flows.json`. The
retraction destroyed a true statement, which is worse than the original error —
it replaced a half-view with false confidence. Found by the `dart-contract`
subagent checking the source `emitFlows` actually reads, rather than accepting
my framing.

Note also that `answers.json` types auth→home as `action: system`, and
DESIGN-ARCHITECTURE says a `system` edge is **not user navigation** — it becomes
a route guard downstream. `flows.json` types it `push` with an `element`. Both
are defensible at different layers (the user does tap Continue; the transition
is still system-driven), but they now disagree, and the flow-walk feature is
built on the `push` reading.

### E2 — `flow-browse-buy` edges are scrambled, and the editor is the likely cause

Discriminating check (`GET /build/screens/:id`) on the actual rendered stubs:

| screen | what it actually renders |
|---|---|
| `portalo.checkout` | **"Order placed"** — order confirmation |
| `portalo.orders` | order history list |
| `portalo.category` | Ceramics grid |

So the authored chain reads:

```
home --"Category tile"--> [Order placed] --"continue"--> Ceramics
     --"Product card"--> Product --"Add to bag"--> Cart --"Checkout"--> Orders
```

The trigger *sequence* is coherent for a chain the screens no longer match.
That is the signature of `rewire()` in `design_facade.js`, which rebuilds edges
positionally with `prev?.trigger` — so dragging a tile moves the screen and
leaves the trigger label behind. **Every row drag silently relabels the row.**

Two separable defects:

1. **product defect** — `rewire()` should carry the trigger with the screen it
   was authored on, not with the slot.
2. **data defect** — portalo's `flow-browse-buy` is already scrambled on disk.

See **OPEN-1** below: the data fix needs an explicit operator decision.

### E3 — portalo is NOT missing state declarations

The request assumed it was. It is not. `registry.json` declares states on 8 of
10 screens:

```
startup [loading]      home     [loading, empty]   category [loading, empty]
auth    [error]        product  [loading, error]   checkout [loading, error]
cart    [empty]        orders   [empty]
splash  —              account  —
```

`intake.dart:159` validates `states` as *any list of strings* — an open
vocabulary with no enum. What is actually missing: nothing **renders** these,
nothing anywhere mentions a **toast**, and `splash` / `account` have none.

### E4 — the exploded panel's data model already exists (mostly)

49 `data-el` elements across 8 screens, **100% of them carrying
`data-inspect-fn`**, plus `-role`, `-style`, `-motion`:

```
splash   0    auth     5    category 5    cart     6    orders  8
startup  0    home     7    product  5    checkout 4    account 9
```

`splash` and `startup` have **zero** — their exploded panel is legitimately
empty and must render an empty state, not a crash.

Gaps against the request: **size is nowhere in the data** (it exists only after
layout, inside the iframe), and **portalo declares zero `kits`** on any
registry entry, so an element→kit column renders `—` everywhere until kits are
declared.

### E5 — the kit "mirror" does not mirror

`config/kit-registry.json` holds **24 kits**. `references/kit-catalog.md` is 98
lines explaining the *mechanism* and listing **zero** of them. Two are directly
load-bearing for this plan:

- `kit/state` → `async state vocabulary (idle/loading/error)`
- `kit/ui_library` → `UI-coupled services (navigation / sheet / notifications toast)`

The kit already separates screen-state from transient-feedback. Decision D2
mirrors that split rather than inventing one.

### E6 — project surfaces are project-owned

Portalo's screen partials live at
`~/.appbox/projects/portalo/design/surfaces/*.html` (12 files), reachable only
through `POST /__project_write`. They are **not** in the repo. The generic
`screen_stub_view.html` authors only 3 `data-el`s; every portalo element comes
from those project files.

---

## Decisions taken (operator, grilled one at a time)

| # | Question | Decision |
|---|---|---|
| D1 | How do flows connect? | **Implicit join via shared screen ids.** No schema change. A screen that terminates one flow and heads another *is* the join. |
| D2 | Is a toast a screen state? | **No — two axes.** `states` stays screen-level with a CLOSED vocabulary; `feedback` moves to the **edge**, because a toast is a consequence of a transition. Mirrors `kit/state` vs `kit/ui_library`. |
| D3 | Who fills states/feedback? | **Intake derives, marked `inferred`.** Follows the precedent `emitFlows` already sets (`intake.dart:371-374`) — derivation is legal when marked and confirmable, so architecture §22 holds. |
| D4 | What is a views row? | **One row, two columns: screen \| exploded panel.** Rejected: flat grid, per-epic rows, per-screen state variants. |
| D5 | What lights up on click? | **The three real joins**: authored `data-inspect-fn`, the flow edge the element fires (via the `element` join), the kit that will implement it — plus live-measured box/style. **No invented Dart symbols.** |
| D6 | Where do the panels sit? | **Both INSIDE `.design-viewer`.** Fullscreen target unchanged; `canvas.js` untouched. Cost: the viewer is also the build-evidence component, so every shell action needs a `static` guard. |

---

## Slices

Ordered by dependency. Each slice states its **runnable check** — the smallest
thing that goes red if the slice breaks. Red-first: write the check, watch it
fail, then build.

### Slice 1 — inter-flow hand-off (D1)

`project_repository.js`:

```js
// Flows connect through shared screens — a screen that terminates one flow and
// heads another IS the join (D1). `nextEdge` stays row-scoped and honest;
// `handoffs` answers the separate question "where else does this screen go?".
export const handoffs = (screenId, fromFlowId) => { ... }
```

- returns `[{ flow, flowName, to, trigger }]` for every *other* flow whose
  edges start at `screenId`
- `design_facade.js` flows builder: the last tile in a row gains
  `handoffs: [...]`
- `design_viewer.html`: row-end renders `continues in <name> →` chips, each an
  `hx-get` that switches the walk to that flow at that screen
- the flow walk at a row end offers the chips instead of dead-ending

**Check** — `tools/probe-flowwalk.mjs` section E: walking `flow-onboarding` to
`portalo.home` surfaces exactly **2** hand-off chips (`flow-browse-buy`,
`flow-account`); clicking one continues the walk in that flow. Red when
`handoffs` ignores `fromFlowId` (3 chips, one self-referential).

### Slice 2 — CANCELLED. The premise was false.

**Correction (recorded deliberately, not dropped).** E2 asserted a product
defect: that `rewire()` rebuilds edges positionally and so "every row drag
silently relabels the row". Reading the function disproves it —
`design_facade.js:155` builds `outByFrom = new Map(edges.map(e => [e.from, e]))`
and re-derives with `outByFrom.get(from)`. The trigger is keyed to the **`from`
screen id**, which *is* the "carry the trigger with the screen" behaviour this
slice was going to introduce. It was already correct.

Verified rather than argued. Replaying the real `rewire()` over the
reconstructed original chain with a single drag of `portalo.checkout` from
index 4 to index 1:

```
MATCH  home --Category tile--> checkout
MATCH  checkout --continue--> category
MATCH  category --Product card--> product
MATCH  product --Add to bag, then review bag--> cart
MATCH  cart --Checkout--> orders
reproduces portalo on-disk data exactly: true
```

So the on-disk scramble is the **correct output of one legitimate drag**, not a
bug. Moving a screen in a chain necessarily leaves each trigger attached to its
source screen while that screen's *destination* changes — the labels stay
structurally valid and become semantically wrong, and there is no general way
for the code to tell. The flows lens already renders every trigger label, so
the condition is visible to a designer who looks.

No code change. **Slice 8a's data repair is the entire remedy.** Deliberately
not replaced with a substitute check: a lint that verified an edge's `element`
resolves to a real `data-el` on the `from` screen would pass on this exact case
(`button:Continue` does exist on `portalo.auth`), so it would be a check that
cannot fail when it matters.

### Slice 3 — two-axis state/feedback contract (D2 + D3)

**`appboxd/lib/intake.dart`**

- close the `states` vocabulary: `loading | empty | error`. Unknown values are
  a validation **error** naming the allowed set.
  *Migration:* portalo's declared states are all in-vocabulary, so it passes
  unchanged. Any project outside the set fails loudly with the fix in the
  message — deliberate, per D2.
- new optional edge key `feedback: { kind, text }`, `kind ∈ success|error|info`
- `emitRegistry` derives states from surface shape and stamps
  `statesProvenance: 'inferred'`
- `emitFlows` derives `feedback` on mutation edges, stamped `inferred: true`
- brief renders both as `[inferred]` so the confirm step has something to confirm

**`appboxd/lib/emit_structure.dart`** — validate and pass through both keys.

**`design_viewer.html`** — the flows connector renders the feedback chip
(`✓ Order placed`) under the trigger label.

**Check** — `dart test`: (a) an out-of-vocabulary state is rejected with the
allowed set in the message; (b) a list surface with no declared states emits
`[loading, empty]` + `statesProvenance: inferred`; (c) `feedback.kind` outside
the enum is rejected. Plus `appbox gate intake --project portalo` stays PASS.

### Slice 4 — the views explode lens (D4 + D5)

**Layout** — `viewer.css`:

- delete the dead `.dv-zoom-views { flex-direction: row }` rule (E1)
- `.dv-views-row` — one row per screen, `display: grid; grid-template-columns:
  auto minmax(18rem, 1fr)`; column 1 the existing `.dv-tile`, column 2 the new
  `.dv-explode`
- `.dv-explode-el` rows colour-coded by role (reuse the role→colour map that
  already exists in `cdp.dart:75`)

**Element inventory** — ~~`elementsFor(screenId)` regexes the project's surface
partial~~ **CORRECTION (found while building).** This does not work and the
claim it rested on was false. `data-el` values are *templated*, not literal:

```
home.html      data-el="card:{{ t('portalo.cat.' ~ pair[0]) }}"   {% for %} over 4 pairs
_tabbar.html   data-el="tab:{{ t('portalo.tab.' ~ suffix) }}"     {% for tab in tabs %}
```

Regexing the source yields **one** entry reading literally
`card:{{ t('portalo.cat.' ~ pair[0]) }}` instead of four resolved names, and
misses the tab bar completely because `home.html` pulls it in with
`{% include "ui/project/_tabbar.html" %}`. Static parsing would need a
loop-evaluating, i18n-resolving, include-following template interpreter — i.e.
nunjucks.

**The inventory therefore comes from the RENDERED DOM, not the source.** The
stub iframe is same-origin, so the parent reads
`iframe.contentDocument.querySelectorAll('[data-el]')` — already resolved,
already including `_tabbar`, and it is the same node set `inspect.js` walks, so
the two lenses cannot disagree. Split of truth:

| datum | source |
|---|---|
| element name, role, style, motion, fn | rendered DOM (`data-*` on the node) |
| box size | rendered DOM, on click (does not exist until layout) |
| `fires` (flow edge) | **server** — flows.json `element` join, passed down as a per-screen map |
| `kit` | **server** — registry `kits` |

So `explode.js` is a genuine island doing genuine work, but it is the same
*kind* of work `inspect.js` already does (walk `[data-el]`, read
`data-inspect-*`, render a readout). It is a sibling, not an escalation.

**Joins (D5)** — per element, resolved in the facade:

- `fires` — scan flows for an edge whose `element` matches this `data-el`;
  render `flow-onboarding → portalo.home`, else `—`
- `kit` — the screen's registry `kits` (portalo has none; renders `—` and that
  is the honest answer — see OPEN-2)
- `fn` / `role` / `style` / `motion` — straight from the data-attributes

**Interaction** — new parent-side island `runtime/vendor/explode.js`
(**ADR-0002 amendment required**). Same shape as `canvas.js`/`drag.js`: IIFE, no
globals, re-arms on `htmx:load`. Because the stub iframe is same-origin the
parent can reach `iframe.contentDocument` directly, so **no child-side change
and no postMessage** — clicking an `.dv-explode-el` flashes the matching
`[data-el]` in column 1 and writes the measured box/style back into the row.
Size is filled on click, not pre-rendered, because it does not exist until
layout.

**Empty state** — `splash` and `startup` have zero elements (E4); the explode
column renders the existing `_empty-state` partial, not an empty box.

**Check** — new `tools/probe-explode.mjs`: (a) views lens renders 10
`.dv-views-row`, each with exactly 2 columns; (b) `portalo.auth`'s explode
column lists 5 entries; (c) clicking `button:Continue` flashes the element in
the iframe **and** the row shows `fires: flow-onboarding → portalo.home`;
(d) `portalo.splash` renders the empty state, not a crash; (e) iframe count is
unchanged after a click (no re-navigation).

### Slice 5 — the two shell panels (D6)

`design_viewer.html`, both **inside** `.design-viewer`:

- `.dv-topbar` — title (`design.artboardsEyebrow`), run-state pill, and
  shell-scoped actions. **Every action guarded by `v.static`** so build
  evidence renders the bar without controls (the D6 cost, accepted).
- `.dv-botbar` — hosts the mini panel, re-laid out from floating to docked:
  one horizontal bar, lens switch left, undo/redo + fullscreen centre, device
  rungs + bg swatches right.
- delete `.dv-flow-canvas { padding-bottom: 11rem }` — it exists only to clear
  the floating panel and is dead once docked.
- `prototype_view.html` drops `artifact-head` / `artifact-foot`; their content
  moves into the viewer contract as `v.title`, `v.actions`, `v.foot`.

**Check** — `probe-inspect.mjs` extended: fullscreen the viewer, assert the
lens switch, undo/redo, rungs, swatches **and** the exit button are all
visible and clickable; assert build evidence (`static: true`) renders
`.dv-topbar` with **zero** action controls.

### Slice 6 — the kit mirror (E5)

- `references/kit-catalog.md` gains the full 24-kit table generated from
  `config/kit-registry.json` (dir, package, capabilities, verification tier).
- **Check** — a design selftest check: every `dir` in `config/kit-registry.json`
  appears in `kit-catalog.md`. Red the moment a kit is added and the mirror is
  not updated. This is what stops the mirror rotting again.

### Slice 7 — docs, ADR, skills

- **ADR-0002 amendment (2026-08-02, second)** — `explode.js`, the parent-side
  inspect island. Note explicitly that it needs no child-side counterpart
  because the stub is same-origin.
- `DESIGN-ARCHITECTURE.md` — views lens is now screen+explode rows, not a flat
  grid; the two-axis state/feedback contract; inter-flow hand-off.
- `ui/common/_integration_viewer.md` — the `v` contract gains `title`,
  `actions`, `foot`, `rows[].explode`, `flows[].handoffs`.
- `skills/appbox-intake/SKILL.md` — states vocabulary + derived-and-inferred
  rule.
- `skills/appbox-designer/SKILL.md` + `references/ui-recipes.md` — feedback on
  edges, the explode lens.
- `skills/appbox-story-mapper` — carries `states`/`feedback` through (it was
  named in the last plan's docs slice and **not** edited; still outstanding).

---

## Slice 8 — project data (operator-approved, both)

Both were held back as OPEN items and both were approved. They mutate
`~/.appbox/projects/portalo/` and go through `POST /__project_write` only —
never a direct file write, never a hand-edit of a generated fixture.

**8a — unscramble `flow-browse-buy` (E2).** Slice 2 stops *future* drags from
relabelling a row; it does not repair data already on disk. Re-pair each
trigger with the transition it was authored for:

```
home     --Category tile-->  category      (was: --> checkout)
category --Product card--->  product
product  --Add to bag----->  cart
cart     --Checkout------->  checkout      (was: --> orders)
checkout --Track your order-> orders       (was: checkout --continue--> category)
```

*(Corrected after the fact: this table originally read "Track order". The
authored value is **"Track your order"** and that is right — the tiebreaker is
neither the plan nor the task prompt but the screen, which renders a button
labelled exactly "Track your order". A `trigger` names what the user taps, and
`flowwalk.js` fuzzy-matches it against `data-el` when no explicit `element` is
authored, so a paraphrase there is a real defect, not a wording nit.)*

**8b — declare kits.** Gives the explode panel's `kit` column real values
instead of 49 dashes, and exercises the kit mirror end to end:

```
portalo.auth     ["auth"]            portalo.category ["data"]
portalo.checkout ["payments","data"] portalo.product  ["data","media"]
portalo.cart     ["data"]            portalo.orders   ["data"]
portalo.home     ["data"]            portalo.account  ["auth","data"]
```

Every name is validated against `config/kit-registry.json` by
`appbox emit structure`; a wrong name fails the build rather than rendering a
plausible lie.

**Check** — `appbox gate intake --project portalo` stays PASS; a probe asserts
the flows lens renders the corrected chain and that `portalo.checkout`'s
explode column shows `kit/payments` rather than `—`.

---

## Outcome (2026-08-02)

All slices landed except Slice 2, which was cancelled on evidence. Verified:
`dart analyze` clean · **948 tests** (was 918) · design lint clean on studio AND
portalo · design selftest **25/25, skipped 0** (was 24) · `gate intake
--project portalo` PASS · probe-flowwalk / -no-reload / -boost /
-composer-draft all pass · probe-inspect clean bar the known favicon 404.

**`tools/probe-explode.mjs` (NEW) is the durable check for Slices 1, 4 and 5** —
none of the five pre-existing probes touches `.dv-views-row`, `.dv-explode`,
`.dv-handoff`, `.dv-topbar` or `.dv-botbar`, so without it `explode.js` could be
deleted outright and the whole suite would stay green. 27 checks in four
sections; two of them earn their keep specifically:

- *"an element with no edge reads `—`, never a guess"* — `field:Email` has no
  authored edge and no trigger it plausibly matches. If the fuzzy fallback is
  ever loosened, that element starts claiming to fire something and this goes
  red. It is the anti-guess assertion.
- *"fullscreen EXIT button inside the fullscreen target"* — the failure mode
  that made D6 a real decision rather than a layout preference: put the bottom
  panel outside `.design-viewer` and fullscreen strands the user with no way
  out.

Proven red, twice, in the right sections:

```
RED 1  facade stops emitting handoffs   -> 2 FAILED  (chip count 2->0, and the
                                                      click-a-chip walk check)
RED 2  explode.js not loaded            -> 5 FAILED  (all four element counts +
                                                      the empty states)
GREEN  restored                         -> ALL CHECKS PASSED
```

Confirmed separately: `__project_write` preserved everything it was not asked
to change — `element: "button:Continue"` still on the auth→home edge, and 8/10
`states` arrays intact (`portalo.splash` and `portalo.account` never had any,
which matches the pre-write registry exactly). `dart run bin/appbox.dart docs`
reports **94 pre-existing warnings** and 2 orphan docs; this plan file is
likely a third. Not addressed — unrelated to this work.

Two corrections were recorded rather than quietly fixed — Slice 2's cancelled
premise, and the templated-`data-el` discovery that redesigned Slice 4's data
source. Both are above, in place.

**Two defects I introduced and fixed, both caught by red-first rather than by
reasoning:**

1. *The kit-mirror check was weaker than its name.* Removing the `payments`
   TABLE ROW left it GREEN, because `payments` is also name-dropped in prose
   and the check searched the whole document. Six of 24 kits are named in
   prose, so for a quarter of the registry it could not see a deleted row. Now
   scoped to lines starting with `|`; both the table-only case (`bluetooth`)
   and the prose-masked case (`payments`) go RED, and restore goes GREEN.
2. *Wiring that check broke the selftest's own green baseline.* It resolved the
   repo root as `dirname(dirname(skill))`, true only for the real
   `<repo>/skills/appbox-designer` layout — `design_selftest_test.dart` builds a
   minimal clean skill in a system temp dir, so the guess landed in
   `/var/folders` and two tests failed (baseline exit 1; negative mode 65
   unproven, a cascade of the same cause). Fixed by walking up from the skill
   dir then the cwd, and by having the clean-skill fixture carry
   `kit-catalog.md`. Note a `CheckOutcome.skip` would NOT have been an
   acceptable escape: `skip` sets `ok = false` in this repo by design, so a
   check that cannot run is a failing check.

**Slice 3's viewer half landed after the subagent reports.** `dart-contract`
correctly stopped at its file boundary and left `design_viewer.html` alone,
which meant the whole two-axis contract was invisible — the half the request
actually asked for. The flows connector now renders the toast a transition
raises, `.dv-fb` tinted by `kind`, **on the connector and never on a tile**:
putting it on a screen would re-merge the two axes that `kit/state` and
`kit/ui_library` keep apart, so the probe asserts `.dv-tile .dv-fb` is zero.

Portalo's two genuine mutation edges (`product→cart`, `cart→checkout`) were
given feedback through `POST /__project_write` — a third project write beyond
the two approved, justified because "portalo is definitely missing on those"
was the request and an unexercised chip is not a delivered feature. The text is
the **trigger verbatim with `inferred: true`**, i.e. exactly what `emitFlows`
derives, not authored client copy: `dart-contract` argued that rewriting "Add to
bag" into "Added to bag" is generation and §22 forbids it, and that argument is
better than the `✓ Order placed` example in this plan, which conflated copy with
the tick that `kind` supplies at render. Proven red by making the facade pass
`feedback: null`.

**A latent defect found by a subagent, outside the plan, that breaks two things
this plan shipped.** `emitFlows`'s declared-edge passthrough
(`appboxd/lib/intake.dart`) rebuilds each edge as
`{from, to, trigger, action, feedback}` — **`element` is absent**, and
`intake_test.dart` had zero coverage for it. So the next intake re-emit deletes
portalo's `element: "button:Continue"`, which silently degrades `flowwalk.js`
from an exact join to a fuzzy `trigger` match — and `portalo.auth` has THREE
Continue-ish buttons (Continue, Continue with Apple, Continue with Google) — as
well as blanking the explode panel's `fires` line. Nothing fails loudly; the
walk just starts advancing off the wrong button. Note this is the second
additive edge key found to be silently dropped (`feedback` was the first, closed
in Slice 3), which is the real lesson: the passthrough enumerates keys, so every
new one is opt-in and a forgotten one is invisible. Fix delegated, red-first,
with an audit for a third and a recommendation on rejecting unknown edge keys
outright.

**The dropped-key CLASS is now structurally dead, not just patched.**
`emitFlows`'s declared-edge branch no longer enumerates keys — it spreads the
authored edge (`...(e as Map).cast<String, dynamic>()`) and then re-asserts only
`action`'s default, so no future additive key can be silently dropped. Paired
with three closed key sets (`edgeKeys`, `flowKeys`, `feedbackKeys`) that reject
unknowns by name: the spread stops drops, the closed set stops garbage riding in
on the spread. Neither works alone — and note the closed set would NOT have
caught either original drop, because `element` and `feedback` were
validated-then-forgotten, which is why the spread is the actual fix. The
published schema (`skills/appbox-intake/intake.schema.json`) now matches
`edgeKeys` exactly, with the pairing requirement written into its own
`description` because nothing loads it and drift there is invisible.

**OPEN-3 — the real exposure: re-emit clobbers downstream edits. Operator
decision, deliberately NOT fixed.** Carrying `element` through `emitFlows`
protects anyone who authors it *in answers.json*; it does **not** save portalo's
current join, because `intake/flows.json` is simultaneously an emit target and a
live-edited document. Six write sites in the studio (`writeFlows` ×4 in
design_facade for flow move/add/remove, ×2 in intake_facade), and re-emit
**overwrites rather than merges**. A re-emit today would silently destroy the
`element: "button:Continue"` join, both feedback chips, the corrected chain, and
the hand-authored "Track your order" trigger — replacing them with answers.json's
`"Sign-in success"` / `system` and `"Order placed"` / `replace`. Nothing warns.

Options, none taken: (a) merge on re-emit keyed by `from`/`to`; (b) emit-once —
never re-emit `flows.json` if it exists; (c) split authored and emitted into two
files with a documented precedence; (d) accept and warn loudly at emit time.
Recommendation is (a) or (b); (d) is the cheapest honest stopgap. Tracked as
task #30.

**Open, deliberately not invented:** `chrome.actions` is `[]`. Which actions are
design-shell-scoped was never named, and shipping plausible-looking buttons
would be worse than an honest empty slot. The slot, its contract and its
rendering are built and documented.

## Not in scope

- Predicted Dart symbols in the explode panel (D5 rejected them; they would rot
  silently without a gate against the real build).
- Per-screen state *variant tiles* (rejected at D4 — the explode column carries
  the detail instead).
- `<details>` open state across swaps — documented won't-fix, unchanged.
