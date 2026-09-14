# CI/CD decision record — arxa monorepo

> SSOT for every pipeline decision (skills/arxa-cicd). `docs/ci/explainer.html`
> is derived from this file; if a decision is not recorded here, it does not
> exist anywhere else either.
>
> **Recorded 2026-09-14** (Task 12, mobile closeout). The decisions below were
> pre-made for this product by the closeout brief and its governing docs — the
> generic bootstrap grill was deliberately NOT re-run. Adoption note: this repo
> already had `desktop-gate.yml` / `desktop-release.yml` and
> `docs/ci/{release-ops,self-hosted-runners}.md`; this record adopts the
> existing frame and extends it with the mobile lanes — nothing here
> contradicts those files except the one recorded exception below.

## The decisions

| # | Decision | Choice | Why (recorded tradeoff) |
|---|----------|--------|-------------------------|
| 1 | Deliverable | The arxa monorepo + its `mobile_flutter` target (plus `kit/studio_transport`) | One repo, one frame; the mobile target is arxa-built (`arxa.json`) so its gates are `arxa gate --all`, wired not duplicated |
| 2 | Repo shape | Private monorepo (single arxa repo) | Already private; self-hosted-runner safety rule applies |
| 3 | Stack | Flutter (fvm pin 3.44.9 = `mobile_flutter/.fvmrc`), Rust transport crate, Dart CLI | The pin is the SSOT — workflows hardcode the same number with a pointer back |
| 4 | Hosting / visibility | GitHub, private | Unchanged |
| 5 | Runner | **Mobile gate lanes: GitHub-hosted Ubuntu** (recorded exception to `docs/ci/self-hosted-runners.md`'s all-self-hosted rule). **iOS lanes: existing `[self-hosted, macOS, ARM64, arxa]` labels** (same runner that serves the desktop jobs) | Format/analyze/test and the Android build need no Apple hardware; hosting them on Ubuntu decouples mobile-gate availability from the single macOS box (and avoids running the Flutter Android toolchain on the operator's daily driver). iOS archive/export genuinely needs macOS → self-hosted labels, per the standing rule |
| 6 | Day-one gates | `scripts/check.sh` areas: `commits`, `pr-title`, `gates`, `mobile`, `mobile-signing`, `transport` | Green by absence; one job per area so required-check contexts stay granular |
| 7 | Trunk / protection | `main` trunk, PR flow. Protection (strict contexts = the six job names, no force-push, no deletions) goes on **after the first green run is watched** — see setup.md; not applied by this change | Watch-then-protect is the skill's verify step; protecting before the first run bricks merges if a job name is wrong |
| 8 | Agent letter | PR titles carry `[arxa-<skill-name>]` stage tags (map below); template footer carries the same table | One SSOT map: decisions.md = template footer = `scripts/check.sh pr-title` allowlist |
| 9 | CD timing | **Prepare-then-halt.** `mobile-release.yml` builds, checksums, validates signing — then HALTS at the human deploy gate (HUMAN GATE 3: a person confirms target + version + account). Upload lanes (`fastlane android beta|production`, `fastlane ios beta|release`) are operator-run | Deploy is the one irreversible pipeline act; CI never mints the approval token (skills/arxa-deployer). M5: TestFlight + Play internal first |

### Derived, recorded with their own whys

- **Concurrency + cancellation**: `concurrency: ci-${{ github.ref }}` with
  `cancel-in-progress` on `ci.yml`; per-job `timeout-minutes` on every job —
  a hung job must never hold a merge queue open, a superseded run must not
  waste the runner. `mobile-release.yml` sets `cancel-in-progress: false` —
  a half-cancelled release build is worse than a slow one.
- **`pr-title` is warn-not-fail** (prints the expected tag, exits 0). The flip
  to strict is a future recorded decision, not a silent change. The repo's
  first tagged PR has not happened yet; the convention beds in first.
- **No `paths:` filters on ci.yml jobs** — skipped jobs interact badly with
  strict required contexts (a docs-only PR would block on missing checks).
  The lanes are cheap enough to run always; cancellation handles the noise.
  (`desktop-gate.yml` keeps its own paths filters — desktop-only, unchanged.)
- **Signing custody**: Android release signing loads from gitignored
  `android/key.properties` (CI writes it from `mobile-release` environment
  secrets); a release packaging task with absent inputs fails CLEARLY
  (`build.gradle.kts` throws) — debug builds alone may use the debug key.
  iOS: team `43GNRCGQXQ`, bundle `solutions.arxadigital.arxa.mobile`
  confirmed against `project.pbxproj`; release signing is match-owned with
  export options carried in the Fastfile (no Xcode tree edits); the committed
  `aps-environment: development` entitlement flips to production with the
  app-store export profile.
- **`arxa gate --all` wrapped, never duplicated**: `check.sh` adds only what
  no gate owns (commit subjects, PR tags, the Flutter loop, the signing
  contract asserts). Gate exit 2 (env/not-applicable) is a skip, not red.
- **OTA (Shorebird)**: extension point accepted and created DORMANT
  (`mobile_flutter/shorebird.yaml`, empty `app_id`). The migration spec's
  distribution plan (M5) has no OTA rows; inventory row AXS-011 names
  Shorebird in this task's closure work. Activation is an operator action
  (`shorebird create-app`), not a pipeline change.

## PR stage-tag map (SSOT)

Same table lives in `.github/pull_request_template.md` and the
`scripts/check.sh pr-title` allowlist — never hand-maintain three lists.

| Tag | Stage |
|-----|-------|
| `[arxa-orchestrator]` | Ø — project front door |
| `[arxa-intake]` | 1 — intake answers |
| `[arxa-story-mapper]` | 0 — story map |
| `[arxa-moodboarder]` | 0 — references |
| `[arxa-designer]` | 2 — design surfaces |
| `[arxa-scaffolder]` | 3 — emit the app |
| `[arxa-builder]` | 4 — fill surfaces |
| `[arxa-tester]` | 5 — tests |
| `[arxa-reviewer]` | 6 — pre-release QC |
| `[arxa-deployer]` | 9 — stores / OTA / web |
| `[arxa-lens]` | 8 — visual evidence |
| `[arxa-lint]` | 7 — knowledge health |
| `[arxa-cicd]` | 10 — the frame itself |

First tag = primary stage; multiple tags = multiple stages touched.
