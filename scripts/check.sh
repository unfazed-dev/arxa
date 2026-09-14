#!/bin/sh
# arxa monorepo — the one-root check (skills/arxa-cicd check contract).
#
# Local green = CI green: .github/workflows/ci.yml runs this script verbatim,
# one job per area; no validator lives anywhere else. `arxa gate --all` is
# WRAPPED here, never duplicated (the script adds only what no gate owns:
# commit subjects, PR title tags, the Flutter format/analyze/test loop and
# the mobile signing contract).
#
#   scripts/check.sh            # every area
#   scripts/check.sh <area>     # one: commits pr-title gates mobile
#                               #      mobile-signing transport
#
# Green by absence: an area whose code is not present skips (exit 0), so the
# frame was green on day zero and stays green on stripped-down checkouts.
set -u
cd "$(dirname "$0")/.."

# Toolchain resolution: the repo pins Flutter via mobile_flutter/.fvmrc
# (3.44.9). Prefer fvm when installed; CI installs Flutter directly at the
# same pin, so `flutter` there is already correct.
if command -v fvm >/dev/null 2>&1; then
  FLUTTER="fvm flutter"
else
  FLUTTER="flutter"
fi

fail() {
  echo "FAIL [$1] $2" >&2
  exit 1
}

skip() {
  echo "skip [$1] $2"
}

# ---------------------------------------------------------------------------
area_commits() {
  # Conventional-commit subjects over the PR range (or the pushed head).
  # Merge commits are excluded: GitHub PR events test an auto-generated
  # "Merge X into Y" commit whose mechanical subject false-positives a naive
  # prefix check (measured live, energize PR #1 2026-08-16).
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    range="origin/${GITHUB_BASE_REF}..HEAD"
  else
    range="-1 HEAD"
  fi
  git log --no-merges --format='%s' $range | while IFS= read -r subject; do
    case "$subject" in
      feat:*|feat\(*:*|fix:*|fix\(*:*|docs:*|docs\(*:*|style:*|style\(*:*|\
      refactor:*|refactor\(*:*|perf:*|perf\(*:*|test:*|test\(*:*|\
      build:*|build\(*:*|ci:*|ci\(*:*|chore:*|chore\(*:*|revert:*|revert\(*:*) ;;
      *)
        echo "bad subject: $subject" >&2
        echo "  expected: type[(scope)]: description  (feat/fix/docs/style/" >&2
        echo "             refactor/perf/test/build/ci/chore/revert)" >&2
        exit 1
        ;;
    esac
  done || exit 1
  echo "ok [commits] subjects conventional"
}

area_pr_title() {
  # PR title carries the pipeline stage: [arxa-<skill-name>] prefix, first
  # tag = primary stage. WARN-NOT-FAIL for now — the flip to strict is a
  # recorded decision in docs/ci/decisions.md, not a silent change.
  title="${PR_TITLE:-}"
  if [ -z "$title" ]; then
    skip pr-title "no PR title in context (push event or local run)"
    return 0
  fi
  case "$title" in
    \[arxa-*:*\]*|\[arxa-*\]*) ;;
    *)
      echo "warn [pr-title] title lacks the [arxa-<skill-name>] stage prefix: $title"
      echo "  expected: [arxa-<skill-name>] <subject> — tags: arxa-orchestrator,"
      echo "  arxa-intake, arxa-story-mapper, arxa-moodboarder, arxa-designer,"
      echo "  arxa-scaffolder, arxa-builder, arxa-tester, arxa-reviewer,"
      echo "  arxa-deployer, arxa-lens, arxa-lint, arxa-cicd"
      ;;
  esac
  echo "ok [pr-title] checked (warn mode)"
}

area_gates() {
  # The pipeline's own gates — this area only wraps them.
  if [ ! -f arxa/pubspec.yaml ]; then
    skip gates "no arxa/ package"
    return 0
  fi
  # Gate exit contract: 0 pass / 1 FAIL / 2 env or not-applicable.
  (cd arxa && dart run bin/arxa.dart gate --all)
  code=$?
  case $code in
    0) echo "ok [gates] arxa gate --all pass" ;;
    2) skip gates "arxa gate --all returned 2 (env / not applicable)" ;;
    *) fail gates "arxa gate --all exit $code" ;;
  esac
}

area_mobile() {
  if [ ! -f mobile_flutter/pubspec.yaml ]; then
    skip mobile "no mobile_flutter/"
    return 0
  fi
  (
    cd mobile_flutter || exit 1
    # .fvmrc lives here — run fvm from this directory when present.
    if command -v fvm >/dev/null 2>&1; then
      fvm dart format --output=none --set-exit-if-changed lib test integration_test ||
        exit 1
      fvm flutter analyze || exit 1
      fvm flutter test || exit 1
    else
      dart format --output=none --set-exit-if-changed lib test integration_test ||
        exit 1
      flutter analyze || exit 1
      flutter test || exit 1
    fi
  ) || fail mobile "format/analyze/test"
  echo "ok [mobile] format + analyze + test"
}

area_mobile_signing() {
  # The Android release-signing contract (migration-spec box 11, Task 12
  # Step 4). Mirrors test/android_release_signing_contract_test.dart — keep
  # the two in sync; this shell copy exists so CI can assert it on machines
  # with no Flutter toolchain.
  [ -f mobile_flutter/android/app/build.gradle.kts ] ||
    { skip mobile-signing "no android app gradle"; return 0; }
  grep -q 'applicationId = "solutions.arxadigital.arxa.mobile"' \
    mobile_flutter/android/app/build.gradle.kts ||
    fail mobile-signing "applicationId is not solutions.arxadigital.arxa.mobile"
  grep -q 'rootProject.file("key.properties")' \
    mobile_flutter/android/app/build.gradle.kts ||
    fail mobile-signing "release signing does not read android/key.properties"
  grep -q 'key.properties' mobile_flutter/android/.gitignore ||
    fail mobile-signing "android/.gitignore does not ignore key.properties"
  grep -q 'if (releaseSigningReady)' \
    mobile_flutter/android/app/build.gradle.kts ||
    fail mobile-signing "release signingConfig is not guarded by releaseSigningReady"
  if grep -q 'getByName("debug")' mobile_flutter/android/app/build.gradle.kts; then
    fail mobile-signing "release path may silently sign with the debug key"
  fi
  # iOS identity contract: team + bundle id stay what parity was proven with.
  grep -q 'DEVELOPMENT_TEAM = 43GNRCGQXQ' \
    mobile_flutter/ios/Runner.xcodeproj/project.pbxproj ||
    fail mobile-signing "iOS DEVELOPMENT_TEAM is not 43GNRCGQXQ"
  grep -q 'PRODUCT_BUNDLE_IDENTIFIER = solutions.arxadigital.arxa.mobile;' \
    mobile_flutter/ios/Runner.xcodeproj/project.pbxproj ||
    fail mobile-signing "iOS bundle id is not solutions.arxadigital.arxa.mobile"
  echo "ok [mobile-signing] ids + gitignored signing inputs + no debug-key release"
}

area_transport() {
  if [ ! -f kit/studio_transport/pubspec.yaml ]; then
    skip transport "no kit/studio_transport/"
    return 0
  fi
  (
    cd kit/studio_transport || exit 1
    if command -v fvm >/dev/null 2>&1; then
      fvm flutter test || exit 1
    else
      flutter test || exit 1
    fi
  ) || fail transport "studio_transport tests"
  echo "ok [transport] kit/studio_transport tests"
  if [ -d kit/studio_transport/rust ]; then
    if command -v cargo >/dev/null 2>&1; then
      (cd kit/studio_transport/rust && cargo test --lib) ||
        fail transport "cargo test --lib"
      echo "ok [transport] rust transport tests"
    else
      skip transport "cargo absent — rust leg skipped locally (CI installs rust)"
    fi
  fi
}

# ---------------------------------------------------------------------------
case "${1:-all}" in
  commits) area_commits ;;
  pr-title) area_pr_title ;;
  gates) area_gates ;;
  mobile) area_mobile ;;
  mobile-signing) area_mobile_signing ;;
  transport) area_transport ;;
  all)
    status=0
    for a in commits pr-title gates mobile mobile-signing transport; do
      # shellcheck disable=SC2086
      scripts/check.sh "$a" || status=1
    done
    [ $status -eq 0 ] && echo "ALL GREEN" || echo "RED" >&2
    exit $status
    ;;
  *)
    echo "usage: scripts/check.sh [commits|pr-title|gates|mobile|mobile-signing|transport|all]" >&2
    exit 2
    ;;
esac
