# New project — name, brand, targets, brief seed

Actor: Evan (founder, intake mode, P1) · Shell: projects-shell · Surfaces:
`projects.new` → `stage_shell_projects_new_view` (form · validating · error) ·
Decision refs: architecture.md §11 (targets platform-only, viewports derive),
§22 (intake elicits, never generates)

## Trigger

Evan taps "New project" from the `projects.home` empty state, or arrives mid
intake phase (a client conversation already in flight). Also the entry the
showcase dogfood seeds on first install (`showcase-first-run.md`).

## Entry / exit

- Entry criteria: no project open in the shell (intake starts a fresh record);
  Evan is in P1, client-intake mode. No licence precondition here — intake sits
  before the builder phase where 💳 runs.
- Exit states: **created** — project record written, pipeline state initialised
  (phase = intake, targets set), routes to design phase · **cancelled** — Evan
  dismisses before submit; nothing is written to pipeline state.

## Happy path

1. `projects.new` renders in **form** state: name, brand, targets picker, brief
   seed area. All empty — this flow owns the first write to pipeline state.
2. **Name input.** Free text; uniqueness checked against existing projects on
   blur.
3. **Brand input.** Client brand string, recorded verbatim — feeds the brand
   tokens that become one of the six frozen design inputs downstream.
4. **Targets picker.** Platform-only choices (`ios, android, web, pwa, macos,
   linux, windows`); the form shows the **consequence**, not the flag —
   "iPhone and iPad layouts, no desktop" for the default `ios,android`, never
   the raw `--targets ios,android`. Mobile is always present
   (architecture.md §11).
5. **Brief seed.** Either Evan pastes a hand-written brief (BYO) or starts
   intake-elicited capture. Where the seed must infer, it marks the inference
   explicitly (`TODO(prose)` style) — intake elicits, never generates
   (architecture.md §22).
6. Evan taps **Create**. The surface enters **validating** state.
7. Inputs valid → project record written; targets written to pipeline state
   (`work/run.json`, not a flag); brief seed written to `docs/design/brief.md`
   plus a seeded `registry.json`. Route to design phase
   (`../design-shell/prototype-directions.md`).

## Decision points

- **BYO brief vs intake-elicited:** a hand-written brief is valid input and
  skips elicitation (Michelle does this on first run, `journeys.md` J1);
  intake-elicited asks and records, marking inferences. Same exit either way —
  both produce a brief the designer consumes.
- **Targets chosen → viewport set derived:** the union of implied viewports
  (`ios`/`android` → mobile + tablet; `web` → mobile + tablet + desktop;
  `macos`/`linux`/`windows` → desktop). Mobile is always in the set, so the
  picker cannot express a no-mobile target. The scaffold coverage gate later
  requires exactly this derived set (architecture.md §11).

## Edge cases

- **Invalid / duplicate name:** `validating` transitions to **error** state,
  naming the conflict (empty or duplicate); the form holds its other fields.
  Not a gate — a field check.
- **No mobile target:** unconstructable per §11 (mobile always present). If
  Evan skips the picker entirely, the default `ios,android` applies; the UI
  cannot produce a mobile-less set.
- **Offline:** form data cached locally, submit queued. On reconnect the write
  to pipeline state completes; nothing lost, nothing inferred from the cache.
- **Intake mid-conversation:** arriving from an in-flight intake phase
  pre-fills the brief seed from captured elicitation; the form does not re-ask.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1–6 | `stage_shell_projects_new_view` — **form** (name, brand, targets picker, brief seed) |
| 7 | `stage_shell_projects_new_view` — **validating** |
| 7 (error) | `stage_shell_projects_new_view` — **error** (invalid / duplicate name) |
| 8 | route to design phase — `../design-shell/prototype-directions.md` |

## Notes

- Targets live in **pipeline state, not flags** (architecture.md §11). Three
  surfaces set targets (this form, the harness skill, the CLI); all three
  *write* state, every gate *reads* state. A design frozen for two viewports
  then cannot be scaffolded for three — the coverage gate reads the same state.
- Intake elicits; it does not generate (architecture.md §22). The brief is the
  client's words; inferences are marked, never smoothed over. This is the
  cheapest place in the whole pipeline to be wrong.
- Sibling flows: `project-list-home.md` (the empty state this launches from, and
  where the new project afterwards appears) · `showcase-first-run.md` (the
  dogfood that seeds a project on install).
- No gate in this flow. The first gate Evan reaches is Gate 1 (design approve)
  in `../design-shell/approve-design.md`; targets chosen here are hashed into
  that approval's invalidation.
