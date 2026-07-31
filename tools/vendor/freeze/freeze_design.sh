#!/usr/bin/env bash
# freeze_design.sh — the PROTOTYPE gate (ADR-0010): validate + freeze an app's
# design/ SSOT produced by an external appbox-design session. The deterministic
# half of Human Gate 1; the human half is `pipeline.sh gate prototype --approve`.
#
# The design dir is <app-root>/design/ by default (grill D2) — anchored to the
# app root argument, never cwd-guessed, never inside the kit tree (same leak
# class as the phantom-state guard). $KIT_DESIGN_DIR overrides the `design`
# segment (relative to the app root, e.g. KIT_DESIGN_DIR=design/new): the
# 2026-07-25 producer reorg gave each producer its own self-contained folder, so
# there is now one freezable design root per producer rather than one per repo.
# The anchor property is unchanged — still app-root-relative, still never cwd.
# Required shape, inside whichever dir resolves:
#
#   design/
#     tokens.json             DTCG tokens carrying the kit vocabulary (checked below)
#     design-system.md        the frozen design-system doc
#     exclusions.json         D6: {"globs": [...], "selectors": [...]} — appbox-design
#                             harness chrome (TweaksPanel, device frames, fake
#                             status bars) that must NEVER scaffold into kit UI
#     direction-approved.md   gate file: the approved design direction
#     brand-spec.md           gate file: brand tokens/spec in prose
#     structure.json          the shell/surface map: {"screens":[{id,shell,comp,
#                             shellDir,surface}], "shellRoots":{...}} — emitted by
#                             the producer (design/tools/emit_structure.py) and
#                             checked below. surface:null = designed, not frozen
#     surfaces/*.html         the frozen hi-fi surfaces (≥1)
#
# Checks (cheapest first, all must pass):
#   1. shape     — every required file present
#   2. vocab     — tokens.json parses (DTCG $type/$value) and carries the kit
#                  token paths the translator maps onto kit_colors.dart
#   3. exclusions— appbox-design chrome signatures found in surfaces are each covered
#                  by an exclusions glob/selector (uncovered = would scaffold)
#   4. structure  — structure.json's shell/surface map resolves: every declared
#                   surface has a file, every file is claimed by exactly one
#                   screen, shells match the filename prefix, and no shell root
#                   was left without a surface
#   5. render    — headless Chromium: every surface loads with zero console/
#                  page errors; screenshots land in .kit/state/prototype/evidence/
#                  (backend cascade: `uv run --with playwright` → python
#                  playwright module; FREEZE_RENDER=skip skips for hermetic runs)
#
# Usage:
#   freeze_design.sh [app-root]            validate (exit 0 pass / 1 FAIL / 2 env)
#   freeze_design.sh [app-root] --serve    validate, then serve design/ locally
#                                          for the Human Gate 1 browser review
set -uo pipefail

APP="${1:-$PWD}"; [ "${1:-}" = "--serve" ] && APP="$PWD"
SERVE=0; [ "${2:-}" = "--serve" ] || [ "${1:-}" = "--serve" ] && SERVE=1
APP="$(cd "$APP" 2>/dev/null && pwd)" || { echo "FAIL: app root not found: ${1:-$PWD}" >&2; exit 2; }
# $KIT_DESIGN_DIR must stay app-root-relative: an absolute value would break the
# anchoring guarantee above (and every path this gate prints is app-relative).
DESIGN_REL="${KIT_DESIGN_DIR:-design}"
case "$DESIGN_REL" in
  /*) echo "FAIL: KIT_DESIGN_DIR must be relative to the app root, got: $DESIGN_REL" >&2; exit 2 ;;
esac
DESIGN="$APP/$DESIGN_REL"
EVIDENCE="$APP/.kit/state/prototype/evidence"
# viewport dimensions are config-driven (R3: config/appbox.config.json viewports.mobile),
# not the 390×844 literal. Falls back only if config is absent.
GATE_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
VWVH="$(python3 -c "import json;d=json.load(open('$GATE_ROOT/config/appbox.config.json'));v=d['viewports']['mobile'];print(v['width'],v['height'])" 2>/dev/null || echo "390 844")"
VW="${VWVH%% *}"; VH="${VWVH##* }"
F=0
fail(){ echo "FAIL: $1" >&2; F=$((F+1)); }
ok(){ echo "  ✓ $1"; }

# ---- 0. the design dir itself (D2 anchor) ----
if [ ! -d "$DESIGN" ]; then
  echo "FAIL: no design dir at $DESIGN" >&2
  echo "     the design SSOT must live at <project-root>/$DESIGN_REL (grill D2) —" >&2
  echo "     point the appbox-design session's output there, then re-run." >&2
  exit 1
fi

# ---- 1. shape ----
for f in tokens.json design-system.md exclusions.json direction-approved.md brand-spec.md structure.json; do
  [ -f "$DESIGN/$f" ] && ok "shape: $f" || fail "shape: $DESIGN_REL/$f missing (see skills/_pipeline.md §prototype)"
done
SURFACES="$(ls "$DESIGN"/surfaces/*.html 2>/dev/null)"
[ -n "$SURFACES" ] && ok "shape: $(printf '%s\n' "$SURFACES" | wc -l | tr -d ' ') surface(s) under $DESIGN_REL/surfaces/" \
  || fail "shape: no surfaces — $DESIGN_REL/surfaces/*.html missing"
[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F shape check(s))" >&2; exit 1; }

# ---- 2. vocab (tokens.json carries the kit token paths) ----
python3 - "$DESIGN/tokens.json" <<'PY'
import json,sys
path=sys.argv[1]
try: d=json.load(open(path))
except Exception as e: print(f"FAIL: vocab: tokens.json does not parse — {e}",file=sys.stderr); sys.exit(1)
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
for p in missing: print(f"FAIL: vocab: missing token path {p}",file=sys.stderr)
for p in bad:     print(f"FAIL: vocab: {p} lacks DTCG $type/$value",file=sys.stderr)
if missing or bad: sys.exit(1)
print(f"  ✓ vocab: {len(REQUIRED)} kit token paths present (DTCG)")
PY
[ $? -ne 0 ] && F=$((F+1))

# ---- 3. exclusions (D6): appbox-design chrome must be named, never scaffolded ----
python3 - "$DESIGN" <<'PY'
import json,re,sys,glob,fnmatch,os
design=sys.argv[1]
try: ex=json.load(open(os.path.join(design,"exclusions.json")))
except Exception as e: print(f"FAIL: exclusions: exclusions.json does not parse — {e}",file=sys.stderr); sys.exit(1)
globs=ex.get("globs",[]); selectors=ex.get("selectors",[])
if not isinstance(globs,list) or not isinstance(selectors,list):
    print("FAIL: exclusions: exclusions.json needs {\"globs\": [...], \"selectors\": [...]}",file=sys.stderr); sys.exit(1)
# appbox-design harness chrome signatures — the stuff that is NOT product UI (D6):
# tweak panels, device/phone frames, fake iOS status bars (9:41 is the tell),
# browser-chrome mockups.
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
for u in uncovered: print(f"FAIL: exclusions: appbox-design chrome present but not excluded — {u} (add to exclusions.json)",file=sys.stderr)
if uncovered: sys.exit(1)
print(f"  ✓ exclusions: {covered} chrome reference(s) covered by exclusions.json (D6)")
PY
[ $? -ne 0 ] && F=$((F+1))
[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F check group(s))" >&2; exit 1; }

# ---- 4. structure: the shell/surface map the scaffolder used to guess ----
# Everything downstream of this gate needs to know which shell a surface belongs
# to, which registry screens have no surface at all, and whether every surface on
# disk is actually claimed. None of that was ever asked for, so the scaffolder
# re-invented it (filename prefixes, eyeballed HTML) and the shell/review gates
# argued about the result. structure.json carries it; these five assertions are
# what make carrying it worth anything.
#
# There is deliberately no "excluded" list to pad: a screen with surface:null IS
# the exclusion, and roots/ resolution below still bite it.
#
# Drift first: the assertions below compare structure.json to surfaces/ on disk,
# which cannot catch a registry screen ADDED after the last emit — that lands as
# a file nobody wrote, so nothing contradicts. For a producer with a registry the
# emitter is the arbiter, so re-derive and compare. (Unlike emit_playground this
# needs no browser, so it is safe to run inside the gate.) A producer with no
# jsx/ has no second source to drift from: there, coverage (b) IS the drift check.
FREEZE_TOOLS="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DESIGN/jsx/app.jsx" ] && [ -x "$FREEZE_TOOLS/emit_structure/emit_structure.py" ]; then
  if python3 "$FREEZE_TOOLS/emit_structure/emit_structure.py" \
       --app "$APP" --design-dir "$DESIGN_REL" --check >/dev/null 2>&1; then
    ok "structure: structure.json is in sync with $DESIGN_REL/jsx/app.jsx"
  else
    fail "structure: $DESIGN_REL/structure.json drifted from jsx/app.jsx — re-run tools/emit_structure/emit_structure.py"
  fi
fi
python3 - "$DESIGN" "$DESIGN_REL" <<'PY'
import json,sys,os,glob
design,rel=sys.argv[1],sys.argv[2]
HARNESS={"index"}   # the harness page, not a product surface
def bad(m): print(f"FAIL: structure: {m}",file=sys.stderr)
try: st=json.load(open(os.path.join(design,"structure.json")))
except Exception as e: bad(f"structure.json does not parse — {e}"); sys.exit(1)

f=0
screens=st.get("screens"); roots=st.get("shellRoots")
if not isinstance(screens,list) or not screens:
    bad(f"{rel}/structure.json needs a non-empty \"screens\" list"); sys.exit(1)
if not isinstance(roots,dict):
    bad(f"{rel}/structure.json needs a \"shellRoots\" object (may be empty)"); sys.exit(1)
for i,s in enumerate(screens):
    if not isinstance(s,dict) or not s.get("id"):
        bad(f"screens[{i}] has no id"); f+=1
for k in ("shell","shellDir","surface"):
    for s in screens:
        if k not in s: bad(f"screen {s.get('id')} has no \"{k}\" key (use null)"); f+=1
if f: sys.exit(1)

on_disk={os.path.basename(p)[:-5] for p in glob.glob(os.path.join(design,"surfaces","*.html"))}-HARNESS
declared=[s["surface"] for s in screens if s.get("surface")]

# (a) resolution — a declared surface that has no file is a dangling promise
for s in sorted(set(declared)-on_disk):
    bad(f"screen '{[x['id'] for x in screens if x.get('surface')==s][0]}' declares surface '{s}' but {rel}/surfaces/{s}.html does not exist"); f+=1
# (b) coverage — a surface nobody claims scaffolds into a view with no identity
for s in sorted(on_disk-set(declared)):
    bad(f"{rel}/surfaces/{s}.html is claimed by no screen in structure.json"); f+=1
# (c) uniqueness — two screens on one surface means one of them is a lie
for s in sorted({x for x in declared if declared.count(x)>1}):
    bad(f"surface '{s}' is claimed by {declared.count(s)} screens"); f+=1
# (d) shellDir — the prefix convention the scaffolder parses, now asserted
for s in screens:
    surf,sh=s.get("surface"),s.get("shellDir")
    if surf and not sh: bad(f"screen '{s['id']}' has a surface but no shell"); f+=1
    elif surf and not surf.startswith(sh+"_"):
        bad(f"screen '{s['id']}': surface '{surf}' is not under shell '{sh}'"); f+=1
# (e) roots — a shell whose ROOT screen was excluded ships a shell with no home
byid={s["id"]:s for s in screens}
for shell,sid in sorted(roots.items()):
    if sid not in byid: bad(f"shellRoots['{shell}'] = '{sid}' is not a screen"); f+=1
    elif not byid[sid].get("surface"):
        bad(f"shellRoots['{shell}'] = '{sid}' has no surface — the shell's landing screen was never designed"); f+=1

if f: sys.exit(1)
n=len(screens); c=len(declared)
print(f"  ✓ structure: {n} screens / {c} surfaces / {len({s['shell'] for s in screens if s.get('shell')})} shells, all claimed and resolved")
if n-c: print(f"    ({n-c} screen(s) carry surface:null — designed but not frozen)")
PY
[ $? -ne 0 ] && F=$((F+1))
[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F check(s) before render)" >&2; exit 1; }

# ---- 5. render (headless Chromium; skip via FREEZE_RENDER=skip) ----
if [ "${FREEZE_RENDER:-}" = skip ]; then
  echo "  (render pass SKIPPED — FREEZE_RENDER=skip; hermetic/CI runs only)"
else
  mkdir -p "$EVIDENCE"
  RENDER_RC=""
  if command -v uv >/dev/null 2>&1; then
    uv run --with playwright python - "$DESIGN" "$EVIDENCE" "$VW" "$VH" <<'PY'
import sys,threading,functools,http.server,socketserver,os,glob
design,evidence,vw,vh=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
srv=socketserver.ThreadingTCPServer(("127.0.0.1",0),functools.partial(Q,directory=design))
port=srv.server_address[1]
threading.Thread(target=srv.serve_forever,daemon=True).start()
from playwright.sync_api import sync_playwright
errors=[]
with sync_playwright() as pw:
    b=pw.chromium.launch()
    pg=b.new_page(viewport={"width":int(vw),"height":int(vh)})
    for html in sorted(glob.glob(os.path.join(design,"surfaces","*.html"))):
        name=os.path.splitext(os.path.basename(html))[0]
        msgs=[]
        pg.on("console",lambda m,msgs=msgs: msgs.append(m.text) if m.type=="error" else None)
        pg.on("pageerror",lambda e,msgs=msgs: msgs.append(str(e)))
        pg.goto(f"http://127.0.0.1:{port}/surfaces/{name}.html")
        pg.wait_for_timeout(1500)
        pg.screenshot(path=os.path.join(evidence,f"{name}.png"),full_page=True)
        for m in msgs: errors.append(f"{name}: {m}")
        print(f"  ✓ render: {name}.html loaded, screenshot → {evidence}/{name}.png")
    b.close()
srv.shutdown()
for e in errors: print(f"FAIL: render: console/page error — {e}",file=sys.stderr)
sys.exit(1 if errors else 0)
PY
    RENDER_RC=$?
  elif python3 -c "import playwright" 2>/dev/null; then
    python3 - "$DESIGN" "$EVIDENCE" "$VW" "$VH" <<'PY'
import sys,threading,functools,http.server,socketserver,os,glob
design,evidence,vw,vh=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
srv=socketserver.ThreadingTCPServer(("127.0.0.1",0),functools.partial(Q,directory=design))
port=srv.server_address[1]
threading.Thread(target=srv.serve_forever,daemon=True).start()
from playwright.sync_api import sync_playwright
errors=[]
with sync_playwright() as pw:
    b=pw.chromium.launch()
    pg=b.new_page(viewport={"width":int(vw),"height":int(vh)})
    for html in sorted(glob.glob(os.path.join(design,"surfaces","*.html"))):
        name=os.path.splitext(os.path.basename(html))[0]
        msgs=[]
        pg.on("console",lambda m,msgs=msgs: msgs.append(m.text) if m.type=="error" else None)
        pg.on("pageerror",lambda e,msgs=msgs: msgs.append(str(e)))
        pg.goto(f"http://127.0.0.1:{port}/surfaces/{name}.html")
        pg.wait_for_timeout(1500)
        pg.screenshot(path=os.path.join(evidence,f"{name}.png"),full_page=True)
        for m in msgs: errors.append(f"{name}: {m}")
        print(f"  ✓ render: {name}.html loaded, screenshot → {evidence}/{name}.png")
    b.close()
srv.shutdown()
for e in errors: print(f"FAIL: render: console/page error — {e}",file=sys.stderr)
sys.exit(1 if errors else 0)
PY
    RENDER_RC=$?
  else
    echo "freeze: ERROR (exit 2) — no render backend. Install one of:" >&2
    echo "  uv (https://docs.astral.sh/uv/)   — freeze uses: uv run --with playwright" >&2
    echo "  pip install playwright && python3 -m playwright install chromium" >&2
    echo "(browsers already cached at ~/Library/Caches/ms-playwright are reused.)" >&2
    echo "Hermetic runs: FREEZE_RENDER=skip freeze_design.sh ..." >&2
    exit 2
  fi
  [ "$RENDER_RC" -ne 0 ] && F=$((F+1))
fi

[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F check group(s))" >&2; exit 1; }
echo "freeze: PASS — $DESIGN is frozen SSOT material."

# ---- Human Gate 1 serve (D5): validate green, then hand the human a browser ----
if [ "$SERVE" = 1 ]; then
  PORT="${FREEZE_SERVE_PORT:-8471}"
  URL="http://localhost:$PORT/surfaces/"
  echo ">> serving $DESIGN at $URL (Ctrl+C stops)"
  command -v open >/dev/null 2>&1 && (sleep 1; open "$URL") &
  exec python3 -m http.server "$PORT" -d "$DESIGN"
fi
exit 0
