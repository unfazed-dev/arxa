# New project (first run) — name, brand, platforms shown as outcome

Actor: Michelle (buyer, 20-min evaluation) · Shell: projects-shell · Surfaces:
`projects.new` → `stage_shell_projects_new_view` (form · validating · error) ·
Decision refs: architecture.md §11 (targets platform-only, viewports derive —
show consequence, not flag), §22 (intake elicits, never generates); personas.md
(Michelle's legibility filter)

## Trigger

Michelle finishes the showcase auto-pitch and lands on `projects.home` empty
state ("You haven't built anything yet"). She taps "New project." She has read
none of these docs and is measuring app_box against FlutterFlow; every label she
meets is her first impression of the tool.

## Entry / exit

- Entry criteria: arrived from `first-run-showcase.md` showcase → empty
  `projects.home`. No project open. No licence precondition — the form sits
  before the builder phase where 💳 runs.
- Exit states: **created** — project record written, pipeline state initialised
  (phase = design, targets set), routes to
  `../design-shell/accept-single-direction.md` · **cancelled** — Michelle backs
  out before submit; nothing written · **abandoned** — 20-minute clock runs out
  mid-form; cached input is recoverable on return.

## Happy path

1. `projects.new` renders in **form** state. The first field is labelled in plain
   English — **"What are you building?"** — not "Project name." Michelle types a
   name she will recognise later (e.g. "Leo's gym app").
2. **Brand input.** "Brand or company name." Recorded verbatim; it becomes one
   of the six frozen design inputs downstream. Michelle does not see that
   machinery — she sees a labelled box.
3. **Platforms picker.** The legibility-critical surface. Michelle is never
   shown the flag `--targets ios,android`. She sees checkboxes labelled by
   device, and beside her selection a live **outcome line**: *"iPhone and iPad
   layouts. No desktop."* Add `web` → the line becomes *"iPhone, iPad, and
   desktop web layouts."* Mobile is always in the set; the picker cannot
   express a phone-less target (architecture.md §11). The consequence updates
   as she toggles — the design fails if she cannot predict the effect before
   submit.
4. **No brief seed for Michelle.** The intake-elicited brief area that Evan
   sees is absent here — Michelle came to try the tool, not answer a
   questionnaire (architecture.md §22; journeys.md J1). She skips intake; an
   empty brief is valid input and does not block.
5. Michelle taps **Create**. Surface enters **validating** state.
6. Inputs valid → project record written; targets written to pipeline state
   (`work/run.json`, never a flag); routes to design phase
   `../design-shell/accept-single-direction.md`.

## Decision points

- **Which platforms → which layouts.** Shown as outcome, never as flag. The
  picker maps Michelle's checkbox state to a viewport union (ios/android →
  mobile + tablet; web → + desktop; macos/linux/windows → desktop) and renders
  the human-readable consequence live. She picks devices; the tool derives
  viewports.
- **BYO brief vs skip.** Michelle skips intake — it is not offered on this
  surface. A hand-written brief is valid for the operator (Evan); for the buyer
  the questionnaire is a wall between her and the showcase, which is the one
  thing that earns her trust (§22).

## Edge cases

- **Invalid or empty name:** **validating** → **error** state with plain wording
  ("Give your project a name") — never a field code or a validation rule quoted
  back. Other fields hold their values. Not a gate; a field check.
- **Target selection confusion:** if Michelle toggles platforms and cannot
  predict what she will get, the design has failed. The outcome line is the
  contract — it must read in devices a non-operator recognises, not a flag or a
  viewport class ("mobile, tablet, desktop" is operator vocabulary; "iPhone and
  iPad layouts" is Michelle's).
- **Offline:** form data cached locally, submit queued. On reconnect the write
  to pipeline state completes; nothing lost, nothing inferred from the cache.
  Michelle sees "Saved — will finish when you're back online," not a
  SARIF-flavoured error.
- **Session timeout mid-form:** input is recovered on return; the empty state
  does not reset her work. She is never asked to re-derive what she typed.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1–4 | `stage_shell_projects_new_view` — **form** (name, brand, platforms picker + live outcome line) |
| 5 | `stage_shell_projects_new_view` — **validating** |
| 5 (error) | `stage_shell_projects_new_view` — **error** (invalid/empty name, plain wording) |
| 6 | route to design phase — `../design-shell/accept-single-direction.md` |

## Notes

- **Targets shown as consequence is Michelle's key UX requirement**
  (architecture.md §11; personas.md). The flag `--targets` is operator
  vocabulary; the buyer sees "iPhone and iPad layouts, no desktop." Where the
  two surfaces set the same state, they must render it in their reader's
  language.
- Targets live in **pipeline state, not flags** (architecture.md §11). This form
  writes `work/run.json`; every gate downstream reads the same state, so a
  design frozen for two viewports cannot be scaffolded for three.
- No gate in this flow. The first gate Michelle reaches is Gate 1 (design
  approve) in `../design-shell/accept-single-direction.md`; the targets chosen
  here are hashed into that approval's invalidation.
- Sibling flows: `first-run-showcase.md` (the showcase pitch this flow launches
  from) · `../design-shell/accept-single-direction.md` (where a created project
  routes) · `../../evan-founder/projects-shell/new-project.md` (the operator's
  version of the same surface — adds the intake/brief seed Michelle never sees).
