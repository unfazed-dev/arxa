# kimitail findings — 2026-08-02 (post flows/.appbox refactor)

Standing instruction: document only. Review again after the full appbox
implementation lands. Findings are ranked; each names the file and the
smallest fix. `[kimitail: …]` markers in code point here.

## Debt (deliberate, tracked)

1. **Project-model migration is partial.** Only `design_model` + screen
   partials moved to `~/.appbox/projects/<name>/`. `intake_model` and
   `build_model` are still studio fixtures in
   `designs/appbox-studio/models/` — the intake (personas/surfaces steps) and
   build (evidence) surfaces show studio demo data, not the current
   project's. Fix when those stages go project-aware: same overlay pattern
   as design_model (server overlay already serves any project `**.json`).
2. **`gate_intake` is design-root-bound** (`appboxd/lib/gate_intake.dart` —
   zero project awareness). It gates the studio's own registry, not a
   project's. Fix: accept `--project <name>` and resolve
   registry/brief/answers from `~/.appbox/projects/<name>/intake/`.
3. **Hot reload misses nested JS modules.** The worker re-imports
   `app.routes.js` cache-busted, but browser-cached nested imports
   (`services/**`, viewmodels) survive — facade/VM edits need a cold
   restart. Templates/CSS/arbs/fixtures DO hot-reload. Fix if it bites:
   version-query every import in the worker loader.
4. **Selftest's route-200 sweep needs a populated `~/.appbox`.**
   `design selftest` boots with the current project overlaid
   (`design_selftest.dart`); on a machine with no projects the design
   routes 500. Fix: skip project-dependent routes when no overlay, or ship
   a fixture project for CI.

## Smells (small, real)

5. **Dead `strip: true` flag** on both facades' viewer context
   (`design_facade.js:399`, `build_facade.js:256`) — no template reads
   `v.strip` since the filmstrip moved to the composer tray. Delete both.
6. **Petal & Stem generic stubs** linger in `screen_stub_view.html`
   (home/cart/checkout/confirmation kinds) — only reachable for evidence
   surfaces with no project partial. Delete when build evidence moves to
   the project (finding 1).
7. **Historical plan doc references dead routes.**
   `docs/plans/media-3d-animation-games.md` cites `/media/*` routes and the
   graphics-demo Portalo. Keep as history; annotate the header as
   superseded by the ecommerce Portalo (Slice 2/3).

## Verified NOT debt (checked, closing)

- `models/screens_model/flows.json` vs `structure.json` flow edges:
  structure.json is GENERATED from the authored layer — not drift.
- The `.dv-zoom` non-wrapping row concern from the pre-flows viewer:
  superseded — the views lens wraps (flex-wrap) and flows rows are the
  intended single-row-per-flow layout.
