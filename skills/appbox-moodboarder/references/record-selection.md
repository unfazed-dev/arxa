# Record and selection gate

## Record (the step energize taught us)

A moodboard that is not RECORDED is a moodboard the designer never sees.
After verify + scoring:

1. Write the `moodboard` answer group into `intake/answers.json`:
   `{provenance: <method line>, criteria: [...], boards: [{id, references:
   [{name, url, grade, steal, why, scores, shot: {file}}]}],
   selectionStatus: "pending"}`.
2. Re-run the intake emitter (`appbox intake emit --project <name>`, or the
   repo-mode equivalent) — it publishes `intake/moodboard.json` with ids,
   counts, `shot.src`, and COMPUTED totals.
3. Run `appbox moodboard check <intake-dir>` — green required. A locked
   criterion with no reference scoring ≥ 3 fails here, BY DESIGN (the
   PENDING feasibility phase — once selectionStatus is `approved` the gate
   tightens: a SELECTED reference must carry it; new-style records
   additionally require the locked-proof evidence): that is
   "intake wants animated 3D and the board cannot feed it" caught at the
   board, not in the shipped site.

## Selection gate (human, recorded)

Present the ranked references (per board, highest weighted total first) to
the founder and ask which are selected. Default proposal: every reference
   at total ≥ 3.5 — a proposal heuristic, deliberately stricter than the
   check's enforcement floor (3.0 by default, `--floor` overridable): the
   floor is law, the proposal is taste. Record `selected: true` per chosen
   reference, set
   `selectionStatus: "approved"`, re-emit, re-check. **The designer consumes
   ONLY selected references** — via the commission, never the raw boards.

After approval, close the fidelity ladder: extract **style tokens** for
each selected reference into `tokens` (palette hexes, type register,
radius vocabulary, motion driver — judgment from the board's annotations
and the reference's public identity) and author one `tokenSynthesis`
block (the cross-pollinated starting direction: layout from one, palette
from another, motion from a third). Re-emit; the commission renders both
as its token layer — tokens beat screenshots beat adjectives.
