#!/usr/bin/env bash
# structure.sh — the STRUCTURE gate. Owns the shell/surface MAP: does
# structure.json resolve, is it in sync with the authored registry, and are the
# exclusions accounted for. Split out of the vendored freeze_design.sh (plan 04)
# along the render/structure seam; rewired to the authored registry (plan 05).
#
# Asserts (cheapest first, all must pass):
#   S0  input   — design/structure.json is present and parses (missing input
#                 FAILS — a gate that cannot find its input never passes quietly)
#   S1  drift   — structure.json is regenerated from the authored layer and
#                 compared, then its git tracking state is asserted:
#     S1a content  — emit_structure --check regenerates to memory and diffs
#                    against the on-disk file (catches a hand-edit, a stale
#                    registry, a missing surfaceId, an orphan viewmodel).
#     S1b tracked  — git status --porcelain over structure.json is empty: the
#                    file is committed and current. `git diff --exit-code` CANNOT
#                    see a new file, and a producer that adds a surface is the
#                    expected case — porcelain is the only assertion that holds.
#   S2  resolve — every tabRoot lands on a screen WITH a surface; the reconcile
#                 count is printed, exclusions (surface:null) listed by id.
#
# The registry join (surfaceId -> viewmodel), orphan detection and shell
# derivation live in the EMITTER, not here — the gate asserts the emitter's
# output is current and self-consistent. Findings route through sarif.sh.
#
# Usage: structure.sh [app-root]   (0 pass / 1 FAIL / 2 env)
# $KIT_DESIGN_DIR selects the producer folder (default: design), app-root-relative.
set -uo pipefail

GATE_COMMON="$(cd "$(dirname "$0")/../_common" && pwd)"
# shellcheck source=../_common/sarif.sh
source "$GATE_COMMON/sarif.sh"

APP="${1:-$PWD}"
# pwd -P resolves symlinks (macOS /var -> /private/var) so APP, STRUCTURE and the
# git toplevel all agree on one physical path — otherwise the porcelain prefix
# match silently no-matches and the gate skips its own drift assertion.
APP="$(cd "$APP" 2>/dev/null && pwd -P)" || { echo "FAIL: app root not found: ${1:-$PWD}" >&2; exit 2; }
DESIGN_REL="${KIT_DESIGN_DIR:-design}"
case "$DESIGN_REL" in
  /*) echo "FAIL: KIT_DESIGN_DIR must be relative to the app root, got: $DESIGN_REL" >&2; exit 2 ;;
esac
DESIGN="$APP/$DESIGN_REL"
_rr="$(git -C "$APP" rev-parse --show-toplevel 2>/dev/null || true)"
REPO_ROOT="$(cd "$_rr" 2>/dev/null && pwd -P || echo "$_rr")"

F=0
fail(){ echo "FAIL: $1" >&2; F=$((F+1)); sarif_result "structure" "error" "$DESIGN_REL/structure.json" "$1"; }
ok(){ echo "  ✓ $1"; }

STRUCTURE="$DESIGN/structure.json"
EMIT="$APP/tools/emit_structure/emit_structure.py"
[ -f "$EMIT" ] || EMIT="${REPO_ROOT:-$APP}/tools/emit_structure/emit_structure.py"

# ---- S0: input present ---------------------------------------------------------
if [ ! -f "$STRUCTURE" ]; then
  fail "structure: no $DESIGN_REL/structure.json — the structure gate's input is missing (run emit_structure.py)"
  exit 1
fi

# ---- S1a: content drift (regenerate-to-memory compare) -------------------------
# No jsx/app.jsx guard: the drift check runs for every producer that carries the
# authored registry (models/screens_model/registry.json). The emitter fails loud
# on a missing surfaceId, an orphan viewmodel, an empty tabRoots map, or a stale
# structure.json — all surfaced here as a content mismatch or a build failure.
if [ ! -f "$EMIT" ]; then
  fail "structure: emit_structure.py not found at $EMIT"
else
  pyout="$(python3 "$EMIT" --app "$APP" --design-dir "$DESIGN_REL" --check 2>&1)"
  rc=$?
  printf '%s\n' "$pyout"
  if [ "$rc" -ne 0 ]; then
    fails="$(printf '%s\n' "$pyout" | grep '^FAIL:' || true)"
    [ -n "$fails" ] && printf '%s\n' "$fails" | while IFS= read -r fl; do sarif_result "structure" "error" "$DESIGN_REL/structure.json" "$fl"; done
    fail "structure: $DESIGN_REL/structure.json drifted from the authored registry — re-run emit_structure.py"
  else
    ok "structure: structure.json is in sync with the authored registry"
  fi
fi

# ---- S1b: tracking (porcelain, NEVER git diff --exit-code) ---------------------
# A producer that adds a surface regenerates structure.json; the new/modified file
# must be committed. git diff --exit-code returns 0 for an untracked file (false
# green); git status --porcelain shows ?? for untracked and  M for modified.
if [ -n "$REPO_ROOT" ] && [ -z "${GATE_SKIP_PORCELAIN:-}" ]; then
  case "$STRUCTURE" in
    "$REPO_ROOT"/*)
      rel="${STRUCTURE#$REPO_ROOT/}"
      dirty="$(git -C "$REPO_ROOT" status --porcelain -- "$rel" 2>/dev/null)"
      if [ -n "$dirty" ]; then
        code="${dirty%% *}"; code="${code%%${dirty#? }}"
        case "$dirty" in \?\?*) code="untracked" ;; *) code="modified" ;; esac
        fail "structure: $DESIGN_REL/structure.json is $code — regenerate then commit it (porcelain, not git-diff)"
      else
        ok "structure: structure.json is tracked and committed"
      fi
      ;;
    *)
      echo "  · structure: structure.json sits outside this repo — porcelain tracking skipped" ;;
  esac
else
  echo "  · structure: not a git repo — porcelain tracking skipped"
fi

# ---- S2: resolve + reconcile print --------------------------------------------
# The emitter has already proven every surface joins to a viewmodel and there are
# no orphans (S1a). What remains: tab roots land on a screen WITH a surface (a
# tab whose root was excluded ships a tab with no home), and the human reader sees
# the reconcile count and the exclusion list rather than a silent drop.
pyout="$(python3 - "$DESIGN" "$DESIGN_REL" 2>&1 <<'PY'
import json,sys,os
design,rel=sys.argv[1],sys.argv[2]
def bad(m): print(f"FAIL: structure: {m}")
try: st=json.load(open(os.path.join(design,"structure.json")))
except Exception as e: bad(f"structure.json does not parse — {e}"); sys.exit(1)

screens=st.get("screens"); roots=st.get("tabRoots")
if not isinstance(screens,list) or not screens:
    bad(f"{rel}/structure.json needs a non-empty \"screens\" list"); sys.exit(1)
if not isinstance(roots,dict) or not roots:
    bad(f"{rel}/structure.json needs a non-empty \"tabRoots\" object"); sys.exit(1)

f=0
# tabRoots here carry ROUTES (projects: '/'), not screen ids, so the structural
# question is: does every tab have at least one frozen (non-excluded) screen?
tabs_with_surfaces={s.get("tab") for s in screens if isinstance(s,dict) and s.get("surface")}
for tab in sorted(roots):
    if tab not in tabs_with_surfaces:
        bad(f"tab '{tab}' has no screen with a surface — its landing screen was excluded or never designed"); f+=1
if f: sys.exit(1)

n=len(screens); excl=[s["id"] for s in screens if isinstance(s,dict) and s.get("surface") is None]
frozen=n-len(excl)
print(f"  ✓ structure: {n} screens / {frozen} frozen / {len(excl)} excluded, {len(roots)} tab roots land on a surface")
if excl: print(f"    exclusions (surface:null): {', '.join(excl)}")
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
