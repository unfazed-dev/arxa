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
2. `design/anatomy_flag.ts` (default empty ⇒ no behaviour change) +
   `?abxShell=` query-param selector in `routes.design.js`.
3. New shell composition `design/anatomy/_shared_anatomy.tsx` mirroring
   `_shared.tsx` in the hub > shell > view > widgets vocabulary, emitting the
   triple on every surface, `shell.surface` spelling for shell-level surfaces.
4. Port views one at a time under `design/anatomy/{chat,freeze,prototype}/`.
5. Extend `probe_inspect.dart` (do not fork) to fetch each screen twice from the
   same running server — `?abxShell=legacy` then `?abxShell=anatomy` — and diff
   the inspect attribute trees. Reuse existing `ProbeReport` / `ProbeTarget`;
   no new harness (Q11 rule).
6. Flip views in `abxAnatomyViews` only as each probe goes green.

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
vocabulary for the node slot. Awaiting team-lead confirmation on the spelling.

("Stamped at emit time" is no longer open — identity is a module-level const on
each surface, "never inferred at runtime". No route-level prop threading, no
TSX-rewriting build step.)
