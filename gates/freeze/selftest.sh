#!/usr/bin/env bash
# gates/freeze/selftest.sh — R5 suite for the freeze gate.
# Happy path AND >=1 negative case. Plants a defect and asserts the gate exits 1
# and names the offending file. The render negative also proves 4.3: one console
# error across several surfaces is reported EXACTLY once (no handler accumulation).
# Plan 06 adds: --targets drives derived widths (6.4), and the design-approval
# stamp goes stale when targets change after approval (6.7).
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
structure(){ printf '{"tabRoots":{},"screens":%s}\n' "$1" > "$DESIGN/structure.json"; }

# ---- HAPPY: shape + vocab + exclusions pass (render skipped for a fast green) ----
mktokens; mkshape
structure '[{"id":"a","shell":"x","surface":"x_a"}]'
plant x_a
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 0 "happy: valid frozen inputs pass"
need "$o" "freeze: PASS" "happy prints PASS"
need "$o" "derived widths for targets [macos]: desktop" "happy reports the derived width set"

# ---- 6.4 derived-width derivation proofs (skip render; widths come from config) ----
o="$(FREEZE_RENDER=skip bash "$GATE" --targets ios,android "$T" 2>&1)"; chk "$?" 0 "ios,android derives"
need "$o" "derived widths for targets [ios,android]: mobile tablet" "ios,android -> 2 widths"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets ios,android,web "$T" 2>&1)"; need "$o" "mobile tablet desktop" "ios,android,web -> 3 widths"

# ---- NEGATIVE: a required frozen input is missing ----------------------------
# NEGATIVE: tokens.json removed -> gate exits 1 and names the missing file.
rm "$DESIGN/tokens.json"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 1 "negative: missing tokens.json fails"
need "$o" "tokens.json missing" "negative names the missing file"
mktokens  # restore

# ---- NEGATIVE (6.3): no --targets and no targets in state -> fails loudly ----
printf '{"phase":"intake"}\n' > "$T/empty.state.json"   # no targets key
o="$(APPBOX_STATE="$T/empty.state.json" FREEZE_RENDER=skip bash "$GATE" "$T" 2>&1)"; chk "$?" 1 "negative: no targets fails loudly"
need "$o" "no --targets given" "names the missing explicit-targets requirement"

# ---- NEGATIVE: unknown target fails loudly ----------------------------------
o="$(FREEZE_RENDER=skip bash "$GATE" --targets zxspectrum "$T" 2>&1)"; chk "$?" 1 "negative: unknown target fails"
need "$o" "unknown target" "names the unknown target"

# ---- NEGATIVE (4.3 proof): one console error across 4 surfaces, single derived
# width (desktop, from --targets macos), reported EXACTLY once. A shared page
# with accumulating handlers would report it once per surface already visited
# (~4x); fresh-page-per-surface reports it once.
structure '[{"id":"a","shell":"x","surface":"x_a"},{"id":"b","shell":"x","surface":"x_b"},{"id":"c","shell":"x","surface":"x_c"},{"id":"d","shell":"x","surface":"x_d"}]'
plant x_a; plant x_b '<script>console.error("THE_ONE_ERROR")</script>x_b'; plant x_c; plant x_d
o="$(bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 1 "negative: a console error fails the render"
need "$o" "THE_ONE_ERROR" "negative names the console error"
need "$o" "render: 4 surface/viewport render(s) across 1 derived width(s), 1 error(s)" "4.3: error reported exactly once across 4 surfaces (no accumulation)"

# ---- 6.7 approval invalidation proof ----------------------------------------
# approve at macos, re-run macos (valid), then change targets -> STALE, loudly.
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos --approve "$T" 2>&1)"; chk "$?" 0 "approve mints the stamp"
need "$o" "freeze: APPROVED" "approve prints APPROVED"
[ -f "$DESIGN/approval.lock" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: approval.lock not written"; }
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 0 "same targets after approval: valid"
need "$o" "approval.lock valid" "valid stamp is acknowledged"
# adding a target after approval must invalidate the token (6.7 / done-when #5)
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos,ios "$T" 2>&1)"; chk "$?" 1 "changed targets after approval: STALE"
need "$o" "approval STALE" "stale approval fails loudly"
need "$o" "targets changed since approval" "names the reason (targets changed)"

echo "freeze selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
