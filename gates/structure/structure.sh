#!/usr/bin/env bash
# structure.sh — the STRUCTURE gate (plan 04.1): split out of the vendored
# freeze_design.sh along the render/structure seam. Freeze owns "the frozen
# inputs exist and render clean"; THIS gate owns the shell/surface MAP — does
# structure.json resolve, is it in sync with the authored registry, and are
# there orphans either way.
#
# Asserts (cheapest first, all must pass):
#   S0  input   — design/structure.json is present and parses (missing input
#                 FAILS — a gate that cannot find its input never passes quietly)
#   S1  drift   — when the producer source (jsx/app.jsx) is present, structure.json
#                 is regenerated and compared via emit_structure --check
#   S2  resolve — every declared surface has a file; every file is claimed by
#                 exactly one screen; shells match the filename prefix; no tab
#                 root was left without a surface
#
# Findings route through gates/_common/sarif.sh (4.2): one SARIF transport for
# the GUI, the companion and a CI log.
#
# Usage: structure.sh [app-root]   (0 pass / 1 FAIL / 2 env)
# $KIT_DESIGN_DIR selects the producer folder (default: design), app-root-relative.
set -uo pipefail

GATE_COMMON="$(cd "$(dirname "$0")/../_common" && pwd)"
# shellcheck source=../_common/sarif.sh
source "$GATE_COMMON/sarif.sh"

APP="${1:-$PWD}"
APP="$(cd "$APP" 2>/dev/null && pwd)" || { echo "FAIL: app root not found: ${1:-$PWD}" >&2; exit 2; }
DESIGN_REL="${KIT_DESIGN_DIR:-design}"
case "$DESIGN_REL" in
  /*) echo "FAIL: KIT_DESIGN_DIR must be relative to the app root, got: $DESIGN_REL" >&2; exit 2 ;;
esac
DESIGN="$APP/$DESIGN_REL"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

F=0
fail(){ echo "FAIL: $1" >&2; F=$((F+1)); sarif_result "structure" "error" "$DESIGN_REL/structure.json" "$1"; }
ok(){ echo "  ✓ $1"; }

STRUCTURE="$DESIGN/structure.json"

# ---- S0: input present ---------------------------------------------------------
if [ ! -f "$STRUCTURE" ]; then
  fail "structure: no $DESIGN_REL/structure.json — the structure gate's input is missing (freeze the design first)"
  exit 1
fi

# ---- S1: drift against the authored registry -----------------------------------
# A producer with a jsx/ registry is the arbiter of structure.json; re-derive and
# compare. Safe inside the gate (no browser). A producer with no jsx/ has no
# second source to drift from; S2 below is then the drift check.
EMIT="$REPO_ROOT/tools/vendor/emit_structure/emit_structure.py"
if [ -f "$DESIGN/jsx/app.jsx" ]; then
  if [ ! -f "$EMIT" ]; then
    fail "structure: $DESIGN_REL/jsx/app.jsx present but emit_structure.py not found at $EMIT"
  elif python3 "$EMIT" --app "$APP" --design-dir "$DESIGN_REL" --check >/dev/null 2>&1; then
    ok "structure: structure.json is in sync with $DESIGN_REL/jsx/app.jsx"
  else
    fail "structure: $DESIGN_REL/structure.json drifted from jsx/app.jsx — re-run emit_structure.py"
  fi
fi

# ---- S2: resolution (a–e) ------------------------------------------------------
# The python prints its ✓ line to stdout and FAIL lines to stderr; we merge (2>&1)
# into one capture so the FAIL lines can be routed through sarif, then replay the
# whole thing for the human reader.
pyout="$(python3 - "$DESIGN" "$DESIGN_REL" 2>&1 <<'PY'
import json,sys,os,glob
design,rel=sys.argv[1],sys.argv[2]
HARNESS={"index"}   # the harness page, not a product surface
def bad(m): print(f"FAIL: structure: {m}")
try: st=json.load(open(os.path.join(design,"structure.json")))
except Exception as e: bad(f"structure.json does not parse — {e}"); sys.exit(1)

f=0
screens=st.get("screens"); roots=st.get("tabRoots")
if not isinstance(screens,list) or not screens:
    bad(f"{rel}/structure.json needs a non-empty \"screens\" list"); sys.exit(1)
if not isinstance(roots,dict):
    bad(f"{rel}/structure.json needs a \"tabRoots\" object (may be empty)"); sys.exit(1)
for i,s in enumerate(screens):
    if not isinstance(s,dict) or not s.get("id"):
        bad(f"screens[{i}] has no id"); f+=1
for k in ("shell","surface"):
    for s in screens:
        if k not in s: bad(f"screen {s.get('id')} has no \"{k}\" key (use null)"); f+=1
if f: sys.exit(1)

on_disk={os.path.basename(p)[:-5] for p in glob.glob(os.path.join(design,"surfaces","*.html"))}-HARNESS
declared=[s["surface"] for s in screens if s.get("surface")]

# (a) resolution — a declared surface with no file is a dangling promise
for s in sorted(set(declared)-on_disk):
    owner=[x['id'] for x in screens if x.get('surface')==s][0]
    bad(f"screen '{owner}' declares surface '{s}' but {rel}/surfaces/{s}.html does not exist"); f+=1
# (b) coverage — a surface nobody claims scaffolds into a view with no identity
for s in sorted(on_disk-set(declared)):
    bad(f"{rel}/surfaces/{s}.html is claimed by no screen in structure.json"); f+=1
# (c) uniqueness — two screens on one surface means one of them is a lie
for s in sorted({x for x in declared if declared.count(x)>1}):
    bad(f"surface '{s}' is claimed by {declared.count(s)} screens"); f+=1
# (d) shell — the prefix convention the scaffolder parses, now asserted
for s in screens:
    surf,sh=s.get("surface"),s.get("shell")
    if surf and not sh: bad(f"screen '{s['id']}' has a surface but no shell"); f+=1
    elif surf and not surf.startswith(sh+"_"):
        bad(f"screen '{s['id']}': surface '{surf}' is not under shell '{sh}'"); f+=1
# (e) roots — a tab whose ROOT screen was excluded ships a tab with no home
byid={s["id"]:s for s in screens}
for tab,sid in sorted(roots.items()):
    if sid not in byid: bad(f"tabRoots['{tab}'] = '{sid}' is not a screen"); f+=1
    elif not byid[sid].get("surface"):
        bad(f"tabRoots['{tab}'] = '{sid}' has no surface — the tab's landing screen was never designed"); f+=1

if f: sys.exit(1)
n=len(screens); c=len(declared)
print(f"  ✓ structure: {n} screens / {c} surfaces / {len({s['shell'] for s in screens if s.get('shell')})} shells, all claimed and resolved")
if n-c: print(f"    ({n-c} screen(s) carry surface:null — designed but not frozen)")
PY
)"
rc=$?
printf '%s\n' "$pyout"
fails="$(printf '%s\n' "$pyout" | grep '^FAIL:' || true)"
[ -n "$fails" ] && printf '%s\n' "$fails" | while IFS= read -r fl; do sarif_result "structure" "error" "$DESIGN_REL/structure.json" "$fl"; done
[ "$rc" -ne 0 ] && F=$((F+1))

[ "$F" -gt 0 ] && { echo "structure: FAIL ($F check group(s))" >&2; exit 1; }
echo "structure: PASS — $DESIGN_REL/structure.json resolves and is in sync."
exit 0
