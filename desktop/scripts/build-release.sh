#!/usr/bin/env bash
# Local release build with updater-artifact signing.
# CI (.github/workflows/desktop-release.yml) exports these from repo secrets instead;
# this wrapper is the local/manual equivalent so `createUpdaterArtifacts` never
# emits the "public key found, but no private key" warning on dev machines.
set -euo pipefail

KEY_FILE="${TAURI_SIGNING_PRIVATE_KEY_FILE:-$HOME/.arxa/updater/arxa-updater.key}"

if [ -z "${TAURI_SIGNING_PRIVATE_KEY:-}" ]; then
  if [ -f "$KEY_FILE" ]; then
    TAURI_SIGNING_PRIVATE_KEY="$(cat "$KEY_FILE")"
    export TAURI_SIGNING_PRIVATE_KEY
    # Key is passwordless by default; override via env if yours is not.
    export TAURI_SIGNING_PRIVATE_KEY_PASSWORD="${TAURI_SIGNING_PRIVATE_KEY_PASSWORD-}"
  else
    echo "warning: no updater signing key at $KEY_FILE — updater artifacts will be unsigned" >&2
  fi
fi

cd "$(dirname "$0")/../src-tauri"
exec npx --yes @tauri-apps/cli@2 build "$@"
