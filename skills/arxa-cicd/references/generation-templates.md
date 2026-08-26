# Generation templates

## 2. Generate the check contract

```sh
scripts/check.sh            # everything — this is what CI runs, verbatim
scripts/check.sh <area>     # one area (landing, commits, …)
```

Rules: fvm PATH injection when present; graceful skip when an area has no
code yet ("green by absence" — never red on an empty repo); conventional-
commit subject check with explicit bad-subject output. For arxa-built
targets the area's gates are `dart run arxa/bin/arxa.dart gate --all` (or the
project-applicable subset) — the script wraps, never replaces.

## 3. Generate the workflow

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

## 4. Runner + protection (run after first green)

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
