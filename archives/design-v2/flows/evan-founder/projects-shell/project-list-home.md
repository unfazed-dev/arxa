# Project list home — the projects index

Actor: Evan (founder, operator) · Shell: projects-shell · Surfaces:
`projects.home` → `stage_shell_projects_home_view` (empty · list · loading) ·
Decision refs: architecture.md §3 (input/work/output layout), §8 (desktop app —
viewer not source of truth), §6 (FSM phases)

## Trigger

App launch lands on the projects tab. Or: Evan switches the `stage_shell` tab
group to **projects** from any other shell.

## Entry / exit

- Entry criteria: the `stage_shell` is running; `work/` is the read source. No
  project needs to be selected — this is the index.
- Exit states: **project selected** → routes to the project's current pipeline
  phase (design / build / ship) · **new project** → routes to
  `projects.new` (see `new-project.md`) · **stays** — Evan reads the list and
  does not pick.

## Happy path

1. `projects.home` mounts and enters **loading**. The ViewModel reads the set of
   projects from `work/` — each project is a `run.json` ledger (stage → status,
   content_hash, ts) per architecture.md §3, §5.
2. The list resolves. If ≥1 project exists, the surface enters **list** state:
   one card per project, showing **name**, **pipeline phase badge**
   (intake · prototype · design · build · ship — per the FSM, §6),
   **last-modified** (from `run.json` `ts`), and **gate status**
   (pending Gate 1 · Gate 1 approved · Gate 2 accepted · shipped).
3. Evan clicks a card. The route target is the project's *current* phase, not a
   fixed destination — see Decision points.
4. If no projects exist, the surface enters **empty** state (see Edge cases).

## Decision points

- **Empty vs populated:** zero projects → **empty** state (real copy, see Edge
  cases); ≥1 → **list**.
- **Phase → route on click** (per the project's FSM position, §6):
  - intake / prototype / design-pre-Gate-1 → `design-shell` (prototype or
    `approve-design.md`, Gate 1).
  - Gate 1 approved, pre-Gate-2 → `build-shell` (`run-build.md`).
  - Gate 2 accepted → `ship-shell` (`confirm-ship.md`, Gate 3).
  - shipped → the project's released view; re-entry routes to the next phase or
    a "shipped" terminal.

## Edge cases

- **Empty state copy is authored, not generated.** The htmx experiment found
  empty-state copy absent and the emitter invented it. The **empty** state must
  carry deliberate wording (e.g. a "create your first project" affordance →
  `new-project.md`) — never a blank canvas or generator-fabricated text.
- **Offline:** the list renders from the cached `work/` ledgers. Pipeline state
  is local; no network is needed to show phase/gate badges. A stale indicator
  appears only if a project's `history.jsonl` shows an in-flight stage whose
  `ts` is older than expected — never inferred from paint (§8).
- **Corrupt or partial `run.json`:** the card renders with a **broken** badge
  (red = broken, per convention) and routes to that project's recovery flow,
  not to a phase. Never silently dropped from the list.
- **Loading with cached data:** if a cached list exists, **list** renders
  immediately and **loading** is a refresh indicator, not a blocking spinner.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | `stage_shell_projects_home_view` — loading state |
| 2 | `stage_shell_projects_home_view` — list state (project cards) |
| 3 | route-out to `design-shell` / `build-shell` / `ship-shell` per phase |
| 4 | `stage_shell_projects_home_view` — empty state (first run) |

## Notes

- The view is a **viewer over pipeline state**, never a source of truth
  (architecture.md §8). Every phase badge and gate status is read from `work/`
  — `run.json`, `history.jsonl`. Closing the app loses nothing.
- No gate lives here; this is an index. The gate referenced by each card's
  status is reached inside the target shell's flow.
- Sibling flow: [`new-project.md`](new-project.md) — the **empty** state's call
  to action and the "new project" entry both route there.
- Michelle's counterpart reads the same index through a legibility filter
  (progress without gate vocabulary) — see `../michelle-buyer/_index.md`.
