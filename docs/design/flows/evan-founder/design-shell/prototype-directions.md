# Prototype directions — three, authored while designing

Actor: Evan (founder, design mode) · Shell: design-shell · Surfaces:
`design.directions` → `stage_shell_design_directions_view` (3-up · one
selected), `design.surface` → `stage_shell_design_surface_view` (live preview ·
stale) · Decision refs: architecture.md §13 (htmx producer is already MVVM),
§14 (authored registry → derived tree → generated structure.json), §19 (designer
is a fork under MIT), §11 (viewport ladder)

## Trigger

Evan lands in design-shell from `new-project` — project created, targets in
pipeline state. He generates three prototype directions before approving one.

## Entry / exit

- Entry criteria: project created (`new-project.md`); targets in pipeline state
  — platform set, viewports derived (§11); the designer harness reachable.
- Exit states: **selected** — one direction chosen, its authored structure
  bound as the design-hash candidate → `approve-design.md` (Gate 1) ·
  **iterating** — revise a direction before selecting →
  `iterate-direction.md` · **blocked** — `none` harness mode with the designer
  (an LLM stage) marked `blocked` (§7).

## Happy path

1. `design-shell` opens carrying targets from state. Viewport set is the derived
   union — `ios,android` → mobile + tablet; `macos` → desktop; mobile is always
   present (§11).
2. `app-box-designer` produces **three directions**. Each is a Hono + htmx MVVM
   app with **zero custom client-side JS** — `X_view.html` + `X_viewmodel.js`
   pairs under `ui/views/<shell>/<tab>/<surface>/`, plus
   `services/{repositories,facades}/` and `app.routes.js` (§13).
3. Structure is **authored while designing, not inferred after**. Per viewmodel
   the producer declares `export const surfaceId = '…';` and writes
   `registry.json` (ids, tabs, comps, surface bindings, role gating). The
   three-layer split holds (§14): authored registry (designer) → derived
   `ui/views/**` + `app.routes.js` (producer) → generated `structure.json`
   (`emit_structure`, never a human).
4. `design.directions` renders **3-up** (`stage_shell_design_directions_view`)
   — three side by side at compact width.
5. Evan opens each in `design.surface` (`stage_shell_design_surface_view`) and
   cycles the **active viewport widths** — 390 / 744 / 1280, rendered *inside*
   each class never on its boundary (§11).
6. Evan selects one; its registry + tree become the design-hash candidate.
   Route to `approve-design.md` **(Gate 1)** — agent reaches, person mints the
   token (§12, §17).

## Decision points

- **3-up then select vs iterate:** preview all three → select → Gate 1; or
  revise before selecting → `iterate-direction.md` (re-run the designer for one
  direction, re-freeze, mark siblings stale).
- **Viewport preview width:** the preview offers exactly the derived set — a
  phone-only target never offers desktop; `macos` never offers layouts beyond
  the always-present compact baseline.
- **`none` harness mode:** the designer is an LLM stage; under `none` it is
  `blocked` and no directions are produced — a determinism measurement, not a
  degradation (§7).

## Edge cases

- **A direction missing tablet/desktop layout:** the viewport ladder catches it
  (§11). The coverage gate requires exactly the derived set; a direction
  authored only at 390px is shown incomplete — flagged, not frozen.
- **Producer invents layout instead of carrying structure:** the
  headtohead-train-shell finding. A direction whose producer branch-matrixes
  layout (conditional rendering) rather than declaring it does not translate —
  the JSX producer captured 7 of 112 nodes that way (§13). Declared structure
  (registry data, `surfaceId`) survives a language change; invented layout does
  not. Such a direction shows `registry: null`, `tabRoots: {}` — filename-
  inferred, not authored — flagged for re-authoring, never silently passed.
- **Stale preview:** `design.surface` renders the last frozen render. If the
  underlying design moved (Evan iterated, the designer re-ran), the preview
  carries a **stale** indicator until re-rendered — never silently fresh.
- **Offline:** the designer needs the harness; offline blocks the LLM stage
  typed, never silent (§7).
- **Partial output:** fewer than three directions returned → the 3-up shows what
  exists with empty slots labelled, never fabricated directions.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | design-shell open (targets carried from `projects-shell` state) |
| 2–3 | designer run — stage transitions in pipeline state, not a surface |
| 4 | `stage_shell_design_directions_view` — 3-up, one selectable |
| 5 | `stage_shell_design_surface_view` — live preview at active viewport widths |
| 6 | `stage_shell_design_directions_view` — selection → route to Gate 1 |

## Notes

- `app-box-designer` is a **fork of `kimi-design-htmx` under MIT** (lineage
  baoyu-design → kimi-design → kimi-design-htmx), not a clean-room rewrite
  (§19). It ships `DESIGN-ARCHITECTURE.md` v1.0.0, `CONTEXT.md`, and
  `docs/adr/0001–0008`; app_box adds the viewport ladder (390/744/1280),
  `export const surfaceId`, a `tabRoots` source, and the `registry.json`
  convention `emit_structure` reads.
- The three-layer split (§14) is a genuine hybrid because the authored layer is
  a *different shape* from the generated one — a declarative id table, not
  screen records. `structure.json` stays a pure function of registry + tree,
  neither of which is itself: no two-writers-one-artifact.
- Sibling flows: `approve-design.md` (Gate 1 — the chosen direction's structure
  is hash-bound there) and `iterate-direction.md` (revise before selecting).
- The directions view is a **viewer over the authored artifacts in `design/`**,
  never a source of truth — same UI contract as the build view (§5, §8).
