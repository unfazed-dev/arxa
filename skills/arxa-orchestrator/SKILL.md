---
name: arxa-orchestrator
description: "Use when a user wants to start an arxa project or ask where a project stands — the interactive front door (stage Ø, before stage 0): asks where to create the project (ARXA_HOME, name, targets, locales), runs arxa project init verbatim, hands off to arxa-cicd day-zero bootstrap, then dispatches to the right stage skill by reading pipeline state; also the cross-stage where-are-we view. Trigger on start a project, new app, create a project, where are we, what is next. It never owns a stage, never writes artifacts, never enforces ordering — the FSM and gates stay the only enforcer."
license: MIT
---

# arxa-orchestrator — the operator’s front door (stage Ø)

> Per-skill playbook (the folded canon for this phase): [`ORCHESTRATOR_playbook.mdx`](ORCHESTRATOR_playbook.mdx)

## Core principle

> **The orchestrator CONVEYS; it never owns.** The FSM and the gates stay the
> only enforcer of order; every stage skill keeps its own contract. This skill
> asks, dispatches, and reports. It produces no artifact, holds no state of its
> own, and gates nothing.

## Pipeline position

Stage Ø (before stage 0) of `arxa-orchestrator` (Ø, front door) → `arxa-story-mapper / arxa-moodboarder` (0, optional) → `arxa-intake` (1) → `arxa-designer` (2) → `arxa-scaffolder` (3) → `arxa-builder` (4) → `arxa-tester` (5) → `arxa-reviewer` (6) → `arxa-deployer` (9) — cross-cutting: `arxa-lint` (7), `arxa-lens` (8), `arxa-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage’s input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/arxa-system-map.md`; the CLI FSM phases: `arxa/lib/phases.dart`.

- **Upstream:** the operator — a conversation (start a project, where are we).
- **Downstream:** `arxa-cicd` first (day-zero bootstrap — the frame the build grows inside), then the whole chain by state: stages 0 → 9, with `arxa-lens` (8) and `arxa-lint` (7) valid anywhere.

## What you own (three things, nothing else)

1. **Interactive start — TWO modes, decided by one question first: does this
   product live in an EXISTING repo?**

   **Repo mode (the arxa law):** when arxa runs inside a client repo, ALL
   pipeline state lives in that repo — `~/.arxa/projects/` is for
   arxa-NATIVE projects only, and a project existing in both places is a
   hard error (`repo_project.dart`). Ask: which app dir (e.g. `landing/`,
   `studio/`) → kind (**`site`** = web/landing, htmx + islands; **`app`** =
   Flutter targets — this decides the whole stack downstream) → targets →
   locales. Then run verbatim:
   ```sh
   arxa project init --repo <app-dir> --kind site|app \
     [--name <n>] --targets web --locales en,fr
   ```
   This writes the `arxa.json` marker + the 8 stage folders (intake
   moodboard design scaffold build test review deploy) with kind-aware,
   CLI-owned READMEs. `arxa project resolve` from any subdir reports the
   binding. `arxa project sync <app-dir>` later pushes kind/targets/locales
   from intake answers into the marker.

   **Native mode:** project name (lowercase alnum + dash) → where (which
   `ARXA_HOME`; default `~/.arxa`) → targets (default ios, android, macos)
   → locales (default en, pl). Then run the existing CLI verbatim — never
   create directories by hand:
   ```sh
   arxa project init <name> --targets ios,android,macos --locales en,pl
   arxa project use <name>
   ```
   (`arxa/lib/project_cli.dart`; `ensureProject` is idempotent and validates
   the name.)
2. **Dispatch.** Read the state (`arxa project list`; stage is derived from
   which outputs exist — `projectStage()` in `arxa/lib/project.dart`), then
   point to exactly ONE next skill (table below). The first call after creation
   is always `arxa-cicd` — bootstrap in a repo with no CI, adopt in one with CI.
3. **The cross-stage view.** Where are we — one report: current project, its
   stage, the gates’ green/red, and the one skill that owns the next move.

## Dispatch table

| state you observe | the one next skill |
|---|---|
| project just created, or repo has no CI yet | `arxa-cicd` — bootstrap |
| CI exists (`ci.yml`, `scripts/check.sh`) | `arxa-cicd` — adopt + PR sweep |
| no brief; requirements raw | `arxa-story-mapper` (0) or `arxa-intake` (1) — intake optional |
| brief exists, no visual references | `arxa-moodboarder` (0) |
| moodboard scored, selection NOT approved | the founder — the human selection gate |
| selection approved, no `design/commission.md` | run `arxa design commission <app-dir>` |
| commission exists, no authored design | `arxa-designer` (2) |
| design frozen (`approval.lock`, `structure.json`) | `arxa-scaffolder` (3) |
| stub tree emitted | `arxa-builder` (4) |
| bodies filled | `arxa-tester` (5) |
| suite green + freeze | `arxa-reviewer` (6) |
| GREEN verdict | `arxa-deployer` (9) |
| a rendered surface needs eyes | `arxa-lens` (8) — any time |
| docs/KB suspected stale | `arxa-lint` (7) — any time |

## What you do NOT do

- Never owns a stage: no elicitation, no authoring, no scaffolding, no testing,
  no review, no deploy — dispatch to the skill that does.
- Never writes project artifacts — the CLI writes; you invoke it verbatim.
- Never enforces ordering — the FSM (`arxa/lib/phases.dart`) and the gates
  enforce; you only point.
- Never re-implements a validator, gate, or check — if a verb is missing, it
  belongs in the owning skill or `arxa`, not here.

## Procedure

1. Ask where + name + targets + locales (ONE at a time, recommendation attached).
2. `arxa project init <name> …` then `arxa project use <name>`; show the
   operator what was created.
3. Hand off to `arxa-cicd` (bootstrap or adopt) — CI is green-by-absence from
   day zero.
4. Dispatch per the table; on where-are-we, report the cross-stage view.
