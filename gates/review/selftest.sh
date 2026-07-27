#!/usr/bin/env bash
# gates/review/selftest.sh — R5 suite for the review (design judge) gate.
# Happy path AND >=1 negative case. Plants a defect and asserts the gate exits 1
# and names the offending token. The vendored gate's own --self-test references a
# fixture file that is not shipped, so this suite is self-contained: it builds a
# tmp surface and exercises the gate's normal CLI (dart review.dart <view-file>).
set -uo pipefail
GATE_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$GATE_DIR/review.dart"
pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SURF="$T/lib/ui/views/train_shell/home"; mkdir -p "$SURF"

# build a clean 5-file form-factor set + a design-system.md (palette + forbidden)
plant_clean(){ local b="$SURF/home_view"; local s
  for s in '' .mobile .tablet .desktop; do printf 'class HomeView%s {}\n' "${s}" > "$b$s.dart"; done
  printf 'class HomeViewModel {}\n' > "$SURF/home_viewmodel.dart"
  printf '## Palette\nkcPrimaryColor\n\n## Forbidden\nIcons.* ad-hoc Color\n' > "$SURF/design-system.md"
}

# ---- HAPPY: a clean surface passes every check -------------------------------
plant_clean
o="$(dart "$GATE" "$SURF/home_view.dart" 2>&1)"; chk "$?" 0 "happy: clean surface passes"
need "$o" "OK — all" "happy prints OK"

# ---- NEGATIVE: a hardcoded Color literal in view code -----------------------
# NEGATIVE: Color(0xFF112233) is an ad-hoc color -> no_hardcoded_colors fails,
# naming the literal (view code must use KitColors.* / Theme.of(context)).
plant_clean
printf 'class HomeView { final c = Color(0xFF112233); }\n' > "$SURF/home_view.dart"
o="$(dart "$GATE" "$SURF/home_view.dart" 2>&1)"; chk "$?" 1 "negative: hardcoded color fails"
need "$o" "Color(0xFF112233)" "negative names the offending color literal"
need "$o" "no_hardcoded_colors" "negative names the failed check"

echo "review selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
