#!/usr/bin/env bash
# branding/scripts/branding_gate.sh — pipeline scaffold sub-gate C.
#
# Read-only assertion that the host app's brand layer is generated and
# consistent (the output contract of tools/generate_branding.sh). Runs with
# cwd = the app (pipeline.sh cd's to $APP in consumer mode). Fails loud on any
# drift; does NOT regenerate — generation is a build step, a gate only asserts.
#
# In monorepo mode this script is never invoked (pipeline sets SCAFFOLD_GATE_C=pass
# there — no app to brand). PIPELINE_BRANDING_GATE overrides the path.
set -uo pipefail
fail(){ echo "FAIL (branding): $1"; exit 1; }

# 1. Host brand accent (kcPrimaryColor) must resolve from app_colors.dart.
APP_COLORS="lib/ui/common/app_colors.dart"
[ -f "$APP_COLORS" ] || fail "app_colors not found: $APP_COLORS"
ACCENT_ARGB=$(grep -E 'kcPrimaryColor[[:space:]]*=[[:space:]]*Color\(0x[0-9A-Fa-f]{8}\)' "$APP_COLORS" \
  | grep -oE '0x[0-9A-Fa-f]{8}' | head -1 | sed 's/^0x//')
[ -n "$ACCENT_ARGB" ] || fail "kcPrimaryColor Color(0xAARRGGBB) not found in $APP_COLORS"

# 2. generated brand_colors.dart exists and its accent matches the host's.
BC="lib/ui/common/generated/brand_colors.dart"
[ -f "$BC" ] || fail "generated/brand_colors.dart missing — run branding/tools/generate_branding.sh"
grep -qE "accent[[:space:]]*=[[:space:]]*Color\(0x$ACCENT_ARGB\)" "$BC" \
  || fail "brand_colors.dart accent drift — expected 0x$ACCENT_ARGB (regenerate via generate_branding.sh)"

# 3. Icon + splash configs present. Launcher icon -> icon.png; native splash
#    main image -> splash_logo.png (the 4× rasterized PNG, NOT the 1024px icon).
LI="flutter_launcher_icons.yaml"; NS="flutter_native_splash.yaml"
[ -f "$LI" ] || fail "$LI missing — run generate_branding.sh"
[ -f "$NS" ] || fail "$NS missing — run generate_branding.sh"
grep -qE 'image_path:[[:space:]]*assets/icons/icon\.png' "$LI" \
  || fail "$LI image_path must be assets/icons/icon.png (note: 'icons', not 'icon')"
grep -qE 'image:[[:space:]]*assets/icons/splash_logo\.png' "$NS" \
  || fail "$NS image must be assets/icons/splash_logo.png (the 4× rasterized logo, not the 1024px icon) — regenerate via generate_branding.sh"

# 4. Icon source asset exists.
[ -f "assets/icons/icon.png" ] || fail "icon source missing: assets/icons/icon.png"

# 5. Native splash must NOT use the brand accent as its background, and must
#    carry color_dark so it follows the system theme. Regression guard for the
#    accent-splash bug (native splash renders before Flutter, can't read ThemeMode,
#    so an accent color clashed with the warm app surface and never went dark).
ACCENT_RGB="${ACCENT_ARGB:2:6}"   # strip 2-char alpha -> RR GG BB (matches generate_branding.sh)
grep -qE 'color_dark:' "$NS" \
  || fail "$NS missing color_dark — native splash won't follow the system theme (regenerate via generate_branding.sh)"
grep -qE "^[[:space:]]*color:[[:space:]]*\"#$ACCENT_RGB\"" "$NS" \
  && fail "$NS color is the brand accent (#$ACCENT_RGB) — must be the app surface (AppBoxKitColors.surface), not accent"

# 6. Native-splash logo PNG must exist and be sized at 4× logoSize (320px) — NOT
#    the full-res 1024px launcher icon (renders enormous on the OS splash, which
#    cannot read Flutter dp). Keep SPLASH_PX in sync with generate_branding.sh +
#    AppBoxKitBrandSplash.logoSize (branding/lib/src/appbox_kit_startup_view.dart).
LOGO_SIZE=80
SPLASH_PX=$((LOGO_SIZE * 4))   # 320
SPLASH_PNG="assets/icons/splash_logo.png"
[ -f "$SPLASH_PNG" ] || fail "splash_logo.png missing — run generate_branding.sh (rasterizes icon.png at ${SPLASH_PX}px)"
if command -v sips >/dev/null 2>&1; then
  _W=$(sips -g pixelWidth "$SPLASH_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  [ -n "$_W" ] || fail "cannot read splash_logo.png dimensions"
  [ "$_W" -le "$SPLASH_PX" ] || fail "splash_logo.png is ${_W}px — must be ≤${SPLASH_PX}px (4× logo ${LOGO_SIZE}dp); regenerate via generate_branding.sh"
fi

# 7. android_12 native-splash logo must be the PADDED asset (small logo centered in
#    a 960 canvas), NOT the full-frame icon — Android 12+ sizes the splash logo by its
#    fraction of the icon window, so a full-frame icon renders ~2.9× the iOS logo.
#    A960px canvas proves generate_branding.sh padded it (raw icon is 1024px). Keep
#    A12_CANVAS_PX in sync with generate_branding.sh.
A12_CANVAS_PX=960
A12_SPLASH_PNG="assets/icons/splash_logo_android12.png"
grep -qE 'image:[[:space:]]*assets/icons/splash_logo_android12\.png' "$NS" \
  || fail "$NS android_12.image must be assets/icons/splash_logo_android12.png (padded to match the iOS logo size) — regenerate via generate_branding.sh"
[ -f "$A12_SPLASH_PNG" ] || fail "splash_logo_android12.png missing — run generate_branding.sh"
if command -v sips >/dev/null 2>&1; then
  _A12W=$(sips -g pixelWidth "$A12_SPLASH_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  [ "$_A12W" = "$A12_CANVAS_PX" ] \
    || fail "splash_logo_android12.png is ${_A12W}px — must be a ${A12_CANVAS_PX}px padded canvas (not the raw icon); regenerate via generate_branding.sh"
fi

echo "OK (branding): brand_colors accent=0x$ACCENT_ARGB; icons+splash configs present; splash bg=surface (theme-reactive); splash logo≤${SPLASH_PX}px; android_12 logo padded in ${A12_CANVAS_PX}px canvas"
exit 0
