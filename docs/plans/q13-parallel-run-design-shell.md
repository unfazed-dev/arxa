# Q13 — Parallel-run showcase-anatomy design shell

Status: plan ratified against verified repo state (not yet implemented).
Scope: generate the new showcase-anatomy design shell alongside the current
studio design shell, behind a flag; probes dual-render and diff; view-by-view
cutover. Deletion of the old shell is explicitly NOT in this run's scope.

## Verified ground truth (checked, not assumed)

Substrate is **Hono JSX / TSX, server-rendered**, under `designs/appbox-studio/ui/`.
The Q11 Flutter goldens (`tool/spike-q11-shells/`) were the *scaffolder-side*
proof; Q13 operates on the studio design and is probed via CDP.

Hosted shells live **nested inside `main_shell`**, not at `views/` top level:

```
designs/appbox-studio/ui/views/
  app_shell/        startup, unknown, auth, splash, dashboard   (ceremony + hub)
  main_shell/       outer chrome; Base + header/footer panels
    build/ design/ intake/ scaffold/ shared/                    (hosted shells)
  workspace_shell/  config, credentials, plans, settings
```

`main_shell_view.tsx` (69 lines) takes `activeShell: string` and a `surface?:
Child` slot; hosted shells mount into it by passing a surface.

Enumerated `activeShell` values (from code, not comments):
`app, build, design, intake, scaffold, workspace`.

**The design shell is `views/main_shell/design/`** — NOT `workspace_shell`
(`workspace_shell` sets `activeShell: 'workspace'` and holds account/project
administration). This was the discriminating check; record it so the mistake is
not re-made.

Design shell contents and sizes:

| File | Lines | Role |
|---|---|---|
| `design/_shared.tsx` | 325 | shared composition for the hosted shell |
| `design/inspector_pane.tsx` | 325 | inspector pane |
| `design/routes.design.js` | 56 | route table |
| `design/prototype/prototype_view.tsx` | 160 | view |
| `design/freeze/freeze_view.tsx` | 227 | view |
| `design/chat/chat_view.tsx` | 60 | view |
| `design/_integration_design.md` | — | integration doc |

The three cutover units are therefore **chat, freeze, prototype**.

## Two blocking findings that constrain implementation

### 1. `inspectAttrs` is TWO different things — name collision, already in repo

The normative JS form is `skills/appbox-designer/references/app-architecture.md`
(§"Every surface stamps its inspect identity"), verbatim:

```js
export const surfaceId = 'train.library';
export const inspectAttrs = {
  screenId: 'train.library',        // registry screen id
  surfaceId: 'train.library',       // this surface
  nodeId: 'anatomy:view.body',      // anatomy-node id
};
```

That is a **module-level exported const object, one per surface**. The decisions
doc line 145 requires this JS form and the Dart shape stay **1:1**.

But `designs/appbox-studio/ui/common/widgets/primitives.tsx` already defines
`inspectAttrs` as a **function**, `(name, meta) => Record<string,string>`,
producing `data-el` / `data-inspect-role|style|motion|fn` — **per widget**, and
its own comment calls itself "the ONE source of widget inspect identity".

Same name, different arity, different granularity, different purpose. This
collision predates Q13.

**Resolution — do not touch the widget function.** The triple is a *surface*
stamp (decisions L85/L146: "every emitted **surface** carries the triple"), not
a widget stamp. So:

- The widget-level `inspectAttrs(name, meta)` function stays exactly as-is.
  Old-shell markup is byte-stable for free — the tension the earlier draft of
  this plan tried to resolve does not exist.
- Each new-shell surface module exports the normative const pair
  (`surfaceId`, `inspectAttrs`) and spreads it onto the surface root element as
  `data-screen-id` / `data-surface-id` / `data-node-id` so CDP can read it.

**Naming discrepancy to confirm:** the task brief says the third key is
`anatomyNodeId`; the normative JS form says **`nodeId`** (with `anatomy:` as the
*value* prefix). Since the JS form is the ratified authority and must stay 1:1
with Dart, this plan uses `nodeId`. Flagged to team-lead.

### 2. There is no existing feature-flag mechanism

Grepped for `featureFlag`, `process.env`, `APPBOX_*` inside `designs/` — zero
hits. `design_server.dart` reads env only for `PORT`, `HOST`, `APPBOX_PROJECT`.

`activeShell` is the existing *shell selection* mechanism, but it selects which
hosted shell renders — it is shell-level, whereas Q13 cutover is **per view**.
Adding a new `activeShell: 'design2'` value would both mis-model the granularity
and add a shell to a closed vocabulary. Rejected.

**Resolution — minimal, no framework:** one module,
`design/anatomy_flag.ts`, exporting a per-view set threaded as a sibling prop on
the path `activeShell` already travels:

```ts
export const abxAnatomyViews: ReadonlySet<string> = new Set([]); // empty = old shell everywhere
export function usesAnatomy(view: string): boolean
```

Default empty ⇒ behaviour is byte-identical to today until a view is flipped.
Flipping = add the view name; flipping back = remove it. Toggle, not revert.

**The override must be request-level, not an env var.** Verified: probes
*attach* to an already-running `design_server` — `probe_base.dart` resolves the
target via `--base` / `--port` / `APPBOX_BASE` with a `4319` default and has no
`Process.start`. So an env var set on the probe process never reaches the server
process, and `APPBOX_ANATOMY_VIEWS` would silently do nothing at step 5.

Dual-render therefore uses a **query-param selector** read by
`routes.design.js` per request, e.g. `?abxShell=anatomy` / `?abxShell=legacy`,
falling back to `abxAnatomyViews` when absent. One running server can then
render both shells, which is what the diff needs.

## Implementation order

1. Nothing in `primitives.tsx`. The widget-level `inspectAttrs` function is
   correct as-is; the triple is a surface-level const stamp (see finding 1).
2. **No new flag mechanism — `activeShell` already is one.** See finding 5.
   Read `c.req.query('abxShell')` in each view's `page` handler, defaulting via
   `abxAnatomyViews`, and pass `activeShell: 'design' | 'anatomy'`.
3. New shell composition `design/anatomy/_shared_anatomy.tsx` mirroring
   `_shared.tsx` in the hub > shell > view > widgets vocabulary, emitting the
   triple on every surface, `shell.surface` spelling for shell-level surfaces.
4. Port views one at a time under `design/anatomy/{chat,freeze,prototype}/`.
5. Extend `probe_inspect.dart` (do not fork) to fetch each screen twice from the
   same running server — `?abxShell=legacy` then `?abxShell=anatomy` — and diff
   the inspect attribute trees. Reuse existing `ProbeReport` / `ProbeTarget`;
   no new harness (Q11 rule).
6. Flip views in `abxAnatomyViews` only as each probe goes green.

## Finding 5 — the flag already exists; it is `activeShell`

`routes.design.js` is a **static `[method, path, handler]` array**, not a request
handler — it cannot read a query param. My earlier "selector in
`routes.design.js`" placement was wrong.

The real seam is one level down, and it is already built. Every view's page
handler has the shape:

    export const page = (c, h) =>
      h.render(c, VIEW, { activeShell: 'design', ...facade.stageContext(...) });

`activeShell` is an existing render prop threaded through the shell composition.
Selecting a shell is therefore a **value change on a prop that already exists**,
not a new mechanism — which is exactly the "find the existing flag; do not
invent a framework" instruction. `c.req.query('...')` is likewise the
established pattern (`prototype_viewmodel.js` uses it ~10×).

Consequence: the cutover unit is the `page` handler of each view, which lines up
with view-by-view cutover with no extra indirection. `abxAnatomyViews` supplies
the default when `?abxShell=` is absent.

## Constraints carried into every step

- Layout values are kit constant names only: `abxPad*`, `abxGap*`,
  `abxHug`/`abxFill`/`abxFixed`, `appBoxKitVerticalSpace*` /
  `appBoxKitHorizontalSpace*`. A raw numeric literal where a kit constant
  exists = FAIL.
- All new constants carry the `abx` prefix; strings use `abxStr*`.
- Vocabulary: hub > shell > view > widgets. No "surface/body/chrome/screen/
  page" in new user-facing or doc text, except the ratified `shell.surface`
  inspectAttrs spelling.
- Anatomy vocabulary is closed at 1 member: `anatomy:view.body`.
- Registry: `skills/appbox-scaffolder/kind-resolution.registry.json` v1.2.0.
- Do not delete the old shell.

## Finding 3 — `nodeId` vs `anatomyNodeId` is not a conflict

`app-architecture.md:184` settles it outright: "Dart spells this slot
`anatomyNodeId`, JS spells it `nodeId` — **one slot, two spellings**." Both are
ratified. The Q11 spike golden confirms the Dart side
(`AppBoxKitInspectAttrs(screenId:, surfaceId:, anatomyNodeId:)`). TSX therefore
uses `nodeId`; nothing to arbitrate.

## Finding 4 — the DOM spelling of the triple does not exist yet (BLOCKING step 5)

`app-architecture.md:180` says the triple's presence "is mechanically enforced
by the probe". It currently is not, and cannot be:

- `probe_inspect.dart` (`appboxd/lib/probes/studio/`) parses only `data-el`,
  `data-inspect-role|style|fn`, `data-inspect-armed`, `data-id`. It never reads
  screen/surface/node identity.
- No `data-screen-id` / `data-surface-id` / `data-node-id` exists anywhere in
  `skills/`. The only neighbours are `data-surface` (`runtime/vendor/inspect.js`),
  `data-screen` (`runtime/vendor/drag.js`), `data-screen-label`.

So `inspectAttrs` is a JS object that no serializer spreads into markup. A
surface-level const that never reaches the DOM makes the step-5 diff compare
nothing — the same late-failure class as the env-var flag (finding 2).

**This must be settled before step 3**, because the shell's emit path is what
writes the attributes. Proposed minimal spelling, consistent with the existing
`data-inspect-*` prefix and avoiding the `data-surface` / `data-screen`
collisions already taken by the vendor runtime:

    data-inspect-screen   data-inspect-surface   data-inspect-node

with `probe_inspect.dart` extended to read those three and assert the closed
vocabulary for the node slot.

**RULED (team-lead + user, 2026-08-08):**
1. Spelling approved as proposed: `data-inspect-screen` / `data-inspect-surface`
   / `data-inspect-node`. Three carriers, one slot — record next to the JS
   (`nodeId`) and Dart (`anatomyNodeId`) spellings.
2. Enforcement is in Q13 scope for the NEW shell only: new emit path writes the
   triple; `probe_inspect.dart` reads the three attributes and asserts the node
   slot against the closed registry vocabulary.
3. **Back-stamp of the old shell: skipped, by user ruling** — old shell dies at
   cutover, stamping it is wasted work. Old-shell probe runs report identity as
   N/A-unstamped (never PASS, never FAIL) through end of life.
4. `app-architecture.md:180` amended in the same commit as the probe extension:
   enforced-for-stamped-surfaces; old shell deliberately unstamped pending
   removal at cutover.

("Stamped at emit time" is no longer open — identity is a module-level const on
each surface, "never inferred at runtime". No route-level prop threading, no
TSX-rewriting build step.)

---

# RULINGS (team-lead) — operative authority for this run

Three ruling messages arrived, written against successive states of my
corrections. Where they disagree, **the later one wins**, because the earlier
was reasoning from premises I subsequently disproved. Reconciled below.

## R1 — Sibling `anatomyAttrs`: NOT built

Msg1 approved a sibling emitter; msg2 retracted it ("disregard the sibling")
after accepting that `inspectAttrs` is a name collision. **Msg2 governs.**
`primitives.tsx` is untouched, old-shell markup is byte-stable for free.

Both messages reach the same *goal* by different means — msg1 wanted the diff
baseline uncontaminated via a sibling, msg2 gets it for free because the triple
was never a widget-level concern. Recorded as debt: if the two attr emitters
should merge post-cutover, that is a deliberate follow-up, not mid-run work.

**Also recorded as pre-existing (predates Q13, not mine to fix):** `inspectAttrs`
names two different things — a per-widget *function* in `primitives.tsx`
(`data-el`, `data-inspect-role|style|fn`) and a per-surface *module const* in
`app-architecture.md` (`{screenId, surfaceId, nodeId}`). Anyone grepping the
name needs this warning.

## R2 — Emit mechanism: surface-level module const (msg1 point 4 superseded)

Msg1 ruled "route-level threading IS emit time", reasoning that props flowing
from `routes.design.js` are statically determined. Msg2 ruled "the triple is a
surface-level module const per app-architecture.md". **These are different
mechanisms and cannot both be built.** Msg2 governs, for two independent
reasons:

1. It is later and it is what the primary source shows (`app-architecture.md`
   §"Every surface stamps its inspect identity" — an `export const` in the
   surface module).
2. Msg1's mechanism is not physically available: `routes.design.js` is a static
   `[method, path, handler]` array with no request object (finding 5). It cannot
   thread anything.

Msg1's *principle* is preserved and is the part that mattered: identity must
never be inferred at runtime from DOM heuristics. A module const satisfies that
more strictly than threading does.

## R3 — Flag: `abxAnatomyViews`, but no env override for probes

Approved: `design/anatomy_flag.ts` exporting `abxAnatomyViews` (default empty ⇒
byte-identical today), `abx` prefix retained, and request-level
`?abxShell=anatomy|legacy` overriding it. Rejecting a `design2` `activeShell`
value is confirmed correct — wrong granularity, and it would widen a closed
vocabulary.

**One approved item is inert and must not be relied on:** `APPBOX_ANATOMY_VIEWS`
as a *probe* override cannot work — probes attach to an already-running server
(finding 2), so an env var in the probe process never reaches the renderer. It
survives only as a *server-process* default, read at server start. The
probe-side selector is the query param. Building it as approved would reproduce
exactly the silent-green failure msg2 credited me for catching.

## R4 — Identity slot: three carriers, one slot

Per msg2 plus `app-architecture.md:184`. Listed together so all three spellings
of the single slot are findable in one place:

| Carrier | Screen | Surface | Node |
|---|---|---|---|
| JS / TSX | `screenId` | `surfaceId` | `nodeId` |
| Dart | `screenId` | `surfaceId` | `anatomyNodeId` |
| DOM | `data-inspect-screen` | `data-inspect-surface` | `data-inspect-node` |

Node value carries the `anatomy:` prefix (`anatomy:view.body`); vocabulary
CLOSED at 1 member, registry v1.2.0.

**No escalation needed on L145.** Msg2 offered to take the "1:1" wording to the
user if I read it as forbidding the spelling split. I do not: `app-architecture.md:184`
states the split explicitly — "Dart spells this slot `anatomyNodeId`, JS spells
it `nodeId` — one slot, two spellings" — so shape-and-values 1:1 is the reading
the source already ratifies. Dart is not renamed. Question closed, not escalated.

## R5 — Enforcement scope: new shell only

- **IN:** new shell's emit path writes the three attrs; `probe_inspect.dart`
  extended to read them and assert the node slot against the closed registry
  vocabulary. Additive; does not touch old-shell markup.
- **OUT:** back-stamping the old shell. Crosses "do not delete" into "modify".
  Pending user ruling.
- **Old-shell identity verdict is `N/A-unstamped`, never `PASS`.** Absence is
  the expected-and-recorded state. A green identity verdict on an unstamped
  shell would be precisely the vacuous pass this run exists to prevent.

## R6 — Diff normalization rule

When diffing old vs new shell output, **strip `data-inspect-screen`,
`data-inspect-surface`, `data-inspect-node` before the structural comparison.**
The new shell legitimately carries attributes the old one does not; the diff
verdict is about rendered structure and behaviour, not about the identity attrs
I was told to add. Without this rule a future reader would read attr deltas as
regressions.

Note the interaction with R5: identity is *stripped* from the structural diff
and asserted *separately* on the new side only. Two verdicts per view, never
merged into one.

## R7 — `app-architecture.md:180` must be amended in the same commit

The line claims enforcement exists; it does not (finding 4). Amend to state the
mechanism precisely — enforced by the probe for surfaces carrying
`data-inspect-*` stamps; old-shell back-stamp pending user ruling — landing in
the **same commit** as the probe extension so the doc is never true-by-
anticipation (bb451c5 precedent).

## R8 — Cutover table (authoritative)

`activeShell` enumerated set: `app, build, design, intake, scaffold, workspace`.
Cutover units = the three design views, flipped independently:

| View | Route root | Handler | Shell verdict | Identity verdict |
|---|---|---|---|---|
| chat | `/design/chat` | `chat.page` | pending | pending |
| freeze | `/design/freeze` | `freeze.page` | pending | pending |
| prototype | `/design` | `prototype.page` | pending | pending |

Flip = swap the `VIEW` template path in that view's `page` handler (see
finding 6 — **not** the `activeShell` value). Flip back = swap the path back:
toggle, not revert.

---

## Finding 6 — `activeShell` is NOT a shell selector (retracts finding 5)

Finding 5 claimed `activeShell` was the existing flag. **It is not.** Every one
of its ~38 uses is navigation-chrome state:

    // common/widgets/chrome.tsx
    const activeLabel = dests.find((d) => d.id === activeShell)?.label ?? activeShell;
    class={`shell-link${activeShell === d.id ? ' is-active' : ''}`}
    aria-current={activeShell === d.id ? 'page' : undefined}

It highlights which destination is current in the rail / tabbar / drawer. It
selects nothing and dispatches to no component. Setting `activeShell: 'anatomy'`
would render the *same* shell with *broken nav highlighting* — no destination
id would match, so no link would be marked active and `activeLabel` would fall
back to the raw string. A silent cosmetic regression, not a shell switch.

**`activeShell` must therefore stay `'design'` in BOTH shells.** This is not
optional: changing it alters chrome markup and would pollute the structural
diff with nav deltas — the diff would report differences that have nothing to do
with the shell rewrite.

This also gives R3's "reject a `design2` value" a stronger reason than the one
recorded: it is not merely that `design2` widens a closed vocabulary, it is that
`activeShell` is the wrong *kind* of thing to encode a shell variant in. The
vocabulary is closed because it enumerates **nav destinations**.

### The actual seam

`VIEW` is a module-level **template path string**:

    const VIEW = 'ui/views/main_shell/design/chat/chat_view.html';
    export const page = (c, h) => h.render(c, VIEW, { activeShell: 'design', ... });

`h.render(c, VIEW, props)` resolves that path. Shell selection is therefore
**which template path the handler passes** — already a variable, already
per-view, already the exact granularity of the cutover unit. The flag becomes:

    const VIEW         = 'ui/views/main_shell/design/chat/chat_view.html';
    const VIEW_ANATOMY = 'ui/views/main_shell/design/anatomy/chat/chat_view.html';
    export const page = (c, h) =>
      h.render(c, abxResolveShellView(c, 'chat', VIEW, VIEW_ANATOMY),
               { activeShell: 'design', ... });

with `abxResolveShellView` in `design/anatomy_flag.ts` reading
`c.req.query('abxShell')` then falling back to `abxAnatomyViews`.

### Open item this raises

`VIEW` points at `.html`, but only `.tsx` exists on disk. I first inferred "the
renderer just maps the extension, so no wiring is needed." **That inference was
the same shape as the one that killed finding 5** — inferring a dispatch
mechanism from a grep that had returned empty because the glob failed to expand.
Silence was read as evidence. It is not.

What the evidence actually shows:

    // services/repositories/widget_repository.js:29,33
    // .tsx is what the renderer renders; .html is the pre-TSX fallback for ...
    return surfaceFiles().includes(`${base}.tsx`) ? `${base}.tsx` : `${base}.html`;

    // services/repositories/project_repository.js:212
    // .html is the pre-TSX fallback) in globalThis.__templates under the render
    // registry's viewRef — ui/project/<kind>.html (generateRenderTsx).

So `.html` is a **legacy viewRef key**, and resolution goes through a *render
registry* (`globalThis.__templates`, keyed by viewRef) plus a `surfaceFiles()`
enumeration that prefers `.tsx` when present. There is a resolver and there is a
registry. Directionally my guess was right; the part that matters — whether a
brand-new `design/anatomy/chat/` path is picked up automatically or must be
registered — is **still untraced**.

### RESOLVED — no registry entry needed, and now verified rather than inferred

Traced. Two of the three candidates were red herrings:

- **`surfaceFiles()` / `screenFile()` is not this subsystem.** It reads
  `project-src/index.json` and resolves `design/surfaces/<name>.tsx` — the
  *user's project* surfaces, not the studio's own `ui/views/**`.
- **`globalThis.__templates` renders nothing.** `worker.dart:134` calls it a
  "project-surface presence map", and line 218 states outright: *"templates map
  is presence-only now (nothing renders from it)"*.

The real path is a **generated render bundle** (`design_tools.dart`,
`generateRenderTsx`). It walks the artifact tree —

    // design_tools.dart:1439 (and :546)
    if (!f.path.endsWith('.html') && !f.path.endsWith('.tsx')) continue;

— and emits a static import plus a registry entry per view:

    const registry: Record<string, ComponentMap> = {
      'ui/views/main_shell/design/chat/chat_view.html': { default: ChatView, ... },
    };
    export function render(viewRef, ctx) {
      const hash = viewRef.indexOf('#');
      const file = hash === -1 ? viewRef : viewRef.slice(0, hash);
      ...

**This is a directory scan, not a manifest.** A new `.tsx` under the scanned
tree is picked up automatically. `htmlKey` is the `.html`-normalized registry
key regardless of whether the source is `.tsx` — which is precisely why
`VIEW = '.../chat_view.html'` resolves a `chat_view.tsx` file
(`design_tools.dart:587` — *"Try the literal path first, then .tsx"*).

So: **no build wiring, no registry entry.** Emitting
`design/anatomy/chat/chat_view.tsx` and pointing `VIEW_ANATOMY` at
`design/anatomy/chat/chat_view.html` is sufficient. The conclusion matches my
first guess; the difference is that it now rests on the generator source rather
than on absence-of-grep-output. Recording both the guess and the verification
because the guess was not yet knowledge when I made it.

### Incidental find — viewRef supports `#fragment`

`render()` splits `viewRef` on `#` and selects a named export. So
`'chat_view.html#anatomy'` is a *second* viable seam: both shells in one file,
selected by fragment. **Not chosen** — separate files keep the two trees
independently diffable, which is the whole point of the parallel run (and is
what R2's "old-shell markup must stay byte-stable" requires). Recorded so the
next reader doesn't rediscover it and assume it was overlooked.

---

## Ruling ledger — authoritative state (supersedes scattered messages)

Three team-lead messages arrived out of order; two were written before my
retraction landed. **Reading any one of them alone will produce the wrong
implementation.** This section is the single authoritative copy.

### SUPERSEDED — do not implement

> *"activeShell finding: approved. Value change on the existing render prop is
> the right seam; deleting `anatomy_flag.ts` from the plan is correct."*

This approved my **retracted** finding 5. It predates the retraction and is
**void on both clauses**:

- Value-change on `activeShell` is *not* the seam (finding 6 — it is nav-chrome
  state; changing it breaks nav highlighting and pollutes the diff).
- `anatomy_flag.ts` is **not** deleted — it is reinstated as the shared-helper
  module by the later ruling below.

Later message: *"Retraction accepted. `activeShell` stays `'design'` in both
shells — locked."* That governs.

### LOCKED rulings

| # | Ruling |
|---|---|
| R-a | `activeShell` frozen at `'design'` in both shells. Rationale of record: it enumerates **nav destinations**, so it is the wrong *kind* of field for a shell variant, and changing it would pollute the structural diff with nav-chrome deltas. |
| R-b | Seam = `VIEW` template-path swap, per-view, toggle-not-revert. |
| R-c | Query read lives in each view's `page` handler. `routes.design.js` is a static array that cannot read a request — letter and spirit agree, no drift. |
| R-d | **One shared helper**, single module, imported by all three handlers — no copy-pasted resolution logic: `abxResolveShellView(c, viewName, VIEW, VIEW_ANATOMY)`, falling back to `abxAnatomyViews` when the query param is absent. |
| R-e | Triple spelling `data-inspect-screen` / `data-inspect-surface` / `data-inspect-node`. Record DOM spelling alongside JS (`nodeId`) and Dart (`anatomyNodeId`) — three carriers, one slot. |
| R-f | Enforcement is **new-shell only**. Old shell untouched; its probe runs report identity **N/A-unstamped** — never PASS, never FAIL. |
| R-g | **Back-stamp skipped by user ruling.** Old shell dies at cutover, so stamping it is wasted work. N/A-unstamped stands through end of life. |
| R-h | `app-architecture.md:180` amended **in the same commit** as the probe extension: enforcement applies to stamped surfaces, old shell deliberately unstamped **pending its removal at cutover** — *not* "pending user ruling" (that ruling has landed). Claim must never be true-by-anticipation (bb451c5 precedent). |

### Correction to the trace instruction (R-i)

The trace was ordered as: *"Resolve whether `surfaceFiles()` +
`globalThis.__templates` auto-enumerate a new `design/anatomy/` path or require
a registry entry."*

Already done — commit `95f4a81`. **But the instruction's premise was itself
wrong**, and that matters for anyone re-deriving it: *neither* named mechanism
is the resolver. `surfaceFiles()` is the user project's surfaces;
`globalThis.__templates` is presence-only and renders nothing
(`worker.dart:218`). The real resolver is the generated render bundle, and it
**directory-scans**. Answer is favourable — no registry entry, no wiring — but
it was reached by discarding both candidates, not by checking them.

Ruling anticipated this cost: *"fourth instance of the only-fails-after-build
class; spending one step on it is exactly the discipline the last three findings
bought."* Confirmed — the step paid for itself by killing a false premise.

---

## Remaining work (handoff state)

Everything is unblocked. Not started — deliberately left for a fresh context
budget rather than half-emitted:

1. `design/anatomy_flag.js` — `abxResolveShellView(c, viewName, VIEW, VIEW_ANATOMY)`, one module (R-d). **Extension corrected — see finding 7.**
2. New shell `design/anatomy/{chat,freeze,prototype}/*_view.tsx` + `_shared_anatomy.tsx`, emitting the R-e triple, `activeShell` hard-frozen at `'design'` (R-a).
3. Add `VIEW_ANATOMY` const + helper call to the three `page` handlers (R-b, R-c).
4. Extend `probe_inspect.dart` to read the three attributes and assert the node slot against the closed registry vocabulary; unstamped surfaces → N/A, not PASS (R-f, R-g).
5. Amend `app-architecture.md:180` **in the same commit as 4** (R-h).

---

## Finding 7 — the helper must be `.js`, not `.ts`

R-d specifies `design/anatomy_flag.ts`. That file would not load. Two
independent confirmations:

- Viewmodels are **native ESM with explicit extensions**:
  `import * as facade from '../../../../../services/facades/design_facade.js';`
  A runtime resolving that literally cannot import a `.ts` sibling.
- The eject copier takes **only three extensions**:

      // design_tools.dart:1360
      /// Copy all *.js, *.d.ts, and *.tsx files from [srcDir] to [dstDir] ...

  Plain `.ts` is not copied. The helper would vanish from the eject even if it
  loaded in dev.

**Use `anatomy_flag.js`.** (`.d.ts` alongside is permitted by the copier if
typing is wanted.) This is a mechanical correction to R-d, not a reopening of
it — placement, signature, and single-module constraint all stand.

---

## Finding 8 — the cutover unit is the viewmodel MODULE, not the `page` handler

R-b/R-c set the cutover unit at each view's `page` handler. But `page` is not
the only handler that renders `VIEW`. From `chat_viewmodel.js`:

    export const page = (c, h) =>
      h.render(c, VIEW, { activeShell: 'design', ... });

    export const context = (c, h) =>
      h.render(c, `${VIEW}#panelsSwap`, facade.toggleContext(...));

Sibling handlers render **fragments of the same template** (`${VIEW}#fragment`)
to service htmx partial swaps. If only `page` consults the flag, then on a
new-shell page every subsequent htmx swap re-renders **old-shell fragment markup
into the new-shell DOM**. The page would silently degrade into a hybrid after
the first interaction — and the probe, if it captures markup on first paint,
would not see it.

This is the same failure class as findings 5–7: a mechanism assumed to have one
call site that actually has several.

**Required refinement:** resolution must be per-*request* and shared by every
handler in the module, not per-handler:

    // anatomy_flag.js
    export const abxResolveShellView = (c, viewName, base, anatomy) => ...;

    // chat_viewmodel.js
    const shellView = (c) => abxResolveShellView(c, 'chat', VIEW, VIEW_ANATOMY);

    export const page    = (c, h) => h.render(c, shellView(c), { activeShell: 'design', ... });
    export const context = (c, h) => h.render(c, `${shellView(c)}#panelsSwap`, ...);

Cutover granularity is **unchanged** — still one view at a time, still
toggle-not-revert. What changes is that flipping a view means flipping *all*
handlers in that viewmodel together, because they render one template. The
per-view cutover table stays exactly as ruled; "cutover unit = `page` handler"
should read "= viewmodel module".

**Every handler in the module must be enumerated when a view is flipped.** A
missed sibling is a silent hybrid, not a visible break — the most expensive
kind of miss for a parallel run whose entire value is diff fidelity.
