# Accept a single direction — Gate 1, one design not three

Actor: Michelle (buyer, evaluating) · Shell: design-shell · Surfaces:
`design.directions` → `stage_shell_design_directions_view` (one direction ·
accept / regenerate), `design.approve` → `stage_shell_design_approve_view`
(Gate 1 — pending · approved) · NEW — not yet scaffolded · Decision refs:
architecture.md §6 (approval binds to hash — `done` exits non-zero if the
design moved), §12 (human gates — agent can reach but cannot mint the token),
§11 (viewport ladder); brief §5.2 (gates visually distinct); journeys.md J3

## Trigger

Michelle lands in design-shell straight from `new-project-first` — project
created, targets written to state. One direction is generated from her brief
and shown. She has ~15 minutes left on her evaluation clock.

## Entry / exit

- Entry criteria: project created (`../projects-shell/new-project-first.md`);
  targets in pipeline state — for Michelle `ios,android` → mobile + tablet, no
  desktop (§11); 💳 licence precondition passes before the phase.
- Exit states: **accepted** — Gate 1 approval token minted, design hash bound,
  freeze phase begins (→ `../../evan-founder/build-shell/run-build.md`, read
  through `../build-shell/watch-build.md`) · **regenerated** — a fresh
  direction replaces the current one; she is back at the same surface ·
  **blocked** — `none` harness mode with the designer (an LLM stage) marked
  `blocked` (§7).

## Happy path

1. 💳 **Licence precondition runs before the phase.** If it fails, the phase
   does not start — a licence message, never a red gate (architecture.md §17).
2. `design-shell` opens carrying targets from state. Michelle sees the
   consequence, not the flag — *"iPhone and iPad layouts"* — and never the word
   `targets` (journeys.md J2). The viewport set is the derived union: `390` +
   `744`; no `1280`, because she did not pick desktop (§11).
3. `app-box-designer` produces **one direction** (single-direction mode). It is
   a Hono + htmx MVVM app with zero custom client-side JS — `X_view.html` +
   `X_viewmodel.js` pairs, authored `registry.json` (§13, §14). She does not
   see any of that vocabulary; she sees a rendered design.
4. `design.directions` renders the single direction at the **active viewport
   width**. She cycles 390 / 744 to judge both layouts — widths rendered
   *inside* each class, never on its boundary (§11). No 3-up, no empty slots.
5. Michelle accepts, or taps **Regenerate** for another. Regenerate is one tap,
   not a workflow: the prior direction is discarded, a fresh one renders, she
   stays on the same surface. There is no "compare three" step — that is
   Evan's discipline, not the machine's requirement (journeys.md J3).
6. On **accept**, route to `design.approve`, which renders in **pending** state.
   Gate 1 is visually distinct from anything an agent can do alone (brief §5.2)
   — it reads as a deliberate human instrument, not a status tile.
7. The surface states what is being approved in plain language — the design,
   the layouts ("iPhone and iPad"), the screen count — all read from
   `work/run.json`. It states the hash-binding consequence plainly: *"Approving
   locks this design. If it changes after you approve, the build stops."* The
   view is a viewer, never a source of truth (architecture.md §8).
8. Michelle confirms. The approval token is minted by the person — an agent may
   generate, present, and reach the gate, then stop; it cannot mint the token
   (architecture.md §12). **(Gate 1)** Even her single-direction accept is
   enforceable: the token binds to the design's content hash exactly as Evan's
   three-direction approval does (§6).
9. Token written to state; `design.approve` enters **approved**. Freeze phase
   begins; route to build.

## Decision points

- **Accept vs regenerate:** accept → Gate 1 (token minted, hash bound);
  regenerate → a fresh direction replaces the current one, same surface, no
  comparison step. There is no "reject and discard" branch — regenerate *is*
  the discard.
- **Gate 1 confirmation:** identical hash-binding to Evan's `approve-design.md`,
  with one direction on the table instead of three. The machine does not
  require three; the three-direction discipline is a practice, not a
  precondition (journeys.md J3, personas.md).
- **Agent-presented, no human:** forbidden path. The confirm action is inert
  until a person mints the token; the surface holds pending (§12).

## Edge cases

- **The direction is just wrong:** regenerate — one tap, not Evan's
  iterate→re-freeze cycle. A buyer with 15 minutes gets a button where an
  operator would get a workflow.
- **Design moved between generation and acceptance:** the frozen-artifact hash
   no longer matches what Michelle is looking at. Surface shows a **stale
   warning** — the soft case; re-emission can change bytes without changing
   intent (§6). She re-reviews; approve stays inert until the warning clears.
- **Design moved AFTER approval:** the source hash is bound hard. `done` exits
   non-zero; the build is blocked, not warned. Route back to design (§6).
- **Forced through a 3-direction workflow:** friction. The tool detects the
   buyer persona and offers single-direction rather than a 3-up with two empty
   slots. Michelle never sees blanks labelled for selection.
- **`none` harness mode:** the designer is an LLM stage; under `none` it is
   `blocked` and no direction is produced — a determinism measurement, not a
   degradation (§7). Michelle sees an honest empty state with wording, not a
   blank surface (personas.md).
- **Offline:** the designer needs the harness; offline blocks the LLM stage
   typed, never silent (§7).
- **Partial output:** an incomplete direction is shown flagged, never fabricated
   into a clean one. Michelle abandons on a hidden `UnimplementedError`
   (personas.md) — she must not be offered a broken thing as ready.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | Licence precondition (pre-phase, not a gate surface) |
| 2 | design-shell open (targets carried from `projects-shell` state, shown as consequence) |
| 3–4 | `stage_shell_design_directions_view` — one direction at active viewport widths, accept / regenerate |
| 5 | Regenerate (inline on the same surface — no route) |
| 6–7 | `stage_shell_design_approve_view` — pending: design, layouts, screen count, hash-binding consequence in plain language |
| 7 | Stale-warning sheet (only if frozen-artifact hash drifted since rendering) |
| 8 | `stage_shell_design_approve_view` — confirm **(Gate 1, visually distinct)** |
| 9 | `stage_shell_design_approve_view` — approved → routes to freeze / build |

## Notes

- **Michelle's single-direction accept is still enforceable.** The approval
  token binds to the design hash exactly as Evan's three-direction approval
  does (§6). The machine requires a human to mint the token; it does not
  require three directions. The 3-up is Evan's practice, not a precondition
  (personas.md, journeys.md J3).
- Both surfaces render pipeline state from `work/` (`run.json`:
  `content_hash`, registry, targets) and the authored artifacts in `design/`.
  UI is a viewer, never a source of truth — closing the app loses nothing (§8).
  The legibility filter is a render concern: the surface shows "iPhone and
  iPad layouts" and "locks this design", never `targets`, `content_hash`, or
  SARIF (journeys.md J2).
- Evan's counterpart: `../../evan-founder/design-shell/approve-design.md` (the
  full Gate 1 with three directions) and
  `../../evan-founder/design-shell/prototype-directions.md` (the 3-up, iterate,
  and the authored-registry discipline). Michelle's flow is that flow with the
  operator-only ceremony removed.
- Next phase: freeze → build. Michelle watches it through
  `../build-shell/watch-build.md` (progress legible without knowing what a gate
  is); the operator view is `../../evan-founder/build-shell/run-build.md`.
