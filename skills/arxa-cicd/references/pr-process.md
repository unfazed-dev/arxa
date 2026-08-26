# PR process

## 6. PR stage tagging (generate in bootstrap; wire in adopt)

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

## 7. PR sweep (adopt mode; report-only)

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
