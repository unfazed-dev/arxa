#!/usr/bin/env bash
# branding/scripts/branding_gate.sh — pipeline scaffold sub-gate C.
#
# Read-only assertion that the host app's brand layer is generated and
# consistent (the output contract of tools/generate_branding.sh, brand-icons
# law 2026-08-09). Runs with cwd = the app (pipeline.sh cd's to $APP in
# consumer mode). Fails loud on any drift; does NOT regenerate — generation is
# a build step, a gate only asserts.
#
# In monorepo mode this script is never invoked (pipeline sets SCAFFOLD_GATE_C=pass
# there — no app to brand). PIPELINE_BRANDING_GATE overrides the path.
set -uo pipefail
fail(){ echo "FAIL (branding): $1"; exit 1; }

# 1. Brand-icons law: the app owns its master in assets/brand-icons/.
[ -d "assets/brand-icons" ] || fail "assets/brand-icons/ missing — every app owns its brand master there (law 2026-08-09)"

# 2. Launcher config present and pointing into brand-icons, with the
#    theme-adaptive monochrome layer declared.
LI="flutter_launcher_icons.yaml"; NS="flutter_native_splash.yaml"
[ -f "$LI" ] || fail "$LI missing — run generate_branding.sh"
[ -f "$NS" ] || fail "$NS missing — run generate_branding.sh"
ICON=$(grep -E '^[[:space:]]*image_path:' "$LI" | head -1 | grep -oE 'assets/brand-icons/[^"]+\.png')
[ -n "$ICON" ] || fail "$LI image_path must point into assets/brand-icons/ (brand-icons law)"
[ -f "$ICON" ] || fail "brand master missing: $ICON"
ICON_MONO=$(grep -E '^[[:space:]]*adaptive_icon_monochrome:' "$LI" | grep -oE 'assets/brand-icons/[^"]+\.png')
[ -n "$ICON_MONO" ] || fail "$LI missing adaptive_icon_monochrome — Android 13+ theme adaptation needs the alpha-glyph layer"
[ -f "$ICON_MONO" ] || fail "monochrome layer missing: $ICON_MONO"

# 3. When the app carries an assets manifest, the launcher master must mirror
#    brandIcon.master (single-SSOT check).
if [ -f "assets.manifest.json" ]; then
  M=$(python3 -c "import json;print((json.load(open('assets.manifest.json')).get('brandIcon') or {}).get('master',''))" 2>/dev/null)
  case "$M" in
    ""|null) : ;;
    assets/*) [ "$ICON" = "$M" ] || fail "launcher master ($ICON) != manifest brandIcon.master ($M)" ;;
    *) [ "$ICON" = "assets/$M" ] || fail "launcher master ($ICON) != manifest brandIcon.master (assets/$M)" ;;
  esac
fi

# 4. Native splash: theme-reactive (color_dark), never the brand accent, and
#    the main image is the 4×-rasterized -splash derivative in brand-icons.
grep -qE 'color_dark:' "$NS" \
  || fail "$NS missing color_dark — native splash won't follow the system theme (regenerate via generate_branding.sh)"
SPLASH_PNG=$(grep -E '^[[:space:]]*image:' "$NS" | head -1 | grep -oE 'assets/brand-icons/[^"]+-splash\.png')
[ -n "$SPLASH_PNG" ] || fail "$NS image must be the assets/brand-icons/<base>-splash.png derivative (not the 1024px master) — regenerate via generate_branding.sh"
[ -f "$SPLASH_PNG" ] || fail "splash derivative missing: $SPLASH_PNG — run generate_branding.sh"

# 5. Splash logo sized at 4× logoSize (320px) — NOT the full-res master (renders
#    enormous on the OS splash, which cannot read Flutter dp). Keep SPLASH_PX in
#    sync with generate_branding.sh.
LOGO_SIZE=80
SPLASH_PX=$((LOGO_SIZE * 4))   # 320
if command -v sips >/dev/null 2>&1; then
  _W=$(sips -g pixelWidth "$SPLASH_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  [ -n "$_W" ] || fail "cannot read $SPLASH_PNG dimensions"
  [ "$_W" -le "$SPLASH_PX" ] || fail "$SPLASH_PNG is ${_W}px — must be ≤${SPLASH_PX}px (4× logo ${LOGO_SIZE}dp); regenerate via generate_branding.sh"
fi

# 6. android_12: padded transparent 960-canvas derivative + theme-reactive
#    icon_background_color(_dark) — Android 12+ sizes the splash logo by its
#    fraction of the icon window; the transparent canvas lets the icon
#    background colors follow the system theme. Keep A12_CANVAS_PX in sync
#    with generate_branding.sh.
A12_CANVAS_PX=960
A12_SPLASH_PNG=$(grep -E '^[[:space:]]*image:' "$NS" | sed -n '2p' | grep -oE 'assets/brand-icons/[^"]+-splash-android12\.png')
[ -n "$A12_SPLASH_PNG" ] || fail "$NS android_12.image must be the assets/brand-icons/<base>-splash-android12.png padded derivative — regenerate via generate_branding.sh"
[ -f "$A12_SPLASH_PNG" ] || fail "android12 splash derivative missing: $A12_SPLASH_PNG — run generate_branding.sh"
grep -qE 'icon_background_color_dark:' "$NS" \
  || fail "$NS android_12 missing icon_background_color_dark — a12 splash won't follow the system theme"
if command -v sips >/dev/null 2>&1; then
  _A12W=$(sips -g pixelWidth "$A12_SPLASH_PNG" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  [ "$_A12W" = "$A12_CANVAS_PX" ] \
    || fail "$A12_SPLASH_PNG is ${_A12W}px — must be a ${A12_CANVAS_PX}px padded canvas (not the raw master); regenerate via generate_branding.sh"
fi

# 7. LEGACY hosts only (app_colors.dart present): vendored brand_colors.dart
#    must exist and match the host accent, and the splash background must not
#    be that accent. Kit-native hosts skip (colors come from appbox_kit_core).
APP_COLORS="lib/ui/common/app_colors.dart"
if [ -f "$APP_COLORS" ]; then
  ACCENT_ARGB=$(grep -E 'kcPrimaryColor[[:space:]]*=[[:space:]]*Color\(0x[0-9A-Fa-f]{8}\)' "$APP_COLORS" \
    | grep -oE '0x[0-9A-Fa-f]{8}' | head -1 | sed 's/^0x//')
  [ -n "$ACCENT_ARGB" ] || fail "kcPrimaryColor Color(0xAARRGGBB) not found in $APP_COLORS"
  BC="lib/ui/common/generated/brand_colors.dart"
  [ -f "$BC" ] || fail "generated/brand_colors.dart missing — run branding/tools/generate_branding.sh"
  grep -qE "accent[[:space:]]*=[[:space:]]*Color\(0x$ACCENT_ARGB\)" "$BC" \
    || fail "brand_colors.dart accent drift — expected 0x$ACCENT_ARGB (regenerate via generate_branding.sh)"
  ACCENT_RGB="${ACCENT_ARGB:2:6}"
  grep -qiE "^[[:space:]]*color:[[:space:]]*\"#$ACCENT_RGB\"" "$NS" \
    && fail "$NS color is the brand accent (#$ACCENT_RGB) — must be the app surface, not accent"
  LEGACY="legacy brand_colors accent=0x$ACCENT_ARGB; "
else
  LEGACY="kit-native host (no app_colors.dart); "
fi

# 8. Web entrypoint law (scaffolder SKILL.md "Web entrypoint"): when the app
#    targets web, index.html must be normalized — font-law preconnect pair (no
#    css2 stylesheet, no font binaries), theme-reactive splash CSS in the kit
#    surface pair, and the native-splash picture.
WEB=""
if [ -f "web/index.html" ]; then
  IDX="web/index.html"
  grep -q 'rel="preconnect" href="https://fonts.googleapis.com"' "$IDX" \
    || fail "$IDX missing fonts.googleapis.com preconnect (font law)"
  grep -qE 'rel="preconnect" href="https://fonts\.gstatic\.com" crossorigin' "$IDX" \
    || fail "$IDX missing fonts.gstatic.com crossorigin preconnect (font law)"
  grep -q 'fonts.googleapis.com/css2' "$IDX" \
    && fail "$IDX links a css2 stylesheet — Flutter web gets fonts via the google_fonts package at runtime, preconnects only"
  grep -qE '\.(woff2?|ttf|otf)' "$IDX" \
    && fail "$IDX references font binaries — no self-hosted fonts (font law)"
  grep -q 'background-color: #F5F0E8' "$IDX" \
    || fail "$IDX splash CSS must set light background #F5F0E8 (kit surface, uppercase hex)"
  grep -q 'background-color: #1C1814' "$IDX" \
    || fail "$IDX splash CSS must set dark background #1C1814 under prefers-color-scheme: dark"
  grep -q 'prefers-color-scheme: dark' "$IDX" \
    || fail "$IDX splash CSS missing the prefers-color-scheme: dark block — web splash must follow the system theme"
  grep -q 'id="splash"' "$IDX" \
    || fail "$IDX missing the flutter_native_splash #splash picture — run dart run flutter_native_splash:create"
  WEB="; web/index.html normalized (preconnects, themed splash)"
fi

echo "OK (branding): ${LEGACY}master=$ICON (+monochrome); splash bg=surface (theme-reactive, color_dark); splash logo≤${SPLASH_PX}px; android_12 transparent ${A12_CANVAS_PX}px canvas + themed icon bg${WEB}"
exit 0
