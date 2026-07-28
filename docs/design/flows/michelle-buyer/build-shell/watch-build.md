# Watch build — progress, not machinery

Actor: Michelle (buyer, evaluating) · Shell: build-shell · Surfaces: `build.run`
→ `stage_shell_build_run_view` (idle · running · green · red) · Decision refs:
architecture.md §5 (UI is a viewer over pipeline state), §6 (deterministic gates
fail loud and HALT), §17 (licence precondition is not a gate — never red)

## Trigger

Gate 1 approved (design accepted — see
`../design-shell/accept-single-direction.md`). The build phase starts; Michelle
stays on the build view and watches it. She does not trust the tool yet — the
watching is the trust being built in real time.

## Entry / exit

- Entry criteria: Gate 1 approved (design hash bound); 💳 licence precondition
  passed before the phase — never rendered as a gate (architecture.md §17).
- Exit states: **green** — all stages passed, build done → route to
  `../ship-shell/take-code-and-leave.md` · **red** — a stage failed; a
  plain-language explanation renders on the build view (no SARIF, no file/line)
  · **blocked** — offline mid-run; deterministic stages continue, LLM stages fail
  typed (never a silent hang).

## Happy path

1. 💳 **Licence precondition ran before the phase.** If it failed, the build did
   not start — a licence message, never a red gate (architecture.md §17).
2. `build.run` enters **running** state. The stage timeline renders live — each
   stage shows a plain-language label: *"Designing…", "Building…",
   "Checking…"*. No gate names, no SARIF, no file paths, no stdout.
3. Stages transition pending → running → passed. Passed stages turn green and
   stay green; the active stage shows a spinner beside its label.
4. Every stage green → `build.run` enters **green** state. A clear "Done!"
   signal — a state, not a log line.
5. Michelle accepts the build **(Gate 2)** → route to
   `../ship-shell/take-code-and-leave.md`.

## Decision points

- **Green vs red:** every stage passed → green (→ ship); any stage failed → red
  (→ plain-language explanation on the build view).
- **Plain language vs technical detail:** Michelle gets the legibility-filtered
  rendering — which stage, what went wrong in her vocabulary, and what to do.
  The SARIF finding, file/line, rule name, and reproduce command are Evan's P3
  recovery view (`../../evan-founder/build-shell/red-gate-recovery.md`), never
  hers.

## Edge cases

- **Red gate with no plain-language explanation** — the #1 risk for Michelle. A
  red state that reads only `scaffold_coverage_gate: FAIL` reads as "the tool
  is broken." The rendering must say what failed in her words (e.g. *"A screen's
  files didn't all come out — one is empty or missing"*) and what to do. A stack
  trace ends the evaluation.
- **Licence precondition appears as red** — FORBIDDEN (§17). The 💳 runs before
  the phase; on failure the build does not start and a licence message shows.
  Showing it as a red gate would read as "the tool is broken" to someone who has
  not read the docs — the single most damaging misrender for the buyer persona.
- **Progress shown as raw log output** — illegible to a non-operator. `work/logs/*`
  exists for Evan; Michelle sees the stage timeline, not scrolling stdout. If the
  only signal is a log, she leaves before "Done!".
- **Offline mid-run** — deterministic stages need no network and continue; LLM
  stages fail typed. The view names which stage stopped and why, in plain
  language — never a silent hang or a spinner that never resolves.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | Licence precondition (pre-phase, not a gate surface) |
| 2–4 | `stage_shell_build_run_view` — stage timeline, plain-language labels, live state transitions |
| 4 (red) | `stage_shell_build_run_view` — red state, plain-language explanation (no SARIF panel) |
| 5 | `stage_shell_build_run_view` — green state, "Done!" → route to ship |

## Notes

- The build view is where Michelle's trust is earned or lost
  (`journeys/michelle-buyer-journey.md`). Legible progress — a stage timeline,
  plain words, a clear done signal — is the retention lever for the buyer
  persona; raw log spew is the opposite.
- She sees the same surface as Evan, through a legibility filter: progress
  without knowing what a gate is. The SARIF detail, file/line, rule names, and
  reproduce command are Evan's — see `../../evan-founder/build-shell/run-build.md`
  (the operator's version with full state-machine detail) and
  `../../evan-founder/build-shell/red-gate-recovery.md` (P3 finding diagnosis).
- Everything rendered comes from `work/` — `run.json`, `history.jsonl`
  (architecture.md §5). The UI is a viewer, never the source of truth; closing it
  loses nothing, and a run continues headless (§8).
