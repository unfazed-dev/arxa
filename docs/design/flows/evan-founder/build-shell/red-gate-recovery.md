# Red-gate recovery — diagnose, fix, re-run

Actor: Evan (founder, red-gate recovery mode — P3) · Shell: build-shell ·
Surfaces: `build.finding` → `stage_shell_build_finding_view` (file · line ·
rule · fix), `build.recovery` (null surface — red-gate · diagnose · fix ·
re-run) · Decision refs: architecture.md §1 (P3 persona), §5 (SARIF findings),
§6 (ESC_LIMIT)

## Trigger

A gate in the build phase went red. The build view (`build.run`) shows the red
state; Evan clicks the red gate to open the finding.

## Entry / exit

- Entry criteria: a gate failed during `run-build.md`; SARIF finding written to
  `work/findings/*.sarif`.
- Exit states: **fixed** — the fixer applied the fix, re-ran the gate, it
  passed → back to `run-build.md` happy path · **ESC_LIMIT reached** — the
  LLM-authored retry hit `ESC_LIMIT=3`; a human is required · **manual fix** —
  Evan fixes it himself and re-runs the stage.

## Happy path

1. `build.run` shows red. Evan clicks the red gate → `build.finding` renders the
   SARIF finding: **gate name, check name, file path, line number, expected
   value, actual value, and the exact command to reproduce it**
   (architecture.md §5).
2. `partialFingerprints` in the SARIF answer *"is this the same failure as
   Tuesday?"* — stable finding identity across runs (architecture.md §5).
3. Evan reviews the finding. The suggested fix is presented (from the
   `--fix-cmd` dispatch or MEM-A's prior failure notes).
4. If the fix is LLM-authored: the fixer applies it and re-runs the gate. This
   loop is bounded by `ESC_LIMIT=3` — after 3 attempts, HALT; a human is
   required (architecture.md §6).
5. If Evan fixes manually: he edits the authored layer (registry or
   view/viewmodel pair — never scaffolded Dart; architecture.md §18), re-freezes,
   and re-runs the stage.
6. Gate passes → back to `run-build.md`. The history (`history.jsonl`) records
   the recovery: failure → fix → pass, with timestamps.

## Decision points

- **Fixer vs manual:** LLM-authored fixer (bounded by ESC_LIMIT) vs Evan fixing
  the authored layer himself.
- **Authored layer vs scaffolded Dart:** the fix always writes the registry or
  the view/viewmodel pair, never scaffolded Dart. Editing Dart creates a second
  writer and the drift check dies (architecture.md §14, §18).
- **Same failure or new?** `partialFingerprints` tells Evan whether this is a
  recurring failure (MEM-A has a note) or a novel one.

## Edge cases

- **ESC_LIMIT reached:** the fixer tried 3 times and failed. The surface must
  not read as "the tool is broken" — it says: *"3 automated attempts failed.
  This needs a human. Here's the finding, the file, and what was tried."*
  (architecture.md §6; personas.md — P3 mode).
- **Terminal gone:** 16 of 22 gates used to print to stdout only — if the
  terminal scrolled, the finding was gone. SARIF sidecars fix this: the finding
  lives in `work/findings/` and renders in the UI (architecture.md §1, §5).
- **Delete during recovery:** if the fix involves removing a surface, the
  delete path requires a human confirm — removing code is not recoverable by
  re-running a stage (architecture.md §18).
- **MEM-A has a note:** prior failure patterns feed back into the error
  message — *"this check fails this way for this reason"* (architecture.md §4).
  The note appears beside the finding.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1–2 | `stage_shell_build_finding_view` — SARIF finding (file/line/rule/expected/actual/reproduce) |
| 3 | Fix suggestion panel (inline in finding view) |
| 4–5 | `build.recovery` (null surface) — fix applied, re-run status |
| 6 | `stage_shell_build_run_view` — green state (gate passed) |

## Notes

- This is where tools are actually judged (architecture.md §1, P3). The finding
  either pinpoints the problem in seconds or it doesn't — and Evan is deciding
  whether to trust the next build.
- Deterministic gates fail loud and HALT — they never self-loop. Only the
  LLM-authored portion may retry, bounded by `ESC_LIMIT` (architecture.md §6).
- Michelle's counterpart: `../michelle-buyer/build-shell/watch-build.md` — she
  sees the red gate in plain language, not the SARIF detail. The finding surface
  is Evan's; the plain-language rendering is hers.
