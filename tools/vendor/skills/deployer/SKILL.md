---
name: deployer
description: Use when shipping a crew-built Flutter target to stores (fastlane: TestFlight/App Store + Play internal/production) and/or pushing an OTA Dart patch (shorebird). Trigger on "deploy", "ship to TestFlight", "release to Play", "push an OTA patch", "hotfix".
---

# deployer — stores (fastlane) + OTA patches (shorebird)

## Core principle
fastlane + shorebird are existing CLIs; this role drives them with a recipe. The
Fastfile + `shorebird.yaml` are **operator-owned extension points** — signing,
bundle id, and app ids are project secrets the factory never holds.

## Stores — fastlane (gym + match + deliver/supply)
1. **Once per project** — `fastlane init` in `<target>/ios` + `<target>/android`.
   Operator fills signing (`match`), bundle id, team. The Fastfile is an
   extension point, NOT factory-generated.
2. **Beta lane** — `fastlane beta`:
   - iOS: `gym` (build) → `match` (signing) → `upload_to_testflight`.
   - Android: `flutter build appbundle` → `upload_to_play_store(track: internal)`.
3. **Release lane** — `fastlane release`: store metadata (`deliver`/`supply`) +
   production track.

## OTA — shorebird (Dart hotpatch, no store review)
1. **Once** — `shorebird init` in target → `shorebird.yaml` (extension point; operator app id).
2. **Patch** — `shorebird release patch` after a Dart-only fix. Catches the 80% case (logic bug) without a store round-trip.
3. **Boundary** — shorebird patches Dart ONLY (their TOS: bug fixes, not new features / store-banned changes). Native changes → fastlane full release.

## Rules
- Never commit secrets — `.env` (Supabase), signing (`match` storage), store keys are operator-owned, gitignored.
- Release is **gated on QC green** (`/flutter-crew:review`) + manifest hash match. Don't ship a drifted target.
- Version: factory stamps `0.1.0+1` in the generated pubspec; operator bumps per release.

## Output
- A shipped build (store track) and/or a shorebird patch version. Deploy is the
  only outward-facing factory action — **confirm with the operator before pushing.**
