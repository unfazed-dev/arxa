# appbox-cicd

The CI/CD setup skill: grills the project's CI decisions, then generates the
check-contract (`scripts/check.sh`), GitHub Actions workflow, branch
protection, and runner setup. Generic over any project; for appbox-built
targets it wires `appbox gate --all` instead of inventing checks.

## Files

- `SKILL.md` — the operative skill (start here)
- `CICD_playbook.mdx` — the canon: decision tree detail, generated-artifact
  templates, the t3ci improvement list, verification recipes
- `references/ci-explainer.html` — the zero-JS template for the generated
  `docs/ci/explainer.html` explanation page. All docs-side artifacts land in
  one organized `docs/ci/` folder — created, with `docs/`, if absent:
  `decisions.md`, `setup.md`, `explainer.html`. One document, two readings,
  both always written: a plain-language version for non-technical readers
  (the default view) and the full technical version, toggled in-page by a
  native HTML checkbox — no JavaScript (t3ci-reference style)

## Position in the pipeline

Not a build stage — the frame the build grows inside: invocable at day zero
(before intake), wrapping ALL gates (`appbox gate --all`); the tail —
tester's suites, reviewer's verdicts, deployer's gates — runs inside it once
artifacts exist. Two modes: bootstrap (no CI) and adopt (audit existing CI +
report-only PR sweep). Deploy stays operator-approved; CI prepares and halts.

## Provenance

Distilled from the t3ci bundle (app-box CI bootstrap + Theo/t3.gg video
findings) plus its post-hoc analysis: every improvement there — job
timeouts, explicit caching on hosted runners, concurrency cancel, day-one
required commit convention, per-repo runner registration, protection
recipes — is embodied here. First consumer: the energize engagement
(external client repo, 2026-08-16), where the full decision tree was first walked.
