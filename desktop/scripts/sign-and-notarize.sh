#!/bin/bash
# sign-and-notarize.sh — sign, notarize, and staple an Arxa Studio build.
#
# Usage:
#   ./sign-and-notarize.sh "/path/to/Arxa Studio.app"        # or a .dmg
#   ./sign-and-notarize.sh --sign-only "/path/to/App.app"    # skip notarization
#
# Env overrides:
#   SIGN_IDENTITY   codesign identity (default: the Developer ID below)
#   ENTITLEMENTS    entitlements plist for JIT sidecars (default: desktop/entitlements.plist)
#   NOTARY_PROFILE  notarytool keychain profile name (default: arxa-notary)
#   APPLE_ID / APPLE_PASSWORD / APPLE_TEAM_ID  — used if NOTARY_PROFILE absent
#
# Idempotent: re-signing with --force is safe to repeat.

set -euo pipefail

DEFAULT_IDENTITY="Developer ID Application: EVAN F PIERRE LOUIS (43GNRCGQXQ)"
SIGN_IDENTITY="${SIGN_IDENTITY:-$DEFAULT_IDENTITY}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="${ENTITLEMENTS:-$SCRIPT_DIR/../entitlements.plist}"
NOTARY_PROFILE="${NOTARY_PROFILE:-arxa-notary}"

SIGN_ONLY=0
if [[ "${1:-}" == "--sign-only" ]]; then SIGN_ONLY=1; shift; fi
TARGET="${1:-}"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

[[ -n "$TARGET" ]] || die "usage: $0 [--sign-only] /path/to/App.app|Installer.dmg"
[[ -e "$TARGET" ]] || die "target not found: $TARGET"
[[ -f "$ENTITLEMENTS" ]] || die "entitlements not found: $ENTITLEMENTS"
security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY" \
  || die "identity not in keychain: $SIGN_IDENTITY"

sign_app() {
  local app="$1"
  local main_exe
  main_exe="$(defaults read "$app/Contents/Info" CFBundleExecutable)"

  info "Signing nested Mach-O binaries (inside-out)"
  # Frameworks / dylibs / helpers first, then loose executables in MacOS/.
  while IFS= read -r -d '' bin; do
    [[ "$(basename "$bin")" == "$main_exe" ]] && continue
    if file -b "$bin" | grep -q 'Mach-O'; then
      info "  sidecar: $bin (with JIT entitlements)"
      codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" "$bin"
    else
      # Script sidecars in Contents/MacOS are nested code: the bundle
      # signature fails ("code object is not signed at all") unless they are
      # signed too. Scripts get a plain signature (no runtime/entitlements).
      info "  sidecar script: $bin"
      codesign --force --timestamp --sign "$SIGN_IDENTITY" "$bin"
    fi
  done < <(find "$app/Contents/MacOS" "$app/Contents/Frameworks" \
             -type f -perm +111 -print0 2>/dev/null)

  info "Signing app bundle: $app"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$app"

  info "Verifying signature"
  codesign --verify --deep --strict --verbose=2 "$app"
}

notary_args() {
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "--keychain-profile $NOTARY_PROFILE"
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    echo "--apple-id $APPLE_ID --password $APPLE_PASSWORD --team-id $APPLE_TEAM_ID"
  else
    return 1
  fi
}

notarize() {
  local target="$1" args submit_path cleanup=""
  if ! args="$(notary_args)"; then
    die "no notarization credentials.
  Provide ONE of:
    1) keychain profile:  xcrun notarytool store-credentials $NOTARY_PROFILE \\
         --apple-id <you@apple-id> --team-id 43GNRCGQXQ --password <app-specific-password>
       (app-specific password: https://support.apple.com/en-ca/HT204397)
    2) env vars: APPLE_ID, APPLE_PASSWORD (app-specific), APPLE_TEAM_ID=43GNRCGQXQ
  Or run with --sign-only to stop after signing."
  fi

  if [[ "$target" == *.app ]]; then
    submit_path="$(mktemp -d)/$(basename "$target").zip"
    cleanup="$(dirname "$submit_path")"
    info "Zipping for submission: $submit_path"
    ditto -c -k --keepParent "$target" "$submit_path"
  else
    submit_path="$target"
  fi

  info "Submitting to notarytool (waits for verdict)"
  # shellcheck disable=SC2086
  xcrun notarytool submit "$submit_path" $args --wait \
    || die "notarization failed — inspect with: xcrun notarytool log <submission-id> $args"
  [[ -n "$cleanup" ]] && rm -rf "$cleanup"

  info "Stapling ticket to $target"
  xcrun stapler staple "$target"
}

case "$TARGET" in
  *.app) sign_app "$TARGET" ;;
  *.dmg)
    info "Signing dmg: $TARGET"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$TARGET"
    ;;
  *) die "target must be a .app or .dmg" ;;
esac

if [[ "$SIGN_ONLY" -eq 1 ]]; then
  info "Sign-only mode: skipping notarization."
else
  notarize "$TARGET"
  info "Gatekeeper assessment"
  spctl -a -vv --type exec "$TARGET" || die "spctl rejected $TARGET"
fi

info "Done: $TARGET"
