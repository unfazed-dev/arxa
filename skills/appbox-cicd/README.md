# appbox-cicd

The CI/CD setup skill: grills the project's CI decisions, then generates the
check-contract (`scripts/check.sh`), GitHub Actions workflow, branch
protection, and runner setup. Generic over any project; for appbox-built
targets it wires `appbox gate --all` instead of inventing checks.

## Files

- `SKILL.md` — the operative skill (start here)
- `CICD_playbook.mdx` — the canon: decision tree detail, generated-artifact
  templates, the t3ci improvement list, verification recipes

## Position in the pipeline

Not a build stage — the automation layer AROUND the tail: tester's suites,
reviewer's verdicts and deployer's gates run inside the CI this skill
stands up. Deploy stays operator-approved; CI prepares and halts.

## Provenance

Distilled from the t3ci bundle (app-box CI bootstrap + Theo/t3.gg video
findings) plus its post-hoc analysis: every improvement there — job
timeouts, explicit caching on hosted runners, concurrency cancel, day-one
required commit convention, per-repo runner registration, protection
recipes — is embodied here. First consumer: the energize engagement
(clients/energize), where the full decision tree was first walked.
