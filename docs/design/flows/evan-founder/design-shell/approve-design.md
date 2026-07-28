# Approve design — Gate 1 (hash-bound)

Actor: Evan (founder, design mode) · Shell: design-shell · Surfaces: `design.approve`
→ `stage_shell_design_approve_view` (Gate 1 — pending · approved) · NEW — not yet
scaffolded · Decision refs: architecture.md §6 (approval binds to hash — `done`
exits non-zero if the design moved), §12 (human gates — agent can reach but cannot
mint the token); brief §5.2 (gates visually distinct)

## Trigger

Evan selects one direction in `prototype-directions` and routes to approve. Or:
re-enters `design.approve` after an iterate cycle (`iterate-direction.md`).

## Entry / exit

- Entry criteria: one direction selected from `prototype-directions`; registry +
  surfaceId authored while designing; prototype phase complete in `work/run.json`.
- Exit states: **approved** — approval token minted, content hash bound, freeze
  phase begins (→ `../build-shell/run-build.md`) · **iterate** — back to
  `prototype-directions` to revise, then re-freeze · **rejected** — back to
  `prototype-directions`, the direction discarded.

## Happy path

1. `design.approve` renders in **pending** state. Gate 1 is visually distinct from
   anything an agent can do alone (brief §5.2) — it reads as a deliberate human
   instrument, not a status tile.
2. The surface states what is being approved: the selected direction, the viewport
   set it was judged at, and the surface count (registry entries). All read from
   `work/run.json` — the view is a viewer, never a source of truth
   (architecture.md §8).
3. The surface states the hash-binding consequence: *"Approving records this
   design's content hash. If the design moves after approval, the build fails
   non-zero."* (architecture.md §6).
4. Evan confirms. The approval token is minted by the person — an agent may
   prepare, present, and reach the gate, then stop; it cannot mint the token
   (architecture.md §12). **(Gate 1)**
5. Token written to state; `design.approve` enters **approved**. Freeze phase
   begins; route to build.

## Decision points

- **Approve vs iterate vs reject:** approve → freeze (token minted, hash bound);
  iterate → `prototype-directions` (revise → re-freeze, see `iterate-direction.md`);
  reject → `prototype-directions` (direction discarded).
- **Agent-presented, no human:** forbidden path. The confirm action is inert until
  a person mints the token; the surface holds pending (architecture.md §12).

## Edge cases

- **Design moved between selection and approval:** the frozen-artifact hash no
  longer matches what Evan picked. Surface shows a **stale warning** — this is
  the soft case (re-emission can change bytes without changing intent,
  architecture.md §6). Evan re-reviews or re-selects; approve stays inert until
  the warning clears.
- **Design moved AFTER approval:** the source hash is bound hard. `done` exits
  non-zero; the build is blocked, not warned. Route back to design
  (architecture.md §6).
- **Agent-presented approval without a human:** the token cannot be minted — the
  surface shows Gate 1 pending in its visually-distinct treatment, waiting on the
  person. Never silently approved (§12).
- **No direction selected:** entry criteria unmet — `design.approve` is not
  reachable; route to `prototype-directions`.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1–3 | `stage_shell_design_approve_view` — pending: direction, viewport set, surface count, hash-binding consequence |
| 3 | Stale-warning sheet (only if frozen-artifact hash drifted since selection) |
| 4 | `stage_shell_design_approve_view` — confirm **(Gate 1, visually distinct)** |
| 5 | `stage_shell_design_approve_view` — approved → routes to freeze / build |

## Notes

- Gate 1 is visually distinct from automated steps (brief §5.2) — approval is the
  product's core claim; the surface should look like it.
- The approve view renders pipeline state only (`work/run.json`: `content_hash`,
  registry, targets). Closing the app loses nothing (architecture.md §8).
- Sibling flows: `prototype-directions.md` (selects the direction),
  `iterate-direction.md` (revise → re-freeze), and `../build-shell/run-build.md`
  (next phase after freeze).
