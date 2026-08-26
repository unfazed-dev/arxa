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
# naming the literal (view code must use ArxaKitColors.* / Theme.of(context)).
plant_clean
printf 'class HomeView { final c = Color(0xFF112233); }\n' > "$SURF/home_view.dart"
o="$(dart "$GATE" "$SURF/home_view.dart" 2>&1)"; chk "$?" 1 "negative: hardcoded color fails"
need "$o" "Color(0xFF112233)" "negative names the offending color literal"
need "$o" "no_hardcoded_colors" "negative names the failed check"

# ---- §16 derivation: a manifest-declared factor set is the expected file set --
# A .shell-structure.json with factors=[desktop] means a 3-file set (view +
# _view.desktop.dart + viewmodel), NOT the legacy 5-file mobile+tablet+desktop.
MAC="$T/lib/ui/views"; mkdir -p "$MAC"
printf '{"selfContained":["m"],"surfaces":{"m":{"m_d_view":"d"}},"factors":["desktop"],"targets":["macos"]}\n' \
  > "$MAC/.shell-structure.json"
DS="$MAC/m/d"; mkdir -p "$DS"
printf 'class DView {}\n'            > "$DS/d_view.dart"
printf 'class DViewDesktop {}\n'     > "$DS/d_view.desktop.dart"
printf 'class DViewModel {}\n'       > "$DS/d_viewmodel.dart"
printf '## Palette\nkcPrimaryColor\n\n## Forbidden\nIcons.*\n' > "$DS/design-system.md"
o="$(dart "$GATE" "$DS/d_view.dart" 2>&1)"; chk "$?" 0 "§16: manifest factors=[desktop], desktop file present -> 3-file set PASSES"
need "$o" "derived factors desktop" "§16 pass cites the derived set + manifest"

# NEGATIVE: a manifest declares factors=[desktop] but the desktop file is missing
# -> form_factor_files FAILS naming the missing _view.desktop.dart (NOT demanding
# the legacy mobile/tablet the derivation correctly omits).
rm "$DS/d_view.desktop.dart"
o="$(dart "$GATE" "$DS/d_view.dart" 2>&1)"; chk "$?" 1 "§16 negative: declared desktop factor missing -> FAILS"
need "$o" "d_view.desktop.dart" "§16 negative names the missing derived factor file"
need "$o" "form_factor_files" "§16 negative names the failed check"
need "$o" "3-file set" "§16 negative explains macos is a 3-file set, not 5"

# ---- §16 derivation: web's 3-factor manifest -> the full 5-file set ---------
# factors=[mobile,tablet,desktop] (web) must require all three factor files,
# same total as the legacy set but via derivation, not the fallback.
WEB="$T/lib/ui/views_web"; mkdir -p "$WEB"
printf '{"selfContained":["m"],"surfaces":{"m":{"m_w_view":"w"}},"factors":["mobile","tablet","desktop"],"targets":["web"]}\n' \
  > "$WEB/.shell-structure.json"
WS="$WEB/m/w"; mkdir -p "$WS"
printf 'class WView {}\n'            > "$WS/w_view.dart"
printf 'class WViewMobile {}\n'      > "$WS/w_view.mobile.dart"
printf 'class WViewTablet {}\n'      > "$WS/w_view.tablet.dart"
printf 'class WViewDesktop {}\n'     > "$WS/w_view.desktop.dart"
printf 'class WViewModel {}\n'       > "$WS/w_viewmodel.dart"
printf '## Palette\nkcPrimaryColor\n\n## Forbidden\nIcons.*\n' > "$WS/design-system.md"
o="$(dart "$GATE" "$WS/w_view.dart" 2>&1)"; chk "$?" 0 "§16: web manifest factors=[mobile,tablet,desktop], all present -> 5-file set PASSES"
need "$o" "derived factors mobile, tablet, desktop" "§16 web pass cites the derived set"

# NEGATIVE: web manifest but the tablet factor file is missing -> FAILS naming it.
rm "$WS/w_view.tablet.dart"
o="$(dart "$GATE" "$WS/w_view.dart" 2>&1)"; chk "$?" 1 "§16 negative: web declared tablet factor missing -> FAILS"
need "$o" "w_view.tablet.dart" "§16 web negative names the missing derived factor file"
need "$o" "form_factor_files" "§16 web negative names the failed check"

# ---- i18n: no_hardcoded_strings (copy comes from ARB via AppLocalizations) ----
# NEGATIVE: a hardcoded Text('Loading ...') in a view file fails, naming the
# literal and the check.
plant_clean
printf 'class HomeView { final t = Text(%s); }\n' "'Loading ...'" > "$SURF/home_view.dart"
o="$(dart "$GATE" "$SURF/home_view.dart" 2>&1)"; chk "$?" 1 "i18n negative: hardcoded Text literal fails"
need "$o" "no_hardcoded_strings" "i18n negative names the failed check"
need "$o" "Loading ..." "i18n negative names the offending literal"
# GREEN: the same surface with copy resolved via AppLocalizations passes.
printf 'class HomeView { final t = Text(AppLocalizations.of(context)!.loading); }\n' > "$SURF/home_view.dart"
o="$(dart "$GATE" "$SURF/home_view.dart" 2>&1)"; chk "$?" 0 "i18n: AppLocalizations copy passes"
# GREEN: a scaffolder stub (STRUCTURE ONLY header) with a placeholder key passes.
{ printf '// arxa-scaffolder: surface skeleton. STRUCTURE ONLY — the builder fills this.\n'
  printf 'class HomeView { final t = Text(%s); }\n' "'projects.home'"; } > "$SURF/home_view.dart"
o="$(dart "$GATE" "$SURF/home_view.dart" 2>&1)"; chk "$?" 0 "i18n: STRUCTURE ONLY stub with placeholder key passes"

echo "review selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
