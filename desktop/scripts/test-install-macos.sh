#!/bin/sh
# Focused test for install-macos.sh — the macOS installer twin.
#
# Runs entirely against a scratch $HOME and file:// fixtures: no network, no
# publication, nothing touches the operator's real ~/Applications or ~/.arxa.
#
#   sh desktop/scripts/test-install-macos.sh
#
# Rows: syntax, local-file install, tampered-artifact refusal, idempotent
# upgrade, channel preservation, clean uninstall, offline manifest lane.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/install-macos.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/arxa-install-macos-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
export HOME="$TMP/home"
mkdir -p "$HOME"

FAILED=0
ok()  { printf 'PASS  %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; FAILED=1; }
app_dir()  { printf '%s' "$HOME/Applications/Arxa Studio.app"; }
chan_file(){ printf '%s' "$HOME/.config/arxa-studio/channel"; }

# A fake update bundle: a .app with a marker file, tarballed like Tauri's
# `createUpdaterArtifacts` output ("<App>.app.tar.gz").
make_bundle() { # dir marker [out.tar.gz]
  rm -rf "$1"
  mkdir -p "$1/Arxa Studio.app/Contents/MacOS"
  printf '%s' "$2" >"$1/Arxa Studio.app/Contents/MacOS/version"
  (cd "$1" && tar -czf "${3:-$1/bundle.app.tar.gz}" "Arxa Studio.app")
}

v1="$TMP/v1/bundle.app.tar.gz"; v3="$TMP/v3/bundle.app.tar.gz"

# --- 1. syntax ---------------------------------------------------------------
if sh -n "$SCRIPT" 2>/dev/null; then ok "syntax (sh -n)"; else bad "syntax (sh -n)"; fi

# --- 2. local-file override installs per-user --------------------------------
rm -rf "$HOME/Applications" "$HOME/.config"
make_bundle "$TMP/v1" v1file
ARXA_STUDIO_BUNDLE="$v1" sh "$SCRIPT" >/dev/null 2>&1 </dev/null
if [ "$(cat "$(app_dir)/Contents/MacOS/version" 2>/dev/null)" = "v1file" ]; then ok "local-file override installs to ~/Applications"; else bad "local-file override installs to ~/Applications"; fi

# --- 3. tampered artifact is refused -----------------------------------------
rm -rf "$HOME/Applications" "$HOME/.config"
make_bundle "$TMP/v2" v2file
printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "$TMP/v2/bundle.app.tar.gz" >"$TMP/v2/bundle.app.tar.gz.sha256"
if ARXA_STUDIO_BUNDLE="$TMP/v2/bundle.app.tar.gz" sh "$SCRIPT" >/dev/null 2>&1 </dev/null; then rc=0; else rc=1; fi
if [ "$rc" -ne 0 ] && [ ! -d "$(app_dir)" ]; then ok "tampered artifact refused (checksum mismatch, nothing installed)"; else bad "tampered artifact refused (checksum mismatch, nothing installed)"; fi

# --- 4. idempotent upgrade ---------------------------------------------------
ARXA_STUDIO_BUNDLE="$v1" sh "$SCRIPT" >/dev/null 2>&1 </dev/null   # same bundle again → clean reinstall
make_bundle "$TMP/v3" v3file
ARXA_STUDIO_BUNDLE="$v3" sh "$SCRIPT" >/dev/null 2>&1 </dev/null
if [ "$(cat "$(app_dir)/Contents/MacOS/version" 2>/dev/null)" = "v3file" ]; then ok "idempotent upgrade replaces the app cleanly"; else bad "idempotent upgrade replaces the app cleanly"; fi

# --- 5. channel choice is preserved ------------------------------------------
rm -rf "$HOME/Applications" "$HOME/.config"
ARXA_CHANNEL=beta ARXA_STUDIO_BUNDLE="$v1" sh "$SCRIPT" >/dev/null 2>&1 </dev/null
if [ "$(cat "$(chan_file)" 2>/dev/null)" = "beta" ]; then ok "ARXA_CHANNEL=beta remembered in the channel file"; else bad "ARXA_CHANNEL=beta remembered in the channel file"; fi
ARXA_STUDIO_BUNDLE="$v1" sh "$SCRIPT" >"$TMP/out" 2>&1 </dev/null
if grep -q "beta" "$(chan_file)" && grep -qi "remembered channel" "$TMP/out"; then ok "rerun without ARXA_CHANNEL follows the remembered channel"; else bad "rerun without ARXA_CHANNEL follows the remembered channel"; fi
ARXA_CHANNEL=stable ARXA_STUDIO_BUNDLE="$v1" sh "$SCRIPT" >/dev/null 2>&1 </dev/null
if [ "$(cat "$(chan_file)" 2>/dev/null)" = "stable" ]; then ok "explicit ARXA_CHANNEL overrides the remembered one"; else bad "explicit ARXA_CHANNEL overrides the remembered one"; fi

# --- 6. clean uninstall keeps data -------------------------------------------
mkdir -p "$HOME/.arxa/projects/demo"
sh "$SCRIPT" --uninstall >/dev/null 2>&1 </dev/null
if [ ! -d "$(app_dir)" ] && [ ! -f "$(chan_file)" ] && [ -d "$HOME/.arxa/projects/demo" ]; then ok "uninstall removes app + channel file, keeps ~/.arxa"; else bad "uninstall removes app + channel file, keeps ~/.arxa"; fi

# --- 7. offline manifest lane (file:// base — no network) --------------------
ARCH=$(uname -m | sed 's/arm64/aarch64/')
FEED="$TMP/feed"; mkdir -p "$FEED/desktop/beta/darwin/$ARCH"
make_bundle "$TMP/v4" v4file "$FEED/bundle.app.tar.gz"
( cd "$FEED" && shasum -a 256 bundle.app.tar.gz >bundle.app.tar.gz.sha256 )
cat >"$FEED/desktop/beta/darwin/$ARCH/latest.json" <<EOF
{ "version": "0.9.9",
  "notes": "fixture",
  "pub_date": "2026-09-14T00:00:00Z",
  "platforms": { "darwin-$ARCH":
    { "signature": "fixture", "url": "file://$FEED/bundle.app.tar.gz" } } }
EOF
ARXA_MANIFEST_BASE="file://$FEED" ARXA_CHANNEL=beta sh "$SCRIPT" >"$TMP/out" 2>&1 </dev/null
if [ "$(cat "$(app_dir)/Contents/MacOS/version" 2>/dev/null)" = "v4file" ] && [ "$(cat "$(chan_file)" 2>/dev/null)" = "beta" ]; then ok "manifest lane: fetch → checksum verify → install (file:// base)"; else bad "manifest lane: fetch → checksum verify → install (file:// base)"; fi
if grep -qi "checksum" "$TMP/out"; then ok "checksum verification reported"; else bad "checksum verification reported"; fi

# --- verdict -----------------------------------------------------------------
if [ "$FAILED" -eq 0 ]; then echo "install-macos.sh: ALL GREEN"; exit 0; fi
echo "install-macos.sh: FAILURES PRESENT"; exit 1
