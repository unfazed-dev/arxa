#!/usr/bin/env bash
# gates/structure/selftest.sh — R5 suite for the structure gate.
# Happy path AND >=1 negative case. Plants a defect and asserts the gate exits 1
# and names the offending file/surface.
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/structure.sh"
pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
DESIGN="$T/design"; mkdir -p "$DESIGN/surfaces"
surfaces(){ cat > "$DESIGN/structure.json"; }
sf(){ printf '<html><body>%s</body></html>\n' "$1" > "$DESIGN/surfaces/$2.html"; }

# ---- HAPPY: every declared surface resolves, none orphaned -------------------
surfaces <<'JSON'
{"tabRoots":{"train":"train.home"},
 "screens":[
   {"id":"train.home","tab":"train","shell":"train_shell","surface":"train_shell_home_view"},
   {"id":"train.stats","tab":"train","shell":"train_shell","surface":"train_shell_stats_view"}]}
JSON
sf home train_shell_home_view; sf stats train_shell_stats_view
o="$(bash "$GATE" "$T" 2>&1)"; chk "$?" 0 "happy: declared surfaces resolve"
need "$o" "structure: PASS" "happy prints PASS"

# ---- NEGATIVE: a declared surface has no file (dangling promise) -------------
# NEGATIVE: train_shell_stats_view declared but its file is absent -> exit 1,
# naming both the screen and the missing surface file.
rm "$DESIGN/surfaces/train_shell_stats_view.html"
o="$(bash "$GATE" "$T" 2>&1)"; chk "$?" 1 "negative: dangling surface declaration fails"
need "$o" "train_shell_stats_view" "negative names the missing surface"
sf stats train_shell_stats_view  # restore

# ---- NEGATIVE: a surface file nobody claims (orphan) -------------------------
# NEGATIVE: an extra surface on disk is claimed by no screen -> exit 1, naming it.
sf ghost train_shell_ghost_view
o="$(bash "$GATE" "$T" 2>&1)"; chk "$?" 1 "negative: orphan surface fails"
need "$o" "train_shell_ghost_view" "negative names the orphan surface"

echo "structure selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
