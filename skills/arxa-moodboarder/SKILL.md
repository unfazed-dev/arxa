---
name: arxa-moodboarder
description: "Use when a story map / requirements brief should become a browsable moodboard of real reference apps — fans out one gathering subagent per epic, captures screenshots of the key screens with the arxa lens under semantic filenames, and assembles the moodboard the arxa-designer consults alongside docs/intake/brief.md. Runs after arxa-story-mapper, before design. Trigger on moodboard, design references, visual direction, 'what should it look like', gather reference apps, capture screenshots for design."
license: MIT
---

# arxa-moodboarder — requirements → references → shots → moodboard

> Per-skill playbook (the folded canon for this phase): [`MOODBOARD_playbook.mdx`](MOODBOARD_playbook.mdx)

```
story-mapper  →  moodboarder  →  arxa-designer
                 (docs/moodboards/)
```

Elicits **visual direction**, the same way the story-mapper elicits scope:
it gathers and captures; it does NOT design (architecture §22). The output is
the client's references, curated and screenshotted — the designer's job is
still the design.

## When to run

After `docs/intake/story-map.json` exists, before `arxa-designer` runs.
Also runnable standalone whenever a requirement needs visual references
("get me a moodboard for X").

**Chain position:** stage 0 of `arxa-orchestrator` (Ø, front door) → `arxa-story-mapper / arxa-moodboarder` (0, optional) → `arxa-intake` (1) → `arxa-designer` (2) → `arxa-scaffolder` (3) → `arxa-builder` (4) → `arxa-tester` (5) → `arxa-reviewer` (6) → `arxa-deployer` (9) — cross-cutting: `arxa-lint` (7), `arxa-lens` (8), `arxa-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/arxa-system-map.md`; the CLI FSM phases: `arxa/lib/phases.dart`.

- **Upstream:** `arxa-story-mapper` — `docs/intake/story-map.json` defines the slices.
- **Downstream:** `arxa-designer`, which consults the moodboard alongside `docs/intake/brief.md` before authoring. Captures use `arxa-lens`.

## The orchestration

1. **Slice the map.** One gathering slice per epic (per feature when an epic
   holds 3+ features). Each slice gets one subagent; slices fan out in
   parallel (one message, ≤8).
2. **Gather** — each subagent runs the prompt template below.
3. **Capture** — screenshots of every key screen, via the arxa lens, under the
   filename convention below.
4. **Assemble** — one moodboard doc per slice + embedded local shots.
5. **Verify** — every embedded `![](shots/…)` path resolves to a file on
   disk. An asset check that verifies strings instead of resolving paths is
   this project's recurring green-gate defect; do not repeat it.
6. **Hand off** — the brief carries the moodboard (`intake.moodboard`
   surface); the designer consults it before authoring.

## Where boards live (the arxa law)

Repo-mode project (an `arxa.json` marker above cwd): boards at
`<app-dir>/moodboard/boards/<slice-slug>.md`, shots at
`<app-dir>/moodboard/shots/<slice-slug>/…`. Arxa-native project: the same
`moodboard/` shape under `~/.arxa/projects/<name>/`. The legacy
`docs/moodboards/` path is pre-law — migrate, do not extend.

## Handoff

- The downstream consumer is `arxa design commission <app-dir>`: it
  compiles `design/commission.md` + `design/commission-prompt.md` from the
  brief, the direction, and ONLY the selected references with their scores,
  and REFUSES to run while `selectionStatus` is not `approved`. On
  new-style records it also REFUSES while `suitorChoice` is absent, and
  renders the chosen suitor (+ remixes) as the mandate's token spine.
- `arxa-designer`: consume the commission as a binding contract before
  authoring; the boards' "patterns this slice must have" lists remain the
  per-epic visual bar behind it.

## References

- `references/gathering-capture.md` — load for step 2 (Gather): the subagent
  prompt template; and step 3 (Capture): arxa lens shot commands, viewport
  args, and the shot filename convention.
- `references/assembly-verify-score.md` — load for step 4 (Assemble): the
  board doc format; step 5 (Verify): the runnable shot-resolution check; and
  scoring references against the intake-derived rubric (including the
  locked-criterion proof requirement).
- `references/record-selection.md` — load when writing the moodboard into
  `intake/answers.json` and re-emitting, and when running the human
  selection gate (ranked references, the ≥3.5 proposal heuristic, token
  extraction).
- `references/suitors.md` — load when synthesizing the three candidate
  directions (the second human gate) after selection is `approved`: synthesis
  rules, the primary/remix gate, and the suitor JSON shape.
