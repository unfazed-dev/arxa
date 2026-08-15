---
name: appbox-cicd
description: Use to stand up CI/CD for any project — grills the CI decisions first (visibility, runner, gates, trunk, protection, CD timing), then generates the one-root check script, GitHub Actions workflow, runner setup and branch protection. Trigger on "set up CI/CD", "wire the pipeline", "protect the branch", "add a runner". Wires appbox gate --all for appbox-built targets; never duplicates validators.
---

# appbox-cicd — elicit the decisions, then wire the pipeline

```
intake → story-mapper → [moodboarder] → designer → scaffolder → builder
                                          → tester → reviewer → deployer
                                                          ↑
                              appbox-cicd wraps these in automation:
                              push/PR → gates → green merge → (deploy gate halts for operator)
```

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

**Produce:** the decision record (docs/ci-decisions.md), `scripts/check.sh`
(the one-root-check: local green = CI green), `.github/workflows/ci.yml`,
branch protection (`gh api`), runner setup doc, and — for appbox-built
targets — jobs that run `appbox gate --all` in dependency order.

**Do not:** choose the stack, visibility, or trunk policy unasked; edit
`appboxd/lib/gate_*.dart` or any validator; mint deploy approval tokens;
register self-hosted runners on public repos.

## Procedure

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
   arbitrary code on your machine" — t3ci/CI/03). Public → GitHub-hosted,
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

Record every answer in `docs/ci-decisions.md` — the table IS the shared
understanding; confirm it before generating anything.

### 2. Generate the check contract

```sh
scripts/check.sh            # everything — this is what CI runs, verbatim
scripts/check.sh <area>     # one area (landing, commits, …)
```

Rules: fvm PATH injection when present; graceful skip when an area has no
code yet ("green by absence" — never red on an empty repo); conventional-
commit subject check with explicit bad-subject output. For appbox-built
targets the area's gates are `dart run bin/appbox.dart gate --all` (or the
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
