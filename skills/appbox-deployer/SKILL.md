---
name: appbox-deployer
description: Use when shipping an appbox-built target to stores (fastlane: TestFlight/App Store + Play internal/production), pushing an OTA Dart patch (shorebird), or deploying a web build to Cloudflare Pages/Workers or Vercel. Trigger on "deploy", "ship to TestFlight", "release to Play", "push an OTA patch", "hotfix", "deploy to Cloudflare Pages", "deploy to Vercel".
---

# deployer — stores (fastlane) + OTA patches (shorebird) + web (Cloudflare Pages/Workers, Vercel)

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

`doctor(config)` is **preflight, not the gate** — it reports readiness; the gate
still has to assert a value.

## Rules
- Never commit secrets — `.env` (Supabase), signing (`match` storage), store keys, the Cloudflare account/Pages/Workers tokens and `VERCEL_TOKEN` are operator-owned, gitignored.
- Release is **gated on QC green** (`/appbox:review`) + manifest hash match. Don't ship a drifted target.
- Version: the pipeline stamps `0.1.0+1` in the generated pubspec; the operator bumps per release.
- Every deploy attempt — shipped or halted — is recorded in the deploy ledger
  (`pipeline/state/deploy-ledger.json`, overridable via `APPBOX_DEPLOY_LEDGER`):
  target, version, account, approving person, timestamp, resulting artefact id.

## Output
- A shipped build (store track), a shorebird patch version, and/or a web
  deployment URL (Pages, Workers or Vercel). Deploy is the only outward-facing pipeline action — **confirm
  with the operator before pushing.**

## Run
```sh
appbox deploy --self-test   # all shapes, no credentials
appbox deploy doctor        # preflight report (NOT a gate)
```
