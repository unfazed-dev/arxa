#!/usr/bin/env bash
# freeze.sh — the FREEZE / PROTOTYPE gate (plan 04.1): the render half of the
# vendored freeze_design.sh, after the structure checks were split out to the
# structure gate's own folder. Asserts the frozen inputs are present AND that
# every surface renders clean at every active ladder width (every viewport in
# config/app-box.config.json).
#
# Required shape, inside <app>/$KIT_DESIGN_DIR (default: design):
#   tokens.json             DTCG tokens carrying the kit vocabulary
#   design-system.md        the frozen design-system doc
#   exclusions.json         {"globs":[...],"selectors":[...]} — harness chrome
#                           that must NEVER scaffold into kit UI
#   direction-approved.md   gate file: the approved design direction
#   brand-spec.md           gate file: brand tokens/spec in prose
#   structure.json          the shell/surface map (resolution is structure's job;
#                           freeze only asserts it is present as a frozen input)
#   surfaces/*.html         the frozen hi-fi surfaces (>=1)
#
# Checks (cheapest first, all must pass):
#   1. shape      — every required file present
#   2. vocab      — tokens.json parses (DTCG $type/$value) and carries the kit
#                   token paths the translator maps onto the palette
#   3. exclusions — harness chrome signatures found in surfaces are each covered
#                   by an exclusions glob/selector (uncovered = would scaffold)
#   4. render     — headless Chromium: every surface loads with zero console /
#                   page errors at EVERY config viewport; screenshots land under
#                   .kit/state/prototype/evidence/. Backend cascade:
#                   `uv run --with playwright` -> python playwright module;
#                   FREEZE_RENDER=skip skips render for hermetic non-browser runs.
#
# Findings route through gates/_common/sarif.sh (4.2). The console/page-error
# handler is registered on a FRESH page per surface (4.3): handlers can never
# accumulate across surfaces, so each error is reported exactly once.
#
# Usage: freeze.sh [app-root]   (0 pass / 1 FAIL / 2 env)
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
EVIDENCE="$APP/.kit/state/prototype/evidence"
GATE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$GATE_ROOT/config/app-box.config.json"

F=0
fail(){ echo "FAIL: $1" >&2; F=$((F+1)); sarif_result "freeze" "error" "$DESIGN_REL" "$1"; }
ok(){ echo "  ✓ $1"; }

# ---- 0. the design dir itself (anchor) ----
if [ ! -d "$DESIGN" ]; then
  fail "no design dir at $DESIGN — the design SSOT must live at <project-root>/$DESIGN_REL; point the design session's output there, then re-run"
  exit 1
fi

# ---- 1. shape ----
for f in tokens.json design-system.md exclusions.json direction-approved.md brand-spec.md structure.json; do
  if [ -f "$DESIGN/$f" ]; then ok "shape: $f"; else fail "shape: $DESIGN_REL/$f missing (see the prototype freeze contract)"; fi
done
SURFACES="$(ls "$DESIGN"/surfaces/*.html 2>/dev/null)"
if [ -n "$SURFACES" ]; then
  ok "shape: $(printf '%s\n' "$SURFACES" | wc -l | tr -d ' ') surface(s) under $DESIGN_REL/surfaces/"
else
  fail "shape: no surfaces — $DESIGN_REL/surfaces/*.html missing"
fi
[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F shape check(s))" >&2; exit 1; }

# ---- 2. vocab (tokens.json carries the kit token paths) ----
pyout="$(python3 - "$DESIGN/tokens.json" 2>&1 <<'PY'
import json,sys
path=sys.argv[1]
try: d=json.load(open(path))
except Exception as e: print(f"FAIL: vocab: tokens.json does not parse — {e}"); sys.exit(1)
REQUIRED=["color.brand.0","color.bg.surface","color.bg.surface-2","color.bg.paper",
          "color.fg.ink","color.fg.muted","color.fg.faint","color.border.rule",
          "color.status.good","color.status.warn","color.status.danger",
          "typography.sans","typography.mono"]
missing=[]; bad=[]
for p in REQUIRED:
    node=d
    for part in p.split('.'):
        node=node.get(part) if isinstance(node,dict) else None
        if node is None: missing.append(p); break
    else:
        if not (isinstance(node,dict) and "$type" in node and "$value" in node): bad.append(p)
for p in missing: print(f"FAIL: vocab: missing token path {p}")
for p in bad:     print(f"FAIL: vocab: {p} lacks DTCG $type/$value")
if missing or bad: sys.exit(1)
print(f"  ✓ vocab: {len(REQUIRED)} kit token paths present (DTCG)")
PY
)"
rc=$?
printf '%s\n' "$pyout"
fails="$(printf '%s\n' "$pyout" | grep '^FAIL:' || true)"
[ -n "$fails" ] && printf '%s\n' "$fails" | while IFS= read -r fl; do sarif_result "freeze" "error" "$DESIGN_REL/tokens.json" "$fl"; done
[ "$rc" -ne 0 ] && F=$((F+1))

# ---- 3. exclusions: harness chrome must be named, never scaffolded ----
pyout="$(python3 - "$DESIGN" 2>&1 <<'PY'
import json,re,sys,glob,fnmatch,os
design=sys.argv[1]
try: ex=json.load(open(os.path.join(design,"exclusions.json")))
except Exception as e: print(f"FAIL: exclusions: exclusions.json does not parse — {e}"); sys.exit(1)
globs=ex.get("globs",[]); selectors=ex.get("selectors",[])
if not isinstance(globs,list) or not isinstance(selectors,list):
    print('FAIL: exclusions: exclusions.json needs {"globs": [...], "selectors": [...]}'); sys.exit(1)
# harness chrome signatures — the stuff that is NOT product UI: tweak panels,
# device/phone frames, fake status bars (9:41 is the tell), browser-chrome mockups.
SIGS=[r"tweak", r"device[-_ ]?frame", r"phone[-_ ]?frame", r"(?:iphone|android)[-_ ]?frame",
      r"device[-_ ]?bezel", r"9:41", r"status[-_ ]?bar", r"browser[-_ ]?chrome", r"mockup[-_ ]?chrome"]
core=lambda s: re.sub(r"[^a-z0-9]","",s.lower())
sel_cores=[core(s) for s in selectors]
uncovered=[]; covered=0
for html in sorted(glob.glob(os.path.join(design,"surfaces","*.html"))):
    rel=os.path.relpath(html,design)
    for i,line in enumerate(open(html,errors="replace"),1):
        for sig in SIGS:
            if not re.search(sig,line,re.I): continue
            if any(fnmatch.fnmatch(rel,g) or fnmatch.fnmatch(os.path.basename(html),g) for g in globs) \
               or any(c and c in core(line) for c in sel_cores): covered+=1
            else: uncovered.append(f"{rel}:{i} /{sig}/")
for u in uncovered: print(f"FAIL: exclusions: harness chrome present but not excluded — {u} (add to exclusions.json)")
if uncovered: sys.exit(1)
print(f"  ✓ exclusions: {covered} chrome reference(s) covered by exclusions.json")
PY
)"
rc=$?
printf '%s\n' "$pyout"
fails="$(printf '%s\n' "$pyout" | grep '^FAIL:' || true)"
[ -n "$fails" ] && printf '%s\n' "$fails" | while IFS= read -r fl; do sarif_result "freeze" "error" "$DESIGN_REL/exclusions.json" "$fl"; done
[ "$rc" -ne 0 ] && F=$((F+1))
[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F check group(s))" >&2; exit 1; }

# ---- 4. render (headless Chromium; skip via FREEZE_RENDER=skip) ----
# Fresh page per (surface, viewport): the console/pageerror handler is registered
# on each new page, so it can never accumulate across surfaces — each error is
# reported exactly once (4.3).
if [ "${FREEZE_RENDER:-}" = skip ]; then
  echo "  (render pass SKIPPED — FREEZE_RENDER=skip; hermetic/non-browser runs only)"
else
  mkdir -p "$EVIDENCE"
  RENDER_RC=""
  if command -v uv >/dev/null 2>&1; then
    uv run --with playwright python - "$DESIGN" "$EVIDENCE" "$CONFIG" <<'PY'
import sys,threading,functools,http.server,socketserver,os,glob,json
design,evidence,config=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    all_vps=json.load(open(config))["viewports"]
except Exception:
    all_vps={"mobile":{"width":390,"height":844}}
# FREEZE_VIEWPORTS (config-driven, R3): restrict the active widths rendered —
# default is every config viewport ("every active ladder width"); a CI/hermetic
# run may narrow it, e.g. FREEZE_VIEWPORTS=mobile. Unknown names are dropped.
want=os.environ.get("FREEZE_VIEWPORTS","").split()
viewports=[(n,all_vps[n]["width"],all_vps[n]["height"]) for n in all_vps if not want or n in want]
if not viewports:
    print(f"FAIL: render: FREEZE_VIEWPORTS={os.environ.get('FREEZE_VIEWPORTS')} matched no config viewport"); sys.exit(1)
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
srv=socketserver.ThreadingTCPServer(("127.0.0.1",0),functools.partial(Q,directory=design))
port=srv.server_address[1]
threading.Thread(target=srv.serve_forever,daemon=True).start()
from playwright.sync_api import sync_playwright
errors=[]
surfaces=sorted(glob.glob(os.path.join(design,"surfaces","*.html")))
with sync_playwright() as pw:
    b=pw.chromium.launch()
    for vname,vw,vh in viewports:
        for html in surfaces:
            name=os.path.splitext(os.path.basename(html))[0]
            pg=b.new_page(viewport={"width":int(vw),"height":int(vh)})
            msgs=[]
            pg.on("console",lambda m,msgs=msgs: msgs.append(m.text) if m.type=="error" else None)
            pg.on("pageerror",lambda e,msgs=msgs: msgs.append(str(e)))
            pg.goto(f"http://127.0.0.1:{port}/surfaces/{name}.html")
            pg.wait_for_timeout(1200)
            pg.screenshot(path=os.path.join(evidence,f"{name}_{vname}.png"),full_page=True)
            for m in msgs: errors.append(f"{name}@{vname}: {m}")
            pg.close()
            print(f"  ✓ render: {name}.html @ {vname} ({vw}x{vh}) loaded, screenshot -> {evidence}/{name}_{vname}.png")
    b.close()
srv.shutdown()
for e in errors: print(f"FAIL: render: console/page error — {e}")
print(f"  render: {len(surfaces)*len(viewports)} surface/viewport render(s), {len(errors)} error(s)")
sys.exit(1 if errors else 0)
PY
    RENDER_RC=$?
  else
    echo "freeze: ERROR (exit 2) — no render backend. Install one of:" >&2
    echo "  uv (https://docs.astral.sh/uv/)   — freeze uses: uv run --with playwright" >&2
    echo "  pip install playwright && python3 -m playwright install chromium" >&2
    echo "(browsers already cached at ~/Library/Caches/ms-playwright are reused.)" >&2
    echo "Hermetic runs: FREEZE_RENDER=skip freeze.sh ..." >&2
    exit 2
  fi
  [ "$RENDER_RC" -ne 0 ] && F=$((F+1))
fi

[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F check group(s))" >&2; exit 1; }
echo "freeze: PASS — $DESIGN_REL is frozen SSOT material."
exit 0
