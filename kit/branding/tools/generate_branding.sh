#!/usr/bin/env bash
#  branding/tools/generate_branding.sh — vendoring codegen for a arxa_kit host app.
#
#  Emits into <host_app>:
#    -  flutter_launcher_icons.yaml   (brand-icons law: assets/brand-icons/ master)
#    -  flutter_native_splash.yaml    (theme-reactive: F5F0E8 light / 1C1814 dark)
#    -  assets/brand-icons/<base>-splash.png            (320px logo raster)
#    -  assets/brand-icons/<base>-splash-android12.png  (334px logo on transparent 960px canvas)
#    -  lib/ui/common/generated/brand_colors.dart       (LEGACY hosts only — kit-native
#       hosts get colors from arxa_kit_core; emitted only when
#       lib/ui/common/app_colors.dart exists to supply kcPrimaryColor)
#
#  Brand-icon resolution (ratified law, 2026-08-09): the app owns its master in
#  assets/brand-icons/. If <host>/assets.manifest.json exists, brandIcon.{master,
#  monochrome,background} are authoritative; otherwise the master is inferred as
#  the single non -monochrome/-splash png in assets/brand-icons/, background
#  defaults to #ffffff.
#
#  After emit, run inside the host:
#    dart run flutter_launcher_icons && dart run flutter_native_splash:create
set -euo pipefail

[[ $# -ge 1 ]] || { echo "usage: generate_branding.sh <host_app_dir>" >&2; exit 1; }
HOST="$(cd "$1" && pwd)"
BRANDING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$BRANDING_DIR/templates"

BRAND_DIR="$HOST/assets/brand-icons"
[[ -d "$BRAND_DIR" ]] || { echo "FAIL: brand-icons dir not found: $BRAND_DIR (law: every app owns assets/brand-icons/)" >&2; exit 1; }

# --- Resolve master / monochrome / background (manifest wins, else infer) ----
eval "$(python3 - "$HOST" <<'PY'
import json, os, sys
host = sys.argv[1]
master = mono = ""
bg = "#ffffff"
mpath = os.path.join(host, "assets.manifest.json")
if os.path.exists(mpath):
    bi = json.load(open(mpath)).get("brandIcon") or {}
    master = bi.get("master", "")
    mono = bi.get("monochrome", "")
    bg = bi.get("background", bg)
    prefix = "assets/" if master and not master.startswith("assets/") else ""
    master = prefix + master if master else ""
    mono = ("assets/" if mono and not mono.startswith("assets/") else "") + mono if mono else ""
if not master:
    bdir = os.path.join(host, "assets", "brand-icons")
    pngs = [f for f in sorted(os.listdir(bdir)) if f.endswith(".png")]
    masters = [f for f in pngs if not any(s in f for s in ("-monochrome", "-splash"))]
    if len(masters) != 1:
        sys.stderr.write(f"FAIL: cannot infer single master in {bdir}: {masters}\n"); sys.exit(1)
    master = "assets/brand-icons/" + masters[0]
    cand = masters[0].replace(".png", "-monochrome.png")
    mono = "assets/brand-icons/" + cand if cand in pngs else master
print(f'ICON="{master}"')
print(f'ICON_MONO="{mono}"')
print(f'ICON_BG="{bg}"')
PY
)"
[[ -f "$HOST/$ICON" ]] || { echo "FAIL: brand master not found: $HOST/$ICON" >&2; exit 1; }
[[ -f "$HOST/$ICON_MONO" ]] || { echo "FAIL: monochrome layer not found: $HOST/$ICON_MONO" >&2; exit 1; }

BASE="$(basename "$ICON" .png)"
SPLASH_LOGO="assets/brand-icons/${BASE}-splash.png"
SPLASH_LOGO_A12="assets/brand-icons/${BASE}-splash-android12.png"

# --- Rasterize splash derivatives -------------------------------------------
#  splash logo: flutter_native_splash renders at source px; 4x the 80dp startup
#  logo => 320px. android_12: ~240dp icon window over a 960px canvas; a 334px
#  logo centered on a TRANSPARENT canvas keeps icon_background_color(_dark)
#  visible (theme-reactive) — sips pads opaquely, so PIL does the padding.
LOGO_SIZE=80
SPLASH_PX=$((LOGO_SIZE * 4))
A12_CANVAS_PX=960
A12_LOGO_PX=334
sips -Z "$SPLASH_PX" "$HOST/$ICON" --out "$HOST/$SPLASH_LOGO" >/dev/null
python3 - "$HOST/$ICON" "$HOST/$SPLASH_LOGO_A12" "$A12_LOGO_PX" "$A12_CANVAS_PX" <<'PY'
import sys
from PIL import Image
src, dst, logo_px, canvas_px = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
logo = Image.open(src).convert("RGBA")
logo.thumbnail((logo_px, logo_px), Image.LANCZOS)
canvas = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
canvas.paste(logo, ((canvas_px - logo.width) // 2, (canvas_px - logo.height) // 2), logo)
canvas.save(dst)
PY

# --- Emit configs -------------------------------------------------------------
sed -e "s|{{ICON}}|$ICON|g" \
    -e "s|{{ICON_MONO}}|$ICON_MONO|g" \
    -e "s|{{ICON_BG}}|$ICON_BG|g" \
    "$TPL/launcher_icons.yaml.tmpl" > "$HOST/flutter_launcher_icons.yaml"
sed -e "s|{{SPLASH_LOGO}}|$SPLASH_LOGO|g" \
    -e "s|{{SPLASH_LOGO_A12}}|$SPLASH_LOGO_A12|g" \
    "$TPL/splash.yaml.tmpl" > "$HOST/flutter_native_splash.yaml"

# --- Legacy brand_colors.dart (only when host carries app_colors.dart) --------
APP_COLORS="$HOST/lib/ui/common/app_colors.dart"
if [[ -f "$APP_COLORS" ]]; then
  ACCENT_ARGB=$(grep -oE 'kcPrimaryColor\s*=\s*Color\(0x[0-9A-Fa-f]{8}\)' "$APP_COLORS" | grep -oE '0x[0-9A-Fa-f]{8}' | head -1)
  [[ -n "$ACCENT_ARGB" ]] || { echo "FAIL: kcPrimaryColor not found in $APP_COLORS" >&2; exit 1; }
  GENERATED_DIR="$HOST/lib/ui/common/generated"
  mkdir -p "$GENERATED_DIR"
  sed -e "s/{{ACCENT_ARGB}}/$ACCENT_ARGB/g" "$TPL/brand_colors.dart.tmpl" > "$GENERATED_DIR/brand_colors.dart"
  echo "emit: $GENERATED_DIR/brand_colors.dart (legacy host)"
else
  echo "skip: brand_colors.dart (kit-native host — colors come from arxa_kit_core)"
fi

echo "emit: $HOST/flutter_launcher_icons.yaml (master: $ICON)"
echo "emit: $HOST/flutter_native_splash.yaml (logo: $SPLASH_LOGO, a12: $SPLASH_LOGO_A12)"
echo "next: (cd $HOST && dart run flutter_launcher_icons && dart run flutter_native_splash:create)"
