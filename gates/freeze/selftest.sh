#!/usr/bin/env bash
# gates/freeze/selftest.sh — R5 suite for the freeze gate.
# Happy path AND >=1 negative case. Plants a defect and asserts the gate exits 1
# and names the offending file. The render negative also proves 4.3: one console
# error across several surfaces is reported EXACTLY once (no handler accumulation).
# Plan 06 adds: --targets drives derived widths (6.4), and the design-approval
# stamp goes stale when targets change after approval (6.7).
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/freeze.sh"
COMMON="$(cd "$(dirname "$0")/../_common" && pwd)"
pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }
avoid(){ case "$1" in *"$2"*) failc=$((failc+1)); echo "  FAIL: output should NOT mention [$2] — $3";; *) pass=$((pass+1));; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T" ${TH:+"$TH"} ${THR:+"$THR"}' EXIT
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
structure(){ printf '{"shellRoots":{},"screens":%s}\n' "$1" > "$DESIGN/structure.json"; }

# ---- HAPPY: shape + vocab + exclusions pass (render skipped for a fast green) ----
mktokens; mkshape
structure '[{"id":"a","shell":"x","surface":"x_a"}]'
plant x_a
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 0 "happy: valid frozen inputs pass"
need "$o" "freeze: PASS" "happy prints PASS"
need "$o" "derived widths for targets [macos]: desktop" "happy reports the derived width set"

# ---- §6: a passing freeze records designHash into LIVE pipeline state --------
# Fixture state via APPBOX_STATE (R5). The tracked seed default.state.json must
# never be written — with no live state the gate notes-and-skips instead.
printf '{"phase":"design","targets":["macos"],"approvalTokens":{},"designHash":"","kitSha":""}\n' > "$T/live.state.json"
o="$(APPBOX_STATE="$T/live.state.json" FREEZE_RENDER=skip bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 0 "§6: freeze pass with live state still passes"
need "$o" "designHash: recorded" "§6: freeze reports the recorded designHash"
h="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["designHash"])' "$T/live.state.json")"
[ -n "$h" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: designHash not written to live state"; }
want_h="$(bash "$COMMON/design_hash.sh" "$DESIGN")"
[ "$h" = "$want_h" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: recorded designHash [$h] != tree hash [$want_h]"; }
# without a live state the seed stays untouched and the gate notes the skip
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 0 "§6: no live state still passes"
need "$o" "designHash: no live pipeline state" "§6: notes the skipped write when only the seed exists"
seed="$(git rev-parse --show-toplevel 2>/dev/null)/pipeline/state/default.state.json"
if [ -f "$seed" ]; then
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["designHash"]=="", "seed designHash was written!"' "$seed" \
    && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: freeze dirtied the tracked seed default.state.json"; }
fi

# ---- 6.4 derived-width derivation proofs (skip render; widths come from config) ----
o="$(FREEZE_RENDER=skip bash "$GATE" --targets ios,android "$T" 2>&1)"; chk "$?" 0 "ios,android derives"
need "$o" "derived widths for targets [ios,android]: mobile tablet" "ios,android -> 2 widths"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets ios,android,web "$T" 2>&1)"; need "$o" "mobile tablet desktop" "ios,android,web -> 3 widths"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets web "$T" 2>&1)"; chk "$?" 0 "web alone derives"
need "$o" "derived widths for targets [web]: mobile tablet desktop" "web alone -> all 3 widths (§11)"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets android "$T" 2>&1)"; chk "$?" 0 "android alone derives"
need "$o" "derived widths for targets [android]: mobile tablet" "android alone -> 2 widths, no desktop (§11)"

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

# ---- htmx producer: shape detection + htmx shape contract (skip render) ----
# Producer-shape seam (dogfood P14 #1): an appbox-designer design (app.routes.js
# + registry + ui/views) is detected as htmx and must NOT need tokens.json /
# exclusions.json / surfaces/*.html (the stacked_kit contract).
TH="$(mktemp -d)"
mkdir -p "$TH/design/ui/views/stage_shell/projects/home"
printf 'export default [\n  ["GET","/",{}],\n];\n' > "$TH/design/app.routes.js"
printf '{"registry":"registry.json","shellRoots":{"projects":"/"},"screens":[{"id":"projects.home","shell":"projects","comp":"Home","shellDir":"stage_shell","surface":"stage_shell_projects_home_view"}]}\n' > "$TH/design/structure.json"
printf '[{"id":"projects.home","surface":"stage_shell_projects_home_view","shell":"projects","comp":"Home"}]\n' > "$TH/design/registry.json"
printf '<html><body>home</body></html>\n' > "$TH/design/ui/views/stage_shell/projects/home/home_view.html"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$TH" 2>&1)"; chk "$?" 0 "htmx: valid frozen inputs pass (no tokens/exclusions needed)"
need "$o" "htmx producer (app.routes.js present)" "htmx producer detected"
avoid "$o" "tokens.json missing" "htmx must NOT require tokens.json"
need "$o" "vocab/exclusions: N/A for the htmx producer" "htmx skips vocab/exclusions"

# ---- htmx NEGATIVE: a required htmx input is missing ------------------------
rm "$TH/design/structure.json"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$TH" 2>&1)"; chk "$?" 1 "htmx negative: missing structure.json fails"
need "$o" "structure.json missing" "names the missing htmx input"

# ---- htmx render exact-count proof (4.3 on the htmx path; needs Node) -------
# Two GET routes served by the designer server, one plants a single console.error.
# render_htmx.mjs uses a fresh page per route, so the error is reported EXACTLY
# once across the 2x1 render matrix — the 4.3 no-accumulation invariant, proven
# on the htmx producer. Skipped (not failed) when Node is absent: the htmx render
# is a Node operation by design (P09).
if command -v node >/dev/null 2>&1; then
  THR="$(mktemp -d)"
  mkdir -p "$THR/design/ui/views/sh/a" "$THR/design/ui/views/sh/b"
  # *_view.html templates satisfy the htmx shape check; the viewmodels below
  # return HTML directly via c.html() so the planted error needs no nunjucks setup.
  printf '<html><body>a</body></html>\n' > "$THR/design/ui/views/sh/a/a_view.html"
  printf '<html><body>b</body></html>\n' > "$THR/design/ui/views/sh/b/b_view.html"
  cat > "$THR/design/app.routes.js" <<'EOF'
import * as a from './ui/views/sh/a/a_viewmodel.js';
import * as b from './ui/views/sh/b/b_viewmodel.js';
export default [ ['GET','/a',a.page], ['GET','/b',b.page] ];
EOF
  cat > "$THR/design/ui/views/sh/a/a_viewmodel.js" <<'EOF'
export const page = (c) => c.html('<html><body>a</body></html>');
EOF
  cat > "$THR/design/ui/views/sh/b/b_viewmodel.js" <<'EOF'
export const page = (c) => c.html('<html><body><script>console.error("THE_ONE_ERROR")</script>b</body></html>');
EOF
  printf '{"registry":"registry.json","shellRoots":{},"screens":[{"id":"a","shell":"sh","shellDir":"sh","surface":"sh_a_view"},{"id":"b","shell":"sh","shellDir":"sh","surface":"sh_b_view"}]}\n' > "$THR/design/structure.json"
  printf '[{"id":"a","surface":"sh_a_view","shell":"sh","comp":"A"},{"id":"b","surface":"sh_b_view","shell":"sh","comp":"B"}]\n' > "$THR/design/registry.json"
  o="$(bash "$GATE" --targets macos "$THR" 2>&1)"; chk "$?" 1 "htmx render: a console error fails the render"
  need "$o" "THE_ONE_ERROR" "htmx render names the console error"
  need "$o" "render: 2 route/viewport render(s) across 1 derived width(s), 1 error(s)" "htmx 4.3: one error across two routes reported exactly once"
  # clean variant passes
  printf 'export const page = (c) => c.html(%s);\n' "'<html><body>b</body></html>'" > "$THR/design/ui/views/sh/b/b_viewmodel.js"
  o="$(bash "$GATE" --targets macos "$THR" 2>&1)"; chk "$?" 0 "htmx render: clean routes pass"
  need "$o" "0 error(s)" "htmx render reports zero errors when clean"
else
  echo "  (skip: htmx render exact-count case — node not on PATH)"
fi

# ---- l10n parity (3b): locale ARBs must match the app_en.arb template -------
# HAPPY: app_pl.arb at key + placeholder parity with the template passes
# (@-prefixed metadata keys are ignored).
mkdir -p "$DESIGN/l10n"
printf '{\n  "homeTitle": "Projects",\n  "@homeTitle": {},\n  "welcome": "Hello {name}"\n}\n' > "$DESIGN/l10n/app_en.arb"
printf '{\n  "homeTitle": "Projekty",\n  "welcome": "Cześć {name}"\n}\n' > "$DESIGN/l10n/app_pl.arb"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 0 "l10n: key + placeholder parity passes"
need "$o" "l10n: 1 locale catalog(s) at key + placeholder parity" "l10n happy reports parity"

# NEGATIVE: a locale missing a template key fails, naming the locale and key.
printf '{\n  "homeTitle": "Projekty"\n}\n' > "$DESIGN/l10n/app_pl.arb"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 1 "l10n negative: missing key fails"
need "$o" "app_pl.arb missing key(s)" "l10n negative names the locale catalog"
need "$o" "welcome" "l10n negative names the missing key"

# NEGATIVE: placeholder drift ({name} in the template, {user} in the locale)
# fails, naming the drifted key.
printf '{\n  "homeTitle": "Projekty",\n  "welcome": "Cześć {user}"\n}\n' > "$DESIGN/l10n/app_pl.arb"
o="$(FREEZE_RENDER=skip bash "$GATE" --targets macos "$T" 2>&1)"; chk "$?" 1 "l10n negative: placeholder drift fails"
need "$o" "placeholder drift" "l10n negative names the placeholder drift"
need "$o" "welcome" "l10n negative names the drifted key"
rm -rf "$DESIGN/l10n"

echo "freeze selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
