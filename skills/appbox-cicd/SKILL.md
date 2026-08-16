---
name: appbox-cicd
description: "Use when CI/CD must be stood up for any project — day zero or existing repo. Bootstrap mode grills the CI decisions first (visibility, runner, gates, trunk, protection, CD timing), then generates the one-root check script, workflow, PR template with [abx-<skill-name>] stage tags, runner setup and branch protection; green by absence from day zero. Adopt mode (CI already exists, e.g. a client repo) audits it against the guardrail list and sweeps the PRs — reads each PR, checks verdicts, reproduces red checks locally, reports merge-ready vs divergence vs runner-asleep; report-only, never bots or merges. Trigger on set up CI/CD, wire the pipeline, protect the branch, add a runner, check the PRs, adopt existing CI. Wires appbox gate --all for appbox-built targets; never duplicates validators."
---

# appbox-cicd — elicit the decisions, then wire the pipeline

> Per-skill playbook (the folded canon for this phase): [`CICD_playbook.mdx`](CICD_playbook.mdx)

```
orchestrator → intake → story-mapper → [moodboarder] → designer → scaffolder → builder
                                                             → tester → reviewer → deployer
appbox-cicd — the frame the build grows inside (day zero → deploy):
  day 0:  scripts/check.sh (green by absence) + skeleton workflow + PR template
  grow:   every stage’s gates wired in as artifacts appear (appbox gate --all)
  tail:   push/PR → gates → green merge → (deploy gate halts for operator)
```

## Pipeline position

Cross-cutting stage 10 — **not a build stage, but the frame the build grows inside**: invocable at day zero (before `appbox-intake` runs), and it wraps **all** stages — `appbox gate --all` runs every gate (intake, freeze, structure, scaffold, coverage, …), not just the tail. On push/PR those gates are the CI. The stage chain: `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.

- **Upstream:** `appbox-orchestrator` (stage Ø) — its dispatch calls this skill’s bootstrap as the first move after `appbox project init`; in an already-CI’d repo the operator invokes adopt mode directly.
- **Downstream:** every stage skill — their gates run inside this frame; `appbox-deployer`’s deploy job PREPARES and HALTS at its approval gate (CI never mints the token).

## Core principle

> **Core principle: elicit; never assume. CI decisions are the client's, not
> the agent's.** A pipeline built on guessed answers (public repo? macOS
> goldens? solo or team?) enforces the wrong contract permanently. This skill
> grills the decisions first — one question at a time, recommendation
> attached — then generates exactly what was agreed. Where the project is
> appbox-built, it WIRES existing gates (`appbox gate --all`); it never
> re-implements a validator that a gate already owns. (Precedent: reviewer's
> "this role wires existing tools; it builds nothing".)

## What you produce (and what you do not)

**Produce:** one organized folder `docs/ci/` — created first, even when
the repo has no `docs/` yet — holding every docs-side artifact:
`decisions.md` (the decision record), `setup.md` (runner recipe + solo
dev loop), `explainer.html` (the dual-version explanation page).
Platform-fixed paths stay where they must live: `scripts/check.sh`
(the one-root-check: local green = CI green), `.github/workflows/ci.yml`,
branch protection (`gh api`), — for appbox-built targets —
jobs that run `appbox gate --all` in dependency order, plus
`.github/pull_request_template.md` (the stage/agent field) and the
`[abx-<skill-name>]` PR-title tag map (one SSOT table emitted into
docs/ci/decisions.md, the template footer, and the title-check allowlist),
and `docs/ci/explainer.html` — the human-browsable explanation page for
the pipeline, zero-JS self-contained HTML generated from the template
[`references/ci-explainer.html`](references/ci-explainer.html). ONE
document, TWO readings, BOTH always written: a **plain-language version
(the default view)** for a non-technical reader — plain leads, what it
means for them, each technical term at most once in a small detail line —
and the full technical version (decisions with whys, job cards, ship
loop, guardrails). The in-page toggle is a native HTML checkbox + CSS: no
JavaScript, ever.

**Do not:** choose the stack, visibility, or trunk policy unasked; edit
`appboxd/lib/gate_*.dart` or any validator; mint deploy approval tokens;
register self-hosted runners on public repos; comment on PRs via bot, merge,
or push fixes from the sweep — the sweep REPORTS (babysit-pr owns watching).

## Procedure

### 0. Detect the mode (bootstrap vs adopt)

- **Bootstrap** — no `.github/workflows/ci.yml` and no `scripts/check.sh`:
  run the full decision grill below, then generate. Valid at day zero,
  BEFORE `appbox-intake` runs — the frame exists first, the build grows
  into it (green by absence until artifacts appear).
- **Adopt** — CI already exists (this repo or a client repo): SKIP
generation; audit the existing CI against the guardrail list (§ The
guardrail, as a test): per-job `timeout-minutes`, workflow `concurrency` +
`cancel-in-progress`, job-per-area (never one bare `gates` job), protection
`contexts` matching real job names, and a PR stage-tag convention (step 6).
Drift found → report + fix-list. Adopt the record too: decisions belong in
`docs/ci/decisions.md` (the organized folder — create it, and `docs/`,
if absent) — an existing `ci-decisions.md`/`ci-setup.md` or similar gets
moved into `docs/ci/` (references updated) or folded in, never duplicated. Then run the PR sweep (step 7).

### 1. Grill the decisions (ask_user_question / grill, ONE at a time)

Each question carries a recommendation + tradeoff. The decision tree, in
dependency order — every later answer depends on earlier ones:

1. **Deliverable** — what does this repo ship? (marketing site / app / ops
   tool / docs-only; determines whether gates are code gates or doc gates)
2. **Repo shape** — monorepo vs per-deliverable; if monorepo, business-domain
   top-level dirs (no `apps/` cargo-cult unless the client wants it).
3. **Stack** — for appbox-built targets: designer artifact (htmx+Dart) vs
   Flutter; for foreign stacks, whatever they use. The stack picks the gate
   commands, runner OS, and caching.
4. **Hosting & visibility** — where, and **private vs public**. Self-hosted
   runners are ONLY safe on private repos ("a stranger's PR would run
   arbitrary code on your machine" — the t3ci CI analysis, finding 03; external
   engagement notes, not a repo path). Public → GitHub-hosted,
   full stop.
5. **Runner** — self-hosted Mac (zero minutes, warm caches, real macOS;
   cost: CI queues when the machine sleeps) vs ubuntu-latest vs hybrid.
6. **Day-one gates** — lean: analyze + test + commit-convention, behind ONE
   root command (`scripts/check.sh`). Every job gets `timeout-minutes`
   and the workflow gets concurrency cancel-in-progress (the two gaps the
   t3ci analysis found in the app-box workflow). Commit convention REQUIRED
   from day one when the repo has no legacy commits — advisory only when
   measured history excuses it.
7. **Trunk & protection** — rename master→main before first push (free at 0
   commits); required checks = the real job names; `strict: true`; reviews
   only when a team exists; forbid force-push/delete.
8. **Agent letter** — AGENTS.md adapted to THIS repo (mandates = the check
   script + conventions; blast radius = real production targets);
   CLAUDE.md as pointer; file-pr/babysit-pr rewritten to this repo's check
   names; model-routing table EMPTY until the project's own audit fills it.
9. **CD timing** — defer deploy automation until a deployable artifact +
   target exist; when wired, the deploy job PREPARES and HALTS at the
   approval gate (it can never mint the token).

Record every answer in `docs/ci/decisions.md` — inside the organized
`docs/ci/` folder, created first if the repo has no `docs/` yet. The table
IS the shared understanding; confirm it before generating anything.

### 2. Generate the check contract

```sh
scripts/check.sh            # everything — this is what CI runs, verbatim
scripts/check.sh <area>     # one area (landing, commits, …)
```

Rules: fvm PATH injection when present; graceful skip when an area has no
code yet ("green by absence" — never red on an empty repo); conventional-
commit subject check with explicit bad-subject output. For appbox-built
targets the area's gates are `dart run appboxd/bin/appbox.dart gate --all` (or the
project-applicable subset) — the script wraps, never replaces.

### 3. Generate the workflow

Self-hosted shape (private repos):

```yaml
on:
  push: { branches: [main] }
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  <area>:                          # ONE job per area — the playbook law
    runs-on: [self-hosted, macOS, ARM64]   # labels from runner setup
    timeout-minutes: 15                     # ALWAYS — no job without one
    steps:
      - uses: actions/checkout@v4
      - run: scripts/check.sh <area>
```

Never one `gates` job running bare `scripts/check.sh` — job-per-area is
what makes required-check contexts and PR-check granularity work.

Then emit `docs/ci/explainer.html` (same organized folder): copy
[`references/ci-explainer.html`](references/ci-explainer.html), fill every
`{{TOKEN}}` from `docs/ci/decisions.md` and the workflow just generated —
BOTH versions, every time: the plain version is written for someone who
has never opened a terminal (lead with the human consequence; translate,
don't transplant config), the technical version keeps full fidelity.
The plain version is the default view; the toggle is a native checkbox —
zero JavaScript. docs/ci/decisions.md stays the SSOT — a decision not in the
record never appears on the page (either version); regenerate the page
whenever a decision or job changes (adopt mode emits it too, from the
audited state).

GitHub-hosted shape (public repos, or no always-on machine): same skeleton,
`runs-on: ubuntu-latest`, plus explicit setup actions + caching for the
stack's package manager. Commit-convention job uses `fetch-depth: 0` and
checks `origin/main..HEAD` on PRs, `HEAD` on pushes.

### 4. Runner + protection (run after first green)

Per-repo runner registration (`~/actions-runner-<repo>` — never share one
registration across repos), `svc.sh` service, labels `macOS,ARM64`. Then:

```sh
gh api repos/<owner>/<repo>/branches/main/protection --method PUT \
  -H "Accept: application/vnd.github+json" --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["<job names>"] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

### 5. Verify, then hand off

Watch the first run go green (`gh run watch`) BEFORE enabling protection.
Then: agent work on the repo flows through builder → tester → reviewer;
PRs flow through file-pr → babysit-pr; deploys halt at the deployer's
approval gate. This skill's output is the pipeline they run inside.

### 6. PR stage tagging (generate in bootstrap; wire in adopt)

Every PR names its stage/agent, in title AND summary:

- **Title:** `[abx-<skill-name>]` prefix — `[abx-designer][abx-scaffolder] home
  shell`. Multiple tags = the stages touched; the FIRST is the primary stage.
  Full skill names, no abbreviations: `abx-orchestrator, abx-intake,
  abx-story-mapper, abx-moodboarder, abx-designer, abx-scaffolder,
  abx-builder, abx-tester, abx-reviewer, abx-deployer, abx-lens, abx-lint,
  abx-cicd`.
- **Summary:** generate `.github/pull_request_template.md` with a
  `Pipeline stage / agent:` field (the `[abx-…]` tag + the full skill name).
- **Check:** a `pr-title` area in `check.sh` + the workflow validates the
  prefix against the tag map. **Warn-not-fail at first** — print the expected
tag and exit 0; flip to strict once the convention beds in. The flip is a
recorded decision in `docs/ci/decisions.md`.
- **One SSOT map** — the identical tag table is emitted into
  `docs/ci/decisions.md`, the template footer, and the check’s allowlist;
  never hand-maintain three lists.

### 7. PR sweep (adopt mode; report-only)

`gh pr list --json number,title,state,statusCheckRollup` → per PR: read
title/body/diff; `gh pr checks`; when a check is RED, reproduce locally
(`scripts/check.sh <area>`) to split CI-vs-local divergence. One feedback
report to the operator, per PR:

- **green** → merge-ready (required checks + protection already say so).
- **red + local green** → CI divergence (flaky runner, cache, env) — never
  “fix” code to match CI.
- **red + local red** → real defect; name the owning stage skill (the
  `[abx-…]` tag or the diff says which) and route it there.
- **queued / not running** → the runner is asleep; wake it — a queued job
  is NEVER fixed by changing code (babysit-pr owns this discipline).

The sweep REPORTS; it never comments via bot, never merges, never pushes
fixes — required checks already surface verdicts, and HUMAN GATES stand.

## The guardrail, as a test

- `scripts/check.sh` exits 0 on a fresh repo with no code ("green by
  absence") — CI is green on day zero, red only when something is real.
- The commit gate excludes merge commits (`git rev-list --no-merges`) —
  GitHub PR events test an auto-generated "Merge X into Y" commit whose
  mechanical subject false-positives a naive prefix check. Measured live on
  energize PR #1 (2026-08-16): red PR, green local, identical commands.
- A queued-but-not-running job is NEVER "fixed" by changing code — the
  runner is asleep; wake it. (babysit-pr owns this discipline.)
- Delete from `contexts` any job you rename — a stale context name bricks
  merges. Re-run the protection PUT after renaming jobs.

## Common mistakes

- **Generating before grilling.** Every unasked decision becomes a wrong
  default enforced by protection.
- **Self-hosted runner on a public repo.** Categorical no.
- **No timeout-minutes.** A hung job holds the merge queue forever.
- **Duplicating a validator.** If a gate exists, wire it; the reviewer's
  doctrine ("extend the gate, keep this role as wiring") applies here too.
- **Advisory checks that should be required.** No legacy commits = no excuse
  for lax commit subjects.
- **CD wired before a target exists.** Deploy machinery with nowhere to
  deploy is overbuild; the scope ceiling applies to pipelines too.
