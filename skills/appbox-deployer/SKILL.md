---
name: appbox-deployer
description: 'Use when shipping an appbox-built target to stores (fastlane: TestFlight/App Store + Play internal/production), pushing an OTA Dart patch (shorebird), or deploying a web build to Cloudflare Pages/Workers or Vercel. Trigger on "deploy", "ship to TestFlight", "release to Play", "push an OTA patch", "hotfix", "deploy to Cloudflare Pages", "deploy to Vercel".'
---

# deployer — stores (fastlane) + OTA patches (shorebird) + web (Cloudflare Pages/Workers, Vercel)

> Per-skill playbook (the folded canon for this phase): [`DEPLOYER_playbook.mdx`](DEPLOYER_playbook.mdx)

## Core principle
fastlane, shorebird and wrangler are existing CLIs; this role drives them with a
recipe. The Fastfile, `shorebird.yaml` and Pages project are **operator-owned
extension points** — signing, bundle id, app ids and the Pages project name are
project secrets the pipeline never holds.

The mechanics live in `appboxd/lib/deploy.dart` (the Dart port of the former
`deploy.py`): the external CLIs are invoked through a `ProcessRunner` port, so
`appbox deploy --self-test` exercises **every command shape under a scripted
runner with no toolchain, no credentials and no signing identity** — the one
property that makes a deploy stage self-testable.

## Pipeline position

Stage 9 (packaging + deploy — the chain's end) of `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). HUMAN GATE 3 (`deploy --approval`, human-supplied, never minted by code) sits here. Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.

- **Upstream:** `appbox-reviewer` — ship only after the stage-6 GREEN verdict; the `native_deps` packaging gate runs in the build phase before this.
- **Downstream:** none — stores / OTA / web are the terminus. `appbox-cicd`'s deploy job PREPARES and HALTS at this approval gate.

## Targets — wired (honest about verification tier)

| target | status |
|---|---|
| `fastlane-ios` / `fastlane-android` | **wired** |
| `shorebird-release` / `shorebird-patch` | **wired** |
| `cloudflare-pages` | **wired** |
| `cloudflare-workers` | **wired** (port-tested) |
| `vercel` | **wired** (port-tested) |

All five are surfaced to an operator. `vercel` and `cloudflare-workers` are
port-tested tier: command shapes are covered by scripted-runner tests, but
neither has been CI-verified against a real project yet — `gates/advertise`
caps any offer at the tier recorded in `config/kit-registry.json`, so say
"port-tested", not "proven".

## Stores — fastlane (gym + match + deliver/supply)
1. **Once per project** — `fastlane init` in `<target>/ios` + `<target>/android`.
   Operator fills signing (`match`), bundle id, team. The Fastfile is an
   extension point, NOT pipeline-generated.
2. **Beta lane** — `fastlane beta`:
   - iOS: `gym` (build) → `match` (signing) → `upload_to_testflight`.
   - Android: `flutter build appbundle` → `upload_to_play_store(track: internal)`.
3. **Release lane** — `fastlane release`: store metadata (`deliver`/`supply`) +
   production track. Store listing copy ships in every launch locale (en + pl)
   — the metadata locales match the app's ARB set.

## OTA — shorebird (Dart hotpatch, no store review)
1. **Once** — `shorebird init` in target → `shorebird.yaml` (extension point; operator app id).
2. **Patch** — `shorebird release patch` after a Dart-only fix. Catches the 80% case (logic bug) without a store round-trip.
3. **Boundary** — shorebird patches Dart ONLY (their TOS: bug fixes, not new features / store-banned changes). Native changes → fastlane full release.

## Web — Cloudflare Pages (wrangler)
1. **Once** — `wrangler pages project create <name>` (operator-owned project).
2. **Deploy** — `wrangler pages deploy <dir> --project-name <name>`. Returns a
   deployment URL (the artefact id recorded in the ledger).

## Web — Cloudflare Workers (wrangler)
1. **Deploy** — `wrangler deploy` in the worker directory, with
   `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` in the ambient environment.
   Returns a deployment URL.

## Web — Vercel
1. **Build** — `flutter build web --release`.
2. **Deploy** — `vercel deploy build/web --prod --yes`, with `VERCEL_TOKEN` in
   the ambient environment (set `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID` to link
   non-interactively). Returns a deployment URL.

## Post-deploy live verification (web targets)

A web deploy is not done when the CLI returns — it is done when the LIVE
URL has been verified. Before the ledger entry closes, for every web
target (Pages, Workers, Vercel):

1. **Fetch the deployment URL** — assert three things: HTTP 200, a
   content signature of the markup (the localized `<title>` is enough),
   and one asset hash matching what you shipped (curl; never open a
   browser for a static doc). Status AND content — a `text/plain` 500
   error body is console-clean and byte-stable, so it sails through a
   naive probe (energize 2026-08-19: every route 500ed for hours while
   the close-out claimed the site verified).
2. **`appbox lens check <deployed-url>`** — console-clean plus one
   `--expect` probe against a behavior this deploy claims to change or
   preserve. A deploy whose live probe fails is a rollback decision, not a
   ledger note.
3. **Mind audit-gating on your own site** — pages that detect
   `navigator.webdriver` self-disable under the lens (LENS_playbook
   "Capability ceiling"); force the real path via a temporary build edit
   or assert source-verified behavior, and record which you did.
4. **Record it** — the ledger note says what was verified live ("verified
   local+live: <probe summary>"), not just that a deploy command ran.

This is the energize discipline made law: every ledger entry verifies
live before closing. Its 15th entry exists because the 14th's
"verified" checked asset bytes and console-clean only while every page
500ed — the rule existed in practice before it existed in writing, and
the outage is why step 1 now demands status + content.

## The deploy gate (the strictest human gate)
Deploy is a **write to the outside world** and the most irreversible act in the
pipeline — an App Store submission cannot be rolled back by re-running a stage.
So deploy is a third human gate (`gates/deploy/`), stricter than the quality
gates. It names the build **target**, the release **version** and the releasing
**account**, and requires a person to confirm that exact triple. The gate
asserts those three in pipeline state (`approvalTokens.deploy`); an agent may
prepare, run `doctor` preflight, reach the gate and **stop** — it can never mint
the approval token. `appbox deploy deploy` requires that approval as an argument and
halts (recording a `halted` ledger row, minting nothing) without it.
When CI is wired ([`appbox-cicd`](../appbox-cicd/SKILL.md)), the deploy job
PREPARES, `doctor`-checks and halts right here — the pipeline automation can
never mint the token either.

`doctor(config)` is **preflight, not the gate** — it reports readiness; the gate
still has to assert a value.

## Rules
- Never commit secrets — `.env` (Supabase), signing (`match` storage), store keys, the Cloudflare account/Pages/Workers tokens and `VERCEL_TOKEN` are operator-owned, gitignored.
- Release is **gated on QC green** (`/appbox:review`) + manifest hash match. Don't ship a drifted target.
- Version: the pipeline stamps `0.1.0+1` in the generated pubspec; the operator bumps per release.
- Every deploy attempt — shipped or halted — is recorded in the deploy ledger
  (`pipeline/state/deploy-ledger.json`, overridable via `APPBOX_DEPLOY_LEDGER`):
  target, version, account, approving person, timestamp, resulting artefact id.
- Web deploys close their ledger entry only after the post-deploy live
  verification above — an unverified live URL is an open entry.

## Output
- A shipped build (store track), a shorebird patch version, and/or a web
  deployment URL (Pages, Workers or Vercel). Deploy is the only outward-facing pipeline action — **confirm
  with the operator before pushing.**

## Run
```sh
appbox deploy --self-test   # all shapes, no credentials
appbox deploy doctor        # preflight report (NOT a gate)
```
