---
name: appbox-lint
description: Use when health-checking the appbox knowledge base — catch contradictions, stale claims, dead links, orphan pages, and docs that disagree with shipped code or catalogs. Run before a session handoff, after a behavior change, or on "lint the docs", "check knowledge consistency", "is the wiki still true?".
---

# appbox-lint — keep the knowledge base honest

> Per-skill playbook (the folded canon for this phase): [`LINT_playbook.mdx`](LINT_playbook.mdx)

## Core principle

The expensive failure isn't a missing doc — it's a **confidently wrong** one.
Lint exists to catch that class of rot. It has two halves: a **mechanical**
pass (CLI checks, cheap, deterministic) and a **semantic** pass (you, reading
— judgment the script can't do). Run both.

## Pipeline position

Cross-cutting stage 7 — not phase-bound; valid at any point, and mandatory before a session handoff or after a behavior change. The stage chain: `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.

- **Upstream:** every other skill — this one audits the docs/KB claims all eleven make.
- **Downstream:** every skill that cites the knowledge base; no stage may run ahead of a doc it contradicts.

## The layers this skill audits (all real paths)

| layer | path | role |
|---|---|---|
| Enforced truth | `config/catalogs/*.json` | runtime vocabulary the gates read |
| Enforced truth | `appboxd/lib/*gate*.dart`, `kit/` | the behavior as shipped |
| Prose | `docs/` (`INDEX.md` is the index, `VOCABULARY.md` the glossary SSOT, `liquid-glass-allowlist.md` + `m3e-law.md` the platform laws) | explanation, plans, research |
| Memory | `memory/facts/*.json`, `memory/stages/*.LESSONS.md`, `memory/MEMORY.md` | cross-session facts + gate-triggered lessons |
| History | `git log` | what actually changed recently |

## Procedure

1. **Mechanical pass.**
   - `appbox docs` — dead `.md` links fail the run; unindexed docs and
     KB-lint orphans warn. Fix ERRORs first (usually: index the page in
     `docs/INDEX.md`, or fix the link). The live run against the real tree
     IS the regression check — the Dart port has no synthetic `--self-test`.
   - `appbox lint` — repo convention scan (R2/R3: e.g. absolute path
     literals that break portability). Fix what it names.

2. **Semantic pass — the part that matters.** For each topic touched recently
   (`git log --oneline -15`; the stage lessons in
   `memory/stages/*.LESSONS.md` are the de-facto change log), cross-check the
   claim across **all four layers** and find disagreement:
   `config/catalogs/*.json` ↔ `docs/` prose ↔ `memory/` ↔ the relevant
   gate/emitter in `appboxd/lib/`.
   Ask: does any layer state a rule that a higher layer (or the shipped code)
   contradicts? Vocabulary conflicts resolve in `docs/VOCABULARY.md` — it is
   the glossary SSOT.

3. **Resolve per the hierarchy: the enforced layer wins.** Catalogs and code
   ENFORCE; prose and memory lag. Fix the doc/memory to match the
   catalog/code — never the reverse — unless you've primary-source-verified
   the catalog/code is itself wrong (then fix IT, with evidence, in the same
   pass; do not paper over it in prose).

4. **Record it.** There is no `docs/changelog.md`; history is git. A durable
   lesson belongs in the owning stage's `memory/stages/<stage>.LESSONS.md`
   — appended only on observed gate failure, one line:
   `gate X failed because Y; do Z` (hard cap 200 lines, enforced by
   `appboxd/lib/memory_curate.dart`). Everything else lands as the direct
   doc/memory fix itself, in the commit.

5. **Suggest follow-ups.** Note gaps the lint can't fix: a concept mentioned
   everywhere but lacking a page in `docs/INDEX.md`, a plan whose
   done/active status is unverified, a catalog that may be stale against
   shipped code.

## Common mistakes

- **Trusting memory or a doc over a catalog/gate.** Catalogs enforce; prose
  lags. On conflict the prose is wrong.
- **Fixing only the file you noticed.** A wrong claim usually lives in 2–3
  places (docs + memory + a LESSONS line). Grep the assertion across all
  layers and fix every copy.
- **Skipping the semantic pass** because the CLI went green. The CLI checks
  plumbing, not truth. A perfectly-linked, fully-indexed doc set can still be
  confidently wrong.
- **Writing lessons speculatively.** `memory/stages/` is gate-triggered
  append-only — a lint observation is NOT a gate failure; record it as a doc
  fix, not a lesson.
- **Inventing paths.** This skill's older revision referenced
  `docs/KNOWLEDGE.md`, `docs/changelog.md`, `skills/refresh`,
  `catalogs/`, and Python stages that no longer exist — every one was a dead
  instruction. Audit against the table above; if a path here ever goes stale,
  `appbox docs` + this file's layer table are the contract.
- **Letting the check rot.** If you change `appboxd/lib/docs_lint.dart` or
  `appboxd/lib/lint_conventions.dart`, keep `appbox docs` / `appbox lint`
  green against the real repo tree.
