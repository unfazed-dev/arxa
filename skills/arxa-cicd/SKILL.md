---
name: arxa-cicd
description: "Use when CI/CD must be stood up for any project — day zero or existing repo. Bootstrap mode grills the CI decisions first (visibility, runner, gates, trunk, protection, CD timing), then generates the one-root check script, workflow, PR template with [arxa-<skill-name>] stage tags, runner setup and branch protection; green by absence from day zero. Adopt mode (CI already exists, e.g. a client repo) audits it against the guardrail list and sweeps the PRs — reads each PR, checks verdicts, reproduces red checks locally, reports merge-ready vs divergence vs runner-asleep; report-only, never bots or merges. Trigger on set up CI/CD, wire the pipeline, protect the branch, add a runner, check the PRs, adopt existing CI. Wires arxa gate --all for arxa-built targets; never duplicates validators."
---

# arxa-cicd — elicit the decisions, then wire the pipeline

> Per-skill playbook (the folded canon for this phase): [`CICD_playbook.mdx`](CICD_playbook.mdx)

```
orchestrator → intake → story-mapper → [moodboarder] → designer → scaffolder → builder
                                                             → tester → reviewer → deployer
arxa-cicd — the frame the build grows inside (day zero → deploy):
  day 0:  scripts/check.sh (green by absence) + skeleton workflow + PR template
  grow:   every stage’s gates wired in as artifacts appear (arxa gate --all)
  tail:   push/PR → gates → green merge → (deploy gate halts for operator)
```

## Pipeline position

Cross-cutting stage 10 — **not a build stage, but the frame the build grows inside**: invocable at day zero (before `arxa-intake` runs), and it wraps **all** stages — `arxa gate --all` runs every gate (intake, freeze, structure, scaffold, coverage, …), not just the tail. On push/PR those gates are the CI. The stage chain: `arxa-orchestrator` (Ø, front door) → `arxa-story-mapper / arxa-moodboarder` (0, optional) → `arxa-intake` (1) → `arxa-designer` (2) → `arxa-scaffolder` (3) → `arxa-builder` (4) → `arxa-tester` (5) → `arxa-reviewer` (6) → `arxa-deployer` (9) — cross-cutting: `arxa-lint` (7), `arxa-lens` (8), `arxa-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/arxa-system-map.md`; the CLI FSM phases: `arxa/lib/phases.dart`.

- **Upstream:** `arxa-orchestrator` (stage Ø) — its dispatch calls this skill’s bootstrap as the first move after `arxa project init`; in an already-CI’d repo the operator invokes adopt mode directly.
- **Downstream:** every stage skill — their gates run inside this frame; `arxa-deployer`’s deploy job PREPARES and HALTS at its approval gate (CI never mints the token).

## Core principle

> **Core principle: elicit; never assume. CI decisions are the client's, not
> the agent's.** A pipeline built on guessed answers (public repo? macOS
> goldens? solo or team?) enforces the wrong contract permanently. This skill
> grills the decisions first — one question at a time, recommendation
> attached — then generates exactly what was agreed. Where the project is
> arxa-built, it WIRES existing gates (`arxa gate --all`); it never
> re-implements a validator that a gate already owns. (Precedent: reviewer's
> "this role wires existing tools; it builds nothing".)

## What you produce (and what you do not)

**Produce:** one organized folder `docs/ci/` — created first, even when
the repo has no `docs/` yet — holding every docs-side artifact:
`decisions.md` (the decision record), `setup.md` (runner recipe + solo
dev loop), `explainer.html` (the dual-version explanation page).
Platform-fixed paths stay where they must live: `scripts/check.sh`
(the one-root-check: local green = CI green), `.github/workflows/ci.yml`,
branch protection (`gh api`), — for arxa-built targets —
jobs that run `arxa gate --all` in dependency order, plus
`.github/pull_request_template.md` (the stage/agent field) and the
`[arxa-<skill-name>]` PR-title tag map (one SSOT table emitted into
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
`arxa/lib/gate_*.dart` or any validator; mint deploy approval tokens;
register self-hosted runners on public repos; comment on PRs via bot, merge,
or push fixes from the sweep — the sweep REPORTS (babysit-pr owns watching).

## Procedure

### 0. Detect the mode (bootstrap vs adopt)

- **Bootstrap** — no `.github/workflows/ci.yml` and no `scripts/check.sh`:
  run the full decision grill below, then generate. Valid at day zero,
  BEFORE `arxa-intake` runs — the frame exists first, the build grows
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

## References

- [`references/decision-grill.md`](references/decision-grill.md) — step 1, the 9-question decision tree (deliverable, repo shape, stack, hosting/visibility, runner, day-one gates, trunk/protection, agent letter, CD timing). Load during bootstrap mode, before generating anything.
- [`references/generation-templates.md`](references/generation-templates.md) — steps 2–4: the check-script rules, the self-hosted/GitHub-hosted workflow YAML + explainer.html emission, and the branch-protection `gh api` call. Load while generating bootstrap artifacts.
- [`references/pr-process.md`](references/pr-process.md) — steps 6–7: PR stage tagging (`[arxa-<skill-name>]` convention, template, SSOT tag map) and the adopt-mode PR sweep (report-only triage of green/CI-divergence/real-defect/runner-asleep). Load when wiring PR conventions or running an adopt-mode sweep.
- [`references/ci-explainer.html`](references/ci-explainer.html) — the zero-JS dual-reading HTML template filled by step 3. Load when generating or regenerating `docs/ci/explainer.html`.
- [`CICD_playbook.mdx`](CICD_playbook.mdx) — the folded canon for this phase; consult for deeper background beyond this skill's law.
