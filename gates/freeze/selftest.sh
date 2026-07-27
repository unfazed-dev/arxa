#!/usr/bin/env bash
# gates/freeze/selftest.sh — R5 suite for the freeze gate.
# Happy path AND >=1 negative case. Plants a defect and asserts the gate exits 1
# and names the offending file. The render negative also proves 4.3: one console
# error across several surfaces is reported EXACTLY once (no handler accumulation).
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/freeze.sh"
pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
DESIGN="$T/design"
mkdir -p "$DESIGN/surfaces"

# a valid DTCG tokens.json carrying every required kit token path
mktokens(){ cat > "$DESIGN/tokens.json" <<'JSON'
{"color":{"brand":{"0":{"$type":"color","$value":"#000"}},"bg":{"surface":{"$type":"color","$value":"#fff"},"surface-2":{"$type":"color","$value":"#fafafa"},"paper":{"$type":"color","$value":"#f5f5f5"}},"fg":{"ink":{"$type":"color","$value":"#111"},"muted":{"$type":"color","$value":"#666"},"faint":{"$type":"color","$value":"#999"}},"border":{"rule":{"$type":"color","$value":"#ddd"}},"status":{"good":{"$type":"color","$value":"#0a0"},"warn":{"$type":"color","$value":"#aa0"},"danger":{"$type":"color","$value":"#a00"}}},"typography":{"sans":{"$type":"fontFamily","$value":"Inter"},"mono":{"$type":"fontFamily","$value":"Mono"}}}
JSON
}
# plant <surface-name> [<html-body>]
plant(){ local n="$1" body="${2:-$1}"; printf '<html><body>%s</body></html>\n' "$body" > "$DESIGN/surfaces/$n.html"; }
mkshape(){ printf '# Design System\n' > "$DESIGN/design-system.md"
  printf '{"globs":["surfaces/*"],"selectors":[]}\n' > "$DESIGN/exclusions.json"
  printf '# Direction\napproved\n' > "$DESIGN/direction-approved.md"
  printf '# Brand\n' > "$DESIGN/brand-spec.md"; }

# ---- HAPPY: shape + vocab + exclusions pass (render skipped for a fast green) ----
mktokens; mkshape
printf '{"tabRoots":{},"screens":[{"id":"a","shell":"x","surface":"x_a"}]}\n' > "$DESIGN/structure.json"
plant x_a
o="$(FREEZE_RENDER=skip bash "$GATE" "$T" 2>&1)"; chk "$?" 0 "happy: valid frozen inputs pass"
need "$o" "freeze: PASS" "happy prints PASS"

# ---- NEGATIVE: a required frozen input is missing ----------------------------
# NEGATIVE: tokens.json removed -> gate exits 1 and names the missing file.
rm "$DESIGN/tokens.json"
o="$(FREEZE_RENDER=skip bash "$GATE" "$T" 2>&1)"; chk "$?" 1 "negative: missing tokens.json fails"
need "$o" "tokens.json missing" "negative names the missing file"
mktokens  # restore

# ---- NEGATIVE (4.3 proof): one console error across 4 surfaces, single viewport,
# reported EXACTLY once. A shared page with accumulating handlers would report it
# once per surface already visited (~4x); fresh-page-per-surface reports it once.
printf '{"tabRoots":{},"screens":[{"id":"a","shell":"x","surface":"x_a"},{"id":"b","shell":"x","surface":"x_b"},{"id":"c","shell":"x","surface":"x_c"},{"id":"d","shell":"x","surface":"x_d"}]}\n' > "$DESIGN/structure.json"
plant x_a; plant x_b '<script>console.error("THE_ONE_ERROR")</script>x_b'; plant x_c; plant x_d
o="$(FREEZE_VIEWPORTS=mobile bash "$GATE" "$T" 2>&1)"; chk "$?" 1 "negative: a console error fails the render"
need "$o" "THE_ONE_ERROR" "negative names the console error"
need "$o" "render: 4 surface/viewport render(s), 1 error(s)" "4.3: error reported exactly once across 4 surfaces (no accumulation)"

echo "freeze selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
