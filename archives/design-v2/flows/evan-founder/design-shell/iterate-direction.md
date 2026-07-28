# Iterate direction — revise a prototype before approving

Actor: Evan (founder, design mode) · Shell: design-shell · Surfaces:
`design.directions` → `stage_shell_design_directions_view` (3-up · one
selected), `design.surface` → `stage_shell_design_surface_view` (live ·
**stale**) · Decision refs: architecture.md §13 (htmx producer is MVVM),
§14 (authored → derived → generated), §11 (viewport ladder), §7 (`none` mode
is the measurement)

## Trigger

From `prototype-directions.md`: Evan picks one of the 3-up directions to
revise rather than approve. He enters iterate mode with free-text or structured
feedback ("wider hero", "fix the tablet nav").

## Entry / exit

- Entry criteria: a design phase is open; at least one direction is rendered
  in the 3-up. The **authored** layer (`models/screens_model/registry.json`)
  and the **derived** tree (`ui/views/**` `view`+`viewmodel` pairs) are the
  SSOT — the preview is a cached render of them, never the truth
  (architecture.md §14).
- Exit states: **revised** — new version generated, preview matches the
  authored tree, return to 3-up · **accepted-as-is** — Evan stops iterating and
  routes to `approve-design.md` (Gate 1) on the current direction ·
  **abandoned** — cancels; the prior version stands unchanged.

## Happy path

1. `design.directions` — Evan selects one direction in the 3-up and opens
   iterate. The selected direction's authored id is the join key — the producer
   declares `surfaceId`, so the join is an assertion, not a filename guess
   (architecture.md §13).
2. Evan enters feedback. The designer (htmx producer) re-runs against the
   selected direction: it edits the **authored** registry and re-emits the
   **derived** `view`/`viewmodel` pairs for that surface. `structure.json` is
   regenerated as *f*(registry, tree) — never hand-written (architecture.md
   §14).
3. While the producer runs, `design.surface` shows **stale**: the cached render
   no longer matches the authored tree. Stale is computed from working-tree
   drift (`git status --porcelain`), not from whether the WebView last painted
   (architecture.md §14–§15).
4. The producer completes; the preview re-renders the new version. **Stale**
   clears once the render's hash matches the current authored tree.
5. Evan returns to `design.directions` with the revised direction in the 3-up —
   ready to iterate again or route to Gate 1 (`approve-design.md`).

## Decision points

- **Iterate vs accept current:** after a revision lands, Evan either loops to
  step 2 with more feedback, or stops and routes to `approve-design.md`
  (Gate 1) on the current version.
- **Viewport-scoped revision:** feedback may target one viewport only ("tablet
  nav only"). This only holds for viewports in the derived set
  (architecture.md §11); a viewport absent from targets has no authored layout
  to revise.

## Edge cases

- **Re-generation differs from the last run:** the designer's LLM stages are
  non-deterministic — the same feedback may yield different output. The `none`
  harness mode reproduces only the deterministic fraction; that fraction *is*
  the run's determinism score. This is a measurement, not degradation
  (architecture.md §7).
- **Stale preview:** if Evan edits the authored tree (or the designer re-runs)
  after the preview rendered, `design.surface` shows **stale** until the render
  catches up. The indicator is driven by tree drift, never by paint
  (architecture.md §15).
- **Viewport ladder gap:** if Evan asks to revise a tablet/desktop layout that
  was never a target, the producer has nothing authored to revise — and
  downstream the freeze would invent that layout from a 390px render
  (architecture.md §11). Surface the gap; do not silently fabricate.
- **Producer adds a surface:** expected case — the drift check uses
  `git status --porcelain`, not `git diff`, so an added surface is visible, not
  swallowed (architecture.md §14).
- **Offline:** the deterministic producer stages need no network; LLM stages
  fail typed, never silent (architecture.md §7).

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | `stage_shell_design_directions_view` — 3-up, one direction selected |
| 2–4 | `stage_shell_design_surface_view` — live preview, **stale** → cleared |
| 5 | `stage_shell_design_directions_view` — revised 3-up → route to Gate 1 |

## Notes

- The authored layer is the SSOT; `design.surface` is a viewer over it.
  Everything it renders comes from the registry + the view/viewmodel tree
  (architecture.md §13–§14). Closing the app loses no authored work.
- Sibling flows: `prototype-directions.md` (the 3-up this enters from),
  `approve-design.md` ◆ **(Gate 1)** (where a revised direction exits to).
- MEM-A feeds prior iterate feedback into the next revision's prompt
  (architecture.md §4).
