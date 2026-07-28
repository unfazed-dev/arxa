# Run build — autonomous scaffold + review

Actor: Evan (founder, autonomous-build mode) · Shell: build-shell · Surfaces:
`build.run` → `stage_shell_build_run_view` (idle · running · green · red) ·
Decision refs: architecture.md §6 (state machine), §17 (licence precondition),
§5 (SARIF findings)

## Trigger

Evan starts the build from the design phase (Gate 1 approved, design frozen).
Or: re-run after a red-gate recovery cycle.

## Entry / exit

- Entry criteria: Gate 1 approved (design hash bound); six frozen inputs present
  (registry + view/viewmodel tree + surfaces + routes + brand tokens + targets);
  💳 licence precondition passes before the phase.
- Exit states: **green** — all surfaces scaffolded, all gates passed, build
  ready for Gate 2 acceptance · **red** — a gate failed; route to
  `red-gate-recovery.md` · **blocked** — licence expired or `none` harness mode
  with LLM stages marked `blocked`.

## Happy path

1. 💳 **Licence precondition runs before the phase.** If it fails, the phase
   does not start — an unmistakable licence message, never a red gate
   (architecture.md §17).
2. `build.run` enters **running** state. The stage timeline renders live from
   `work/history.jsonl` — each stage transitions through
   `pending → running → passed/failed`.
3. The scaffolder emits Dart per surface, reading targets from state: exactly
   the derived form-factor set (macOS = 3 files, ios+android = 5 files per
   surface). `scaffold_coverage_gate.sh` requires the derived set — no empty
   files, no orphans (architecture.md §16).
4. The reviewer runs `enforce_design` (73 checks) per surface. Findings emit as
   SARIF to `work/findings/*.sarif` — `partialFingerprints` stable across runs
   (architecture.md §5).
5. All gates green → `build.run` enters **green** state. Route to
   `accept-build.md` (Gate 2).

## Decision points

- **Gate green vs red:** all surfaces passed → green (→ Gate 2); any surface
  failed → red (→ `red-gate-recovery.md`).
- **`none` harness mode:** deterministic stages run; LLM stages marked
  `blocked`. The fraction producible under `none` is the run's determinism
  score (architecture.md §7). This is not degraded — it is a measurement.
- **ESC_LIMIT reached:** the LLM-authored retry loop hits `ESC_LIMIT=3` on a
  surface → that surface is marked red; the loop HALTs (architecture.md §6).
  Deterministic gates never self-loop.

## Edge cases

- **Licence expired mid-run:** the precondition ran before the phase, so this
  means the run was already in progress. In-progress work completes; the next
  phase is blocked with a licence message. Never a red gate.
- **Offline mid-run:** the scaffold is deterministic (no network needed for
  `none` mode); LLM stages requiring the harness fail typed, never silent
  (architecture.md §7).
- **Duplicate stage execution:** `run.json` is content-hashed; a re-run with
  unchanged inputs produces identical output (architecture.md §6).
- **A surface 404s its fonts:** the render gate catches it — path resolution,
  not string-checks. The three verification layers that once missed the
  `emit_htmx` asset bug are replaced by real path resolution
  (research-findings §7).

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | Licence precondition (pre-phase, not a gate surface) |
| 2–4 | `stage_shell_build_run_view` — stage timeline, live state transitions |
| 4 | SARIF findings panel (on red — see `build.finding` surface) |
| 5 | `stage_shell_build_run_view` — green state → route to Gate 2 |

## Notes

- The build view is a **viewer over pipeline state**, never a source of truth.
  Everything it renders comes from `work/` — `run.json`, `history.jsonl`,
  `findings/*.sarif`, `logs/*`. Closing the app loses nothing; a run continues
  headless (architecture.md §8).
- Michelle's counterpart: `../michelle-buyer/build-shell/watch-build.md` — the
  same view read through a legibility filter (progress without knowing what a
  gate is).
- MEM-A feeds prior failure notes into the next run's error messages
  (architecture.md §4).
