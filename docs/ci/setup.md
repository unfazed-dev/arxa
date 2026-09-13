# CI/CD setup — runner recipe + solo dev loop

> Companion to `docs/ci/decisions.md` (the record). This file is the how-to:
> what runs where, how to run it locally, and what a human must do once.

## The one-root check

```sh
scripts/check.sh            # everything (what CI runs, per area)
scripts/check.sh mobile     # one area: commits pr-title gates mobile
                            #              mobile-signing transport
```

Local green = CI green — CI jobs run the same script verbatim. Flutter is
resolved through fvm when installed (pin: `mobile_flutter/.fvmrc`, 3.44.9);
CI installs Flutter directly at that pin.

## Runners

- **Hosted Ubuntu lanes** (`commits`, `pr-title`, `gates`, `mobile`,
  `mobile-signing`, `transport` in `ci.yml`; `android-release` in
  `mobile-release.yml`): nothing to set up — GitHub-hosted. Recorded
  exception to the all-self-hosted rule; see decisions.md #5.
- **Self-hosted macOS/ARM64 lanes** (`ios-release`): served by the EXISTING
  runner registered for the desktop jobs — labels
  `[self-hosted, macOS, ARM64, arxa]` (see `docs/ci/self-hosted-runners.md`
  for the registration recipe and the label contract). If the runner is
  asleep, iOS jobs queue — a queued job is a runner problem, never a code
  problem.

## Branch protection (after the first green run is watched)

```sh
gh api repos/<owner>/<repo>/branches/main/protection --method PUT \
  -H "Accept: application/vnd.github+json" --input - <<'JSON'
{
  "required_status_checks": { "strict": true,
    "contexts": ["commits", "pr-title", "gates", "mobile", "mobile-signing", "transport"] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

Rename a job ⇒ delete the stale context from `contexts` and re-run the PUT.

## Secrets for the mobile release lane

All live in the `mobile-release` GitHub environment (custody, not bare repo
secrets — same pattern as the desktop `release` environment). None are ever
printed by CI or committed; presence is reported, values are not.

| Secret | Feeds |
|--------|-------|
| `ANDROID_KEYSTORE_BASE64` | `android/key.properties` (storeFile) |
| `ANDROID_KEYSTORE_PASSWORD` | key.properties |
| `ANDROID_KEY_ALIAS` | key.properties |
| `ANDROID_KEY_PASSWORD` | key.properties |
| `MATCH_GIT_URL` | fastlane match storage (iOS distribution signing) |
| `APP_STORE_CONNECT_API_KEY_KEY_ID` / `_ISSUER_ID` / `_CONTENT` | TestFlight/App Store upload |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play upload (operator-run lanes) |

Local Android release build: create `mobile_flutter/android/key.properties`
(gitignored) with `storeFile/storePassword/keyAlias/keyPassword`. Absent
inputs ⇒ the release packaging task fails with a clear GradleException;
debug builds alone may use the debug key.

## Release lane operation (the halt)

`mobile-release.yml` (tag `mobile-v*` or manual dispatch) builds a
release-shaped AAB (real keystore when secrets exist; a disposable test-only
keystore otherwise — created and destroyed inside the job, artifact stamped
`TEST-SIGNED`), validates the iOS archive unsigned, and HALTS. Shipping is a
human act (HUMAN GATE 3):

```sh
cd mobile_flutter
fastlane android doctor && fastlane android beta        # Play internal
fastlane ios doctor                                     # identity report
# after the human deploy gate approval:
fastlane ios beta                                       # TestFlight
```

OTA: `shorebird.yaml` is a dormant extension point — activation steps in
that file.

## First-green checklist (Part B)

1. `actionlint .github/workflows/*.yml`
2. `sh -n scripts/check.sh` (syntax), then each area for real
3. Watch the first `ci.yml` run go green (`gh run watch`) BEFORE applying
   branch protection
4. Exercise the release lane without publishing (brief Step 8)
