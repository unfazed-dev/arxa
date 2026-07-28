# Accept build — Gate 2 (read-only acceptance)

Actor: Evan (founder, autonomous-build mode — P2) · Shell: build-shell · Surfaces:
`build.approve` → `stage_shell_build_approve_view` (Gate 2 — pending · accepted ·
rejected) · NEW — not yet scaffolded · Decision refs: architecture.md §6 (gates
define stages — Gate 2 approves the scaffolded work; approval binds to a hash),
§12 (human gates — agent reaches but cannot mint), §17 (licence precondition is
before builder, not Gate 2); brief §5.2 (gates visually distinct)

## Trigger

The build phase went green in `run-build.md` — every gate passed, every surface
scaffolded with the derived form-factor set. `build.run` enters **green** and
routes Evan to `build.approve` for acceptance.

## Entry / exit

- Entry criteria: Gate 1 approved and hash-bound; all build gates green
  (`work/run.json` stage → passed); every surface scaffolded with the form-factor
  set targets derive (macOS = 3 files, ios+android = 5 per surface;
  architecture.md §16); 💳 licence precondition passed before the phase — not a
  gate, never red (§17).
- Exit states: **accepted** — acceptance token minted; route to ship phase
  (`../ship-shell/select-targets.md`) · **rejected** — route to
  `red-gate-recovery.md` (Evan's call when the green set doesn't read as
  shippable) · **invalidated** — design moved since Gate 1; hash check exits
  non-zero, route back to design.

## Happy path

1. `build.approve` renders in **Gate 2 pending** state. The surface is visually
   distinct from the automated stage timeline — a human gate, not another step
   (brief §5.2; architecture.md §6).
2. The surface shows the **build summary**, all read from `work/` — surface
   count, per-gate results (all green), the derived form-factor set, and the
   **diff vs the previous run** from `history.jsonl` ("what changed since
   Tuesday"). The view is a viewer, never a source of truth (architecture.md
   §5, §8).
3. The surface states the hash-binding consequence: *"Accepting binds this build
   to the design hash from Gate 1. If the design has moved, `done` exits
   non-zero and acceptance is refused."* Happy path: the hash matches
   (architecture.md §6).
4. Evan reviews the diff and the green gate set, then **accepts**. The approval
   token is minted by the person — an agent may run the build, reach Gate 2, and
   stop; it cannot mint the token (architecture.md §12). **(Gate 2)**
5. Token written to state; `build.approve` enters **accepted**. Route to ship
   phase (`../ship-shell/select-targets.md`).

## Decision points

- **Accept vs reject:** accept → ship phase; reject → `red-gate-recovery.md`.
  Reject is Evan's judgement when no single gate failed but the whole doesn't
  read as shippable quality — the human check the gate exists to hold.
- **Review the diff:** the diff vs the previous run must be reviewable here. A
  green build that changed nothing since the last accepted run and one that
  rewrote half the surfaces are different acceptance decisions; the surface
  makes that visible (architecture.md §5).

## Edge cases

- **Design moved after Gate 1, before Gate 2:** the content-hash check at step 3
  catches it. Gate 1's approval is invalidated, Gate 2 refuses acceptance, and
  Evan routes back to design — not to recovery, since nothing is broken
  (architecture.md §6).
- **A gate that passed but shouldn't have (stale green):** the `dep_hash`-on-mtime
  family fails this way — green because mtime was restored, not because content
  matched. app_box hashes content and regenerates-and-diffs, so a stale-green
  gate fails for the right reason at re-run; if one slips through, reject and
  route to recovery (research-findings §7).
- **ESC_LIMIT reached on a surface:** that surface is red and the build never
  reached Gate 2. The flow does not render `build.approve`; Evan is already in
  `red-gate-recovery.md` (architecture.md §6).
- **No previous run to diff against:** first build — the diff panel renders the
  full surface set as net-new, not an empty panel.
- **Licence expired between green and Gate 2:** the 💳 precondition ran before
  the phase, so the build completed under a valid licence. Expiry here blocks
  the *next* phase (ship) with a licence message — Gate 2 itself proceeds
  (architecture.md §17).

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1–3 | `stage_shell_build_approve_view` — pending: build summary (surface count · gate results · form-factor set · diff) + hash-binding consequence |
| 4 | `stage_shell_build_approve_view` — accept **(Gate 2, visually distinct)** |
| 5 | `stage_shell_build_approve_view` — accepted → routes to ship |

## Notes

- Gate 2 must look different from anything automated — approval is the product's
  core claim, and it should look like it. The three gates share a visual
  language; Gate 3 adds the blast-radius statement (brief §5.2).
- The 💳 licence precondition ran before the builder phase in `run-build.md`. It
  is not Gate 2 and never shows red — a gate that can go red for payment teaches
  people to distrust red (architecture.md §17).
- Acceptance, like Gate 1, is a **read-only assertion**: it writes a token into
  state and binds to the design hash. It writes nothing to the outside world —
  that is Gate 3 alone (architecture.md §17).
- Sibling flows: entry from `run-build.md`; rejection routes to
  `red-gate-recovery.md`; acceptance routes to
  `../ship-shell/select-targets.md`. Michelle's counterpart reads the same green
  build through a legibility filter (`../michelle-buyer/build-shell/watch-build.md`).
