# memory/ — appbox curated memory

The durable, human-auditable memory of the appbox pipeline. Files, not a
service: plain markdown + JSON, git-tracked, diffable, deletable. appbox owns
this tree — stacked_kit's `memory/` is the template, never a dependency
(docs/plans/appbox-memory-and-payment.md, M1).

Consumers: the engine (self-tuning prompt assembly), the operator (briefings).
Per-app runtime memory ships as a kit inside generated apps — never here.

## Write-path doctrine (M1)

- **Raw events, always.** Deterministic writers (gates, runner, gateway)
  append raw events — scorecards, usage, gate outcomes — to the appboxd data
  dir (JSONL, git-ignored, high-volume). Nothing curated lives there.
- **Curated lessons, gate-triggered only.** A consolidation stage promotes
  durable lessons into `stages/`, and its output passes a gate like every
  other artifact. Writes are appended ONLY on observed gate failure — the
  trigger is an observed event, not an inference. The mem0 production audit
  (97.8% junk memories in 32 days) is what unconstrained "what's worth
  remembering" writes produce; the write path is the bottleneck, not the model.
- **A gate consumes it, or it rots.** `gates/memory/` asserts the hygiene of
  this tree (index size, facts parse, lesson caps, no absolute paths).

## Layout

- `MEMORY.md` — this index. Hard cap 100 lines; consolidate, don't grow.
- `facts/<topic>.json` — durable facts as a JSON array of `{fact, source, ts}`.
  Seeded from the decisions records; add a topic file when a decisions doc
  lands durable facts. Read via `MemoryCurator.readFacts`.
- `stages/<stage>.LESSONS.md` — one lesson log per pipeline stage (intake,
  structure, scaffold, coverage, freeze, review, native_deps, advertise,
  deploy). Append-only via `MemoryCurator.appendLesson`, human-editable, hard
  cap 200 lines — oldest lessons dropped on overflow. Read into the stage
  prompt's static prefix via `MemoryCurator.lessonsFor` (lessons sit inside
  the cached prefix and cost ~0 on repeat runs).

## What this is NOT (M2)

No mem0/Letta/Zep-class agent-memory framework, no semantic cache, no vector
retrieval — at this scale `cat` beats ANN and the write path of agent-decided
memory is unsolved. Self-learning = scorecard affinity + these lesson logs +
cache-first prompt assembly + exact-match response cache.
