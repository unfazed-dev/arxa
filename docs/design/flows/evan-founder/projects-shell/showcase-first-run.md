# Showcase — first run (the dogfood)

Actor: Evan (founder, first launch) · Shell: projects-shell · Surfaces:
`projects.splash` → _null_ (first-run) · `projects.showcase` → _null_ (the
dogfood — app_box shows itself) · `projects.home` →
`stage_shell_projects_home_view` (empty) · Decision refs: architecture.md §8
(desktop app — dogfood, bootstrap caveat), §9 build order step 7 (desktop UI),
§11/§16 (macOS → one viewport, 3 files/surface)

## Trigger

First install/launch of the desktop app. A first-run flag (a local preference,
not pipeline state in `work/`) is what gates the auto-launch.

## Entry / exit

- Entry criteria: the app binary is installed and launches on macOS; no prior
  first-run completion is recorded.
- Exit states: **showcase viewed** — Evan saw and dismissed the dogfood, lands
  on `projects.home` (empty) · **showcase skipped** — dismissed before the app
  painted; flag still clears, lands on `projects.home` (empty).

## Happy path

1. App launches; `projects.splash` (null surface) shows the brand splash —
   first-run onboarding.
2. The showcase app launches as a separate macOS window: `projects.showcase`
   (null surface — the dogfood). Evan is looking at a real Flutter app built
   by the pipeline. `--targets macos` → one viewport (1280), three files per
   surface (§11/§16).
3. Evan explores the showcase. This IS the proof — the pipeline's output is the
   UI on screen. For Evan, the showcase demonstrates the pipeline works on its
   own UI.
4. Evan dismisses the showcase. The first-run flag clears (local preference).
5. Control lands on `projects.home` → `stage_shell_projects_home_view` in its
   **empty** state — no projects yet, wording per `project-list-home.md`.

## Decision points

- **First run vs subsequent:** first run → showcase auto-launches after the
  splash; every subsequent launch skips splash and showcase and goes straight
  to `projects.home`. The auto-launch is gated only by the first-run flag.
- **Dismiss before paint vs after:** either way the flag clears and the flow
  exits to `projects.home`; the only difference is whether Evan saw the dogfood.

## Edge cases

- **Showcase fails to launch:** the showcase is hand-written v1 UI (bootstrap
  caveat, §8 — app_box does not yet exist to generate itself). A launch
  failure (missing binary, macOS Gatekeeper quarantine, missing entitlements)
  is a bootstrap-time failure, not a broken gate — it never goes red. The flow
  falls through to `projects.home` with a one-line note that the showcase
  could not start. Red always means a gate broke; this is neither.
- **macOS desktop, not mobile:** the showcase renders at the macOS viewport
  (1280), not the 390×844 mobile default (§11). One viewport, because the
  target set is `macos` only.
- **Re-install with preserved state:** if projects already exist, the showcase
  still runs on this install's first run, then exits to `projects.home` in its
  **list** state rather than empty.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | `projects.splash` (null surface) — brand splash |
| 2–3 | `projects.showcase` (null surface) — the dogfood, a launched macOS app |
| 4 | dismiss (no surface — returns focus to the shell) |
| 5 | `projects.home` → `stage_shell_projects_home_view` — empty state |

## Notes

- The showcase is a **null surface** because it IS the artefact, not a viewer
  over `work/`. It deliberately inverts the §8 viewer contract — this is the
  one place where the pipeline's output is the thing on screen, not a render
  of pipeline state.
- **Bootstrap caveat (§8):** v1 of the showcase is hand-written, because
  app_box does not exist yet to generate it. True dogfooding — the showcase
  regenerated through app_box's own pipeline — starts at v2. The desktop UI is
  build-order step 7 (§9); hand-written until then.
- Next flow: `./new-project.md` (Evan starts his first real project from the
  empty home). Empty-state wording lives in `./project-list-home.md`.
- Sibling actor: Michelle's first-run counterpart is
  `../../michelle-buyer/projects-shell/first-run-showcase.md` — she also gets
  the showcase auto-launch (it is the pitch for the buyer persona), but reads
  it as proof of output quality, not as dogfooding.
