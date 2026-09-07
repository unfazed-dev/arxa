#!/bin/sh
# Arxa Studio — Linux installer.
#
#   curl -fsSL https://raw.githubusercontent.com/unfazed-dev/arxa-releases/main/install.sh | sh
#
# Source of truth: arxa/desktop/scripts/install.sh. The release workflow copies
# it to the root of the public arxa-releases repo beside the updater manifests.
#
# What it does (per-user, no root except for the distro packages):
#   1. installs the host packages the AppImage cannot bundle
#      (libfuse2 to mount it; zenity, gnome-keyring + secret-tool, bubblewrap
#      which the engine shells out to)
#   2. reads desktop/<channel>/linux/<arch>/latest.json — the same manifest the
#      in-app updater reads — and downloads that AppImage
#   3. verifies the published .sha256
#   4. installs to ~/.local/share/arxa-studio/arxa-studio.AppImage, links
#      ~/.local/bin/arxa-studio, writes a .desktop entry + icon
#
# Knobs:  ARXA_CHANNEL=beta            beta feed instead of stable
#         ARXA_STUDIO_APPIMAGE=<file|url>  install this image, skip the manifest
#         ARXA_SKIP_DEPS=1              do not touch system packages
#         sh install.sh --uninstall     remove what this script installed
#                                       (~/.arxa, your data, is left alone)
set -eu

REPO_RAW=https://raw.githubusercontent.com/unfazed-dev/arxa-releases/main
CHANNEL=${ARXA_CHANNEL:-stable}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
APP_DIR=$DATA_HOME/arxa-studio
APPIMAGE=$APP_DIR/arxa-studio.AppImage
BIN_DIR=$HOME/.local/bin
DESKTOP=$DATA_HOME/applications/arxa-studio.desktop
ICON=$DATA_HOME/icons/hicolor/128x128/apps/arxa-studio.png

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # url dest
  if have curl; then curl -fsSL --retry 3 -o "$2" "$1"
  elif have wget; then wget -qO "$2" "$1"
  else die "need curl or wget"; fi
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$APP_DIR"
  rm -f "$BIN_DIR/arxa-studio" "$DESKTOP" "$ICON"
  update-desktop-database "$DATA_HOME/applications" 2>/dev/null || true
  say "Arxa Studio removed. Your data in ~/.arxa was left in place."
  exit 0
fi

case "$(uname -s)" in Linux) ;; *) die "this installer is for Linux; macOS builds are on the GitHub Release page" ;; esac
case "$(uname -m)" in
  x86_64|amd64) ARCH=x86_64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  *) die "unsupported CPU: $(uname -m)" ;;
esac

# --- 1. host packages ------------------------------------------------------
if [ -z "${ARXA_SKIP_DEPS:-}" ]; then
  ID= ID_LIKE=
  [ -r /etc/os-release ] && . /etc/os-release
  SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
  PKGS= INSTALL= PRE=
  case " ${ID:-} ${ID_LIKE:-} " in
    *arch*|*manjaro*)
      PKGS="fuse2 zenity gnome-keyring libsecret bubblewrap"
      INSTALL="pacman -S --needed --noconfirm" ;;
    *debian*|*ubuntu*)
      FUSE=libfuse2; apt-cache show libfuse2t64 >/dev/null 2>&1 && FUSE=libfuse2t64
      PKGS="$FUSE zenity gnome-keyring libsecret-tools bubblewrap"
      PRE="apt-get update -qq"; INSTALL="apt-get install -y" ;;
    *fedora*|*rhel*)
      PKGS="fuse-libs zenity gnome-keyring libsecret bubblewrap"
      INSTALL="dnf install -y" ;;
    *suse*)
      PKGS="libfuse2 zenity gnome-keyring libsecret-tools bubblewrap"
      INSTALL="zypper install -y" ;;
    *)
      say "Unknown distro (${ID:-?}). Make sure libfuse2, zenity, gnome-keyring, secret-tool and bubblewrap are installed." ;;
  esac
  if [ -n "$PKGS" ]; then
    if [ -n "$SUDO" ] && ! have sudo; then
      say "No sudo; install these yourself, then rerun with ARXA_SKIP_DEPS=1:  $PKGS"
      exit 1
    fi
    say "Installing host packages: $PKGS"
    # shellcheck disable=SC2086
    [ -z "$PRE" ] || $SUDO $PRE
    # shellcheck disable=SC2086
    $SUDO $INSTALL $PKGS || die "package install failed. On Arch, run 'sudo pacman -Syu' first and retry."
  fi
fi

# --- 2. pick the image ----------------------------------------------------
TMP=$(mktemp -d "${TMPDIR:-/tmp}/arxa-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$APP_DIR" "$BIN_DIR" "$(dirname "$DESKTOP")" "$(dirname "$ICON")"

URL= VERSION=
if [ -n "${ARXA_STUDIO_APPIMAGE:-}" ]; then
  case "$ARXA_STUDIO_APPIMAGE" in
    http://*|https://*) URL=$ARXA_STUDIO_APPIMAGE ;;
    *) [ -f "$ARXA_STUDIO_APPIMAGE" ] || die "no such file: $ARXA_STUDIO_APPIMAGE"
       cp "$ARXA_STUDIO_APPIMAGE" "$APPIMAGE.part" ;;
  esac
else
  MANIFEST=$REPO_RAW/desktop/$CHANNEL/linux/$ARCH/latest.json
  fetch "$MANIFEST" "$TMP/latest.json" \
    || die "no $CHANNEL Linux release for $ARCH yet ($MANIFEST). Try ARXA_CHANNEL=beta."
  URL=$(sed -n 's/.*"url": *"\([^"]*\)".*/\1/p' "$TMP/latest.json" | head -1)
  VERSION=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$TMP/latest.json" | head -1)
  [ -n "$URL" ] || die "manifest has no url: $MANIFEST"
fi

if [ -n "$URL" ]; then
  say "Downloading Arxa Studio ${VERSION:-} ($ARCH, $CHANNEL)..."
  fetch "$URL" "$APPIMAGE.part" || die "download failed: $URL"
  # --- 3. checksum --------------------------------------------------------
  if fetch "$URL.sha256" "$TMP/sum"; then
    WANT=$(cut -d' ' -f1 "$TMP/sum")
    GOT=$(sha256sum "$APPIMAGE.part" | cut -d' ' -f1)
    [ "$WANT" = "$GOT" ] || { rm -f "$APPIMAGE.part"; die "checksum mismatch for $URL"; }
    say "Checksum OK."
  elif [ -n "${ARXA_STUDIO_APPIMAGE:-}" ]; then
    say "No .sha256 next to that URL; skipping verification."
  else
    rm -f "$APPIMAGE.part"; die "no checksum published at $URL.sha256"
  fi
fi

# --- 4. install ------------------------------------------------------------
chmod +x "$APPIMAGE.part"
mv -f "$APPIMAGE.part" "$APPIMAGE"
ln -sf "$APPIMAGE" "$BIN_DIR/arxa-studio"

# the icon lives inside the image; extraction needs no FUSE
ICON_IN=usr/share/icons/hicolor/128x128/apps/arxa-desktop.png
if (cd "$TMP" && "$APPIMAGE" --appimage-extract "$ICON_IN" >/dev/null 2>&1) && [ -f "$TMP/squashfs-root/$ICON_IN" ]; then
  cp "$TMP/squashfs-root/$ICON_IN" "$ICON"
else
  say "Could not extract the icon; the launcher entry will use a generic one."
fi

cat >"$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Arxa Studio
Comment=Arxa Studio desktop
Exec="$APPIMAGE" %U
Icon=$ICON
Terminal=false
Categories=Development;
StartupWMClass=arxa-desktop
EOF
update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null || true

say ""
say "Installed Arxa Studio ${VERSION:-} to $APPIMAGE"
say "Launch it from your app menu, or run: arxa-studio"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "(add $BIN_DIR to your PATH for the command to work)" ;;
esac
say "Blank window on Wayland with an NVIDIA GPU? Run: WEBKIT_DISABLE_DMABUF_RENDERER=1 arxa-studio"
say "Uninstall: sh install.sh --uninstall"
