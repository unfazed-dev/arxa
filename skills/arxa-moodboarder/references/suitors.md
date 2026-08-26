# Suitors — the direction audition

## Suitors — the direction audition (the second human gate)

Selection picks *references*; it does not pick a *direction*. Between the
selection gate and the commission, the moodboarder synthesizes exactly
**three candidate directions** — suitors — from the SELECTED set only, and
the human picks one. This is the pipeline-scale form of the options law
(build distinct options A, B, C…, stop, wait for a pick): a single
`tokenSynthesis` reaches the commission unauditioned; under the audition
it is the legacy fallback.

**Synthesis rules:**

- Exactly three suitors, labeled **A, B, C** — 2 is a coin flip, 5 is
  another moodboard. Project-level, never per-board: the site gets ONE
  direction, not one per slice.
- Built from the selected references only. Each suitor names its lead
  references as `<boardId>/<reference name>` and says what it takes from
  each — cross-pollination attribution (layout from one, palette from
  another, motion from a third; never a clone of a single reference).
- Each suitor carries a **spread statement**: the register it owns that the
  other two do not. If the selected set cannot yield three honest
  directions, STOP and surface the finding ("your selections are one
  direction — confirm or diversify"); three clones is a failed audition,
  not a completed one. (Energize's cautionary case: top-3-by-score on the
  main board was one premium-minimal direction three times — the rubric
  ranks references within a register; it cannot manufacture spread.)
- Tokens are **lens-measured where the reference is publicly reachable**:
  palette/type via `arxa lens tokens`, motion driver via two
  settle-state captures or burst frames. Record each suitor's
  `provenance` as `measured` (with `evidence` entries under
  `moodboard/evidence/…`) or `judged` (memory-judgment, graded and
  visible as such). Measured beats judged beats remembered.
- No layout sketches, no mockups — the moodboarder gathers and synthesizes;
  the designer designs (architecture §22).

**The gate.** Present the three suitors and ask for one **primary**,
optionally with attribute-scoped **remix clauses** from the closed
vocabulary — `palette`, `type`, `radius`, `motion`,
`layout-register` ("B, but motion from C" is a complete answer). Record
into the moodboard answer group, re-emit, and run `arxa moodboard
check <intake-dir>` — the gate has teeth:

- exactly three suitors labeled A/B/C; leads resolving to selected
  references; measured suitors carrying evidence that resolves on disk;
- `suitorChoice` ordered after selection approval (a pending selection
  cannot audition) and remixing only the closed vocabulary, never the
  primary itself;
- on new-style records, every locked-criterion score ≥ 3 carries cited
  lens evidence (the locked-proof law above).

A record with suitors but no `suitorChoice` is a pending audition:
`arxa design commission` refuses to compile it until the human picks.

```json
"suitors": [
  { "id": "A", "name": "cinematic-minimal product stage",
    "spread": "owns the dark, scroll-scrubbed, product-as-hero register",
    "leads": ["main/Polestar", "motion/Apple product pages"],
    "tokens": { "palette": "…", "type": "…", "motion": "…" },
    "provenance": "measured",
    "evidence": [ { "kind": "tokens", "file": "evidence/suitor-a__tokens.json" } ] }
],
"suitorChoice": { "primary": "B", "remix": [ { "attribute": "motion", "from": "C" } ] }
```

**Grandfather.** Records made before the audition (energize included) stay
valid under the law of their day — the gate applies from its landing, never
retroactively.
