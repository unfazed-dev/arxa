#!/bin/sh
# Arxa Studio — macOS installer (twin of install.sh, the Linux one).
#
#   curl -fsSL https://raw.githubusercontent.com/unfazed-dev/arxa-releases/main/install-macos.sh | sh
#
# Source of truth: arxa/desktop/scripts/install-macos.sh. The release workflow
# copies it to the root of the public arxa-releases repo beside the updater
# manifests.
#
# What it does (per-user, no root, no sudo):
#   1. reads desktop/<channel>/darwin/<arch>/latest.json — the same manifest
#      the in-app updater reads — and downloads the .app.tar.gz update bundle
#   2. verifies the published .sha256 (and the minisign .sig when `minisign`
#      is installed — the same keypair the in-app updater verifies with)
#   3. installs to ~/Applications/Arxa Studio.app
#   4. remembers the channel in ~/.config/arxa-studio/channel, so reruns
#      (upgrades) follow the feed you first chose
#
# Knobs:  ARXA_CHANNEL=beta            beta feed instead of stable (sticky)
#         ARXA_STUDIO_BUNDLE=<file|url>  install this bundle, skip the manifest
#         ARXA_MANIFEST_BASE=<url>     manifest base for tests (file:// works)
#         sh install-macos.sh --uninstall  remove the app; your data in
#                                       ~/.arxa is left alone
set -eu

REPO_RAW=https://raw.githubusercontent.com/unfazed-dev/arxa-releases/main
MANIFEST_BASE=${ARXA_MANIFEST_BASE:-$REPO_RAW}
APP="$HOME/Applications/Arxa Studio.app"
CONF_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/arxa-studio
CHANNEL_FILE=$CONF_DIR/channel
# The updater public key (tauri.conf.json > plugins.updater.pubkey) — pinned
# here so the installer can verify the .sig itself when minisign is available.
UPDATER_PUBKEY='dW50cnVzdGVkIGNvbW1lbnQ6IG1pbmlzaWduIHB1YmxpYyBrZXk6IDNGODRCMjg2NDZBQjQxMjQKUldRa1FhdEdocktFUDkyUjJwL1pPQ3hRdUVaWEFYYzl1TzR3YU05VVNTQXZTUGs1bDRRKzk5RWUK'

say() { printf '%s\n' "$*"; }
die() { printf 'install-macos.sh: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # url dest
  if have curl; then curl -fsSL --retry 3 -o "$2" "$1"
  elif have wget; then wget -qO "$2" "$1"
  else die "need curl or wget"; fi
}

sha256() { # file
  if have shasum; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$APP" "$CHANNEL_FILE"
  say "Arxa Studio removed. Your data in ~/.arxa was left in place."
  exit 0
fi

case "$(uname -s)" in Darwin) ;; *) die "this installer is for macOS; Linux has install.sh, Windows is not supported" ;; esac
case "$(uname -m)" in
  arm64) ARCH=aarch64 ;;
  x86_64) ARCH=x86_64 ;;
  *) die "unsupported CPU: $(uname -m)" ;;
esac

# --- 1. channel (sticky across upgrades) ------------------------------------
if [ -n "${ARXA_CHANNEL:-}" ]; then
  CHANNEL=$ARXA_CHANNEL
elif [ -f "$CHANNEL_FILE" ]; then
  CHANNEL=$(cat "$CHANNEL_FILE")
  say "Using remembered channel: $CHANNEL"
else
  CHANNEL=stable
fi
case "$CHANNEL" in stable|beta) ;; *) die "channel must be stable or beta, got: $CHANNEL" ;; esac

# --- 2. pick the bundle ------------------------------------------------------
TMP=$(mktemp -d "${TMPDIR:-/tmp}/arxa-install-macos.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

URL='' VERSION=''
if [ -n "${ARXA_STUDIO_BUNDLE:-}" ]; then
  case "$ARXA_STUDIO_BUNDLE" in
    http://*|https://*|file://*) URL=$ARXA_STUDIO_BUNDLE ;;
    *) [ -f "$ARXA_STUDIO_BUNDLE" ] || die "no such file: $ARXA_STUDIO_BUNDLE"
       cp "$ARXA_STUDIO_BUNDLE" "$TMP/bundle.app.tar.gz" ;;
  esac
else
  MANIFEST=$MANIFEST_BASE/desktop/$CHANNEL/darwin/$ARCH/latest.json
  fetch "$MANIFEST" "$TMP/latest.json" \
    || die "no $CHANNEL macOS release for $ARCH yet ($MANIFEST). Try ARXA_CHANNEL=beta."
  URL=$(sed -n 's/.*"url": *"\([^"]*\)".*/\1/p' "$TMP/latest.json" | head -1)
  VERSION=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$TMP/latest.json" | head -1)
  [ -n "$URL" ] || die "manifest has no url: $MANIFEST"
fi

if [ -n "$URL" ]; then
  say "Downloading Arxa Studio ${VERSION:-} ($ARCH, $CHANNEL)..."
  fetch "$URL" "$TMP/bundle.app.tar.gz" || die "download failed: $URL"
fi

# --- 3. verify (checksum always; minisign signature when available) ----------
if [ -n "${ARXA_STUDIO_BUNDLE:-}" ] && [ -z "$URL" ]; then
  # local file: honour a checksum sitting next to it, if any
  if [ -f "$ARXA_STUDIO_BUNDLE.sha256" ]; then
    WANT=$(cut -d' ' -f1 "$ARXA_STUDIO_BUNDLE.sha256")
    GOT=$(sha256 "$TMP/bundle.app.tar.gz")
    [ "$WANT" = "$GOT" ] || die "checksum mismatch for $ARXA_STUDIO_BUNDLE"
    say "Checksum OK."
  else
    say "No .sha256 next to that bundle; skipping verification."
  fi
else
  if fetch "$URL.sha256" "$TMP/sum"; then
    WANT=$(cut -d' ' -f1 "$TMP/sum")
    GOT=$(sha256 "$TMP/bundle.app.tar.gz")
    [ "$WANT" = "$GOT" ] || { say "checksum mismatch for $URL"; die "tampered download — refusing to install"; }
    say "Checksum OK."
  else
    die "no checksum published at $URL.sha256"
  fi
fi
if [ -n "$URL" ] && fetch "$URL.sig" "$TMP/bundle.sig" 2>/dev/null && [ -s "$TMP/bundle.sig" ]; then
  if have minisign; then
    PUB=$(printf '%s' "$UPDATER_PUBKEY" | base64 -d | sed -n '2p')
    if minisign -V -q -P "$PUB" -m "$TMP/bundle.app.tar.gz" -x "$TMP/bundle.sig"; then
      say "Updater signature verified (minisign)."
    else
      die "updater signature FAILED to verify for $URL"
    fi
  else
    say "minisign not installed — .sig downloaded but not verified (brew install minisign)."
  fi
fi

# --- 4. install per-user ------------------------------------------------------
mkdir -p "$HOME/Applications" "$CONF_DIR"
rm -rf "$APP"
tar -xzf "$TMP/bundle.app.tar.gz" -C "$HOME/Applications"
[ -d "$APP" ] || die "bundle did not contain 'Arxa Studio.app'"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
printf '%s' "$CHANNEL" >"$CHANNEL_FILE"

say ""
say "Installed Arxa Studio ${VERSION:-} to $APP"
say "Launch it from ~/Applications (or Spotlight)."
[ "$CHANNEL" = "beta" ] && say "Beta channel: in-app updates follow it when launched with ARXA_UPDATE_CHANNEL=$CHANNEL."
say "Uninstall: sh install-macos.sh --uninstall"
