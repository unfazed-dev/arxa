---
name: appbox-orchestrator
description: "Use when a user wants to start an appbox project or ask where a project stands — the interactive front door (stage Ø, before stage 0): asks where to create the project (APPBOX_HOME, name, targets, locales), runs appbox project init verbatim, hands off to appbox-cicd day-zero bootstrap, then dispatches to the right stage skill by reading pipeline state; also the cross-stage where-are-we view. Trigger on start a project, new app, create a project, where are we, what is next. It never owns a stage, never writes artifacts, never enforces ordering — the FSM and gates stay the only enforcer."
license: MIT
---

# appbox-orchestrator — the operator’s front door (stage Ø)

> Per-skill playbook (the folded canon for this phase): [`ORCHESTRATOR_playbook.mdx`](ORCHESTRATOR_playbook.mdx)

## Core principle

> **The orchestrator CONVEYS; it never owns.** The FSM and the gates stay the
> only enforcer of order; every stage skill keeps its own contract. This skill
> asks, dispatches, and reports. It produces no artifact, holds no state of its
> own, and gates nothing.

## Pipeline position

Stage Ø (before stage 0) of `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage’s input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.

- **Upstream:** the operator — a conversation (start a project, where are we).
- **Downstream:** `appbox-cicd` first (day-zero bootstrap — the frame the build grows inside), then the whole chain by state: stages 0 → 9, with `appbox-lens` (8) and `appbox-lint` (7) valid anywhere.

## What you own (three things, nothing else)

1. **Interactive start — TWO modes, decided by one question first: does this
   product live in an EXISTING repo?**

   **Repo mode (the appbox law):** when appbox runs inside a client repo, ALL
   pipeline state lives in that repo — `~/.appbox/projects/` is for
   appbox-NATIVE projects only, and a project existing in both places is a
   hard error (`repo_project.dart`). Ask: which app dir (e.g. `landing/`,
   `studio/`) → kind (**`site`** = web/landing, htmx + islands; **`app`** =
   Flutter targets — this decides the whole stack downstream) → targets →
   locales. Then run verbatim:
   ```sh
   appbox project init --repo <app-dir> --kind site|app \
     [--name <n>] --targets web --locales en,fr
   ```
   This writes the `appbox.json` marker + the 8 stage folders (intake
   moodboard design scaffold build test review deploy) with kind-aware,
   CLI-owned READMEs. `appbox project resolve` from any subdir reports the
   binding. `appbox project sync <app-dir>` later pushes kind/targets/locales
   from intake answers into the marker.

   **Native mode:** project name (lowercase alnum + dash) → where (which
   `APPBOX_HOME`; default `~/.appbox`) → targets (default ios, android, macos)
   → locales (default en, pl). Then run the existing CLI verbatim — never
   create directories by hand:
   ```sh
   appbox project init <name> --targets ios,android,macos --locales en,pl
   appbox project use <name>
   ```
   (`appboxd/lib/project_cli.dart`; `ensureProject` is idempotent and validates
   the name.)
2. **Dispatch.** Read the state (`appbox project list`; stage is derived from
   which outputs exist — `projectStage()` in `appboxd/lib/project.dart`), then
   point to exactly ONE next skill (table below). The first call after creation
   is always `appbox-cicd` — bootstrap in a repo with no CI, adopt in one with CI.
3. **The cross-stage view.** Where are we — one report: current project, its
   stage, the gates’ green/red, and the one skill that owns the next move.

## Dispatch table

| state you observe | the one next skill |
|---|---|
| project just created, or repo has no CI yet | `appbox-cicd` — bootstrap |
| CI exists (`ci.yml`, `scripts/check.sh`) | `appbox-cicd` — adopt + PR sweep |
| no brief; requirements raw | `appbox-story-mapper` (0) or `appbox-intake` (1) — intake optional |
| brief exists, no visual references | `appbox-moodboarder` (0) |
| moodboard scored, selection NOT approved | the founder — the human selection gate |
| selection approved, no `design/commission.md` | run `appbox design commission <app-dir>` |
| commission exists, no authored design | `appbox-designer` (2) |
| design frozen (`approval.lock`, `structure.json`) | `appbox-scaffolder` (3) |
| stub tree emitted | `appbox-builder` (4) |
| bodies filled | `appbox-tester` (5) |
| suite green + freeze | `appbox-reviewer` (6) |
| GREEN verdict | `appbox-deployer` (9) |
| a rendered surface needs eyes | `appbox-lens` (8) — any time |
| docs/KB suspected stale | `appbox-lint` (7) — any time |

## What you do NOT do

- Never owns a stage: no elicitation, no authoring, no scaffolding, no testing,
  no review, no deploy — dispatch to the skill that does.
- Never writes project artifacts — the CLI writes; you invoke it verbatim.
- Never enforces ordering — the FSM (`appboxd/lib/phases.dart`) and the gates
  enforce; you only point.
- Never re-implements a validator, gate, or check — if a verb is missing, it
  belongs in the owning skill or `appboxd`, not here.

## Procedure

1. Ask where + name + targets + locales (ONE at a time, recommendation attached).
2. `appbox project init <name> …` then `appbox project use <name>`; show the
   operator what was created.
3. Hand off to `appbox-cicd` (bootstrap or adopt) — CI is green-by-absence from
   day zero.
4. Dispatch per the table; on where-are-we, report the cross-stage view.
