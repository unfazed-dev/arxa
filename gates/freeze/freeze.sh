#!/usr/bin/env bash
# ⚠️ SUPERSEDED (2026-07-31, commit 4f9c458): this bash freeze gate is
# superseded by the Dart freeze gate — `dart run bin/appbox.dart gate freeze`
# (or `appbox gate freeze`) in appboxd/ (appboxd/lib/gate_freeze.dart).
# Retained for reference only; it is silently broken because its htmx path
# uses the archived skills/appbox-designer/runtime/serve.mjs (render_htmx.mjs).
#
# freeze.sh — the FREEZE / PROTOTYPE gate (plan 04.1): the render half of the
# vendored freeze_design.sh, after the structure checks were split out to the
# structure gate's own folder. Asserts the frozen inputs are present AND that
# every surface renders clean at every DERIVED width — the viewport set implied
# by --targets via pipeline/state/targets.derivation.json (6.4). Widths come
# ONLY from config/appbox.config.json (R3); there are no viewport literals here.
#
# Targets (6.2/6.3): pass --targets ios,android explicitly for a deterministic
# gate/golden run; with no flag, targets are read from pipeline state (the live
# SSOT). An unknown target, or no targets at all, fails loudly.
#
# Design-approval invalidation (6.7): `--approve` mints design/approval.lock
# stamping the current targets + a hash of the frozen inputs. A later run
# re-checks it; if targets or inputs changed since approval the gate FAILS
# loudly (the frozen design no longer covers the deliverable).
#
# Hash-bound approval (§6): on PASS the gate records a sha256 of the whole
# design tree (gates/_common/design_hash.sh) into state.designHash (live state
# only — the tracked seed is read-only). The design-consuming gates
# (structure/scaffold/coverage) re-check it via
# gates/_common/assert_design_fresh.sh and FAIL if the design moved.
#
# Required shape, inside <app>/$KIT_DESIGN_DIR (default: design). TWO producer
# contracts share this gate (the producer-shape seam, dogfood P14 finding #1),
# detected by app.routes.js at the design root (htmx) vs surfaces/*.html+tokens
# (stacked_kit):
#
#   stacked_kit producer:
#     tokens.json design-system.md exclusions.json direction-approved.md
#     brand-spec.md structure.json surfaces/*.html (>=1)
#
#   htmx producer (appbox-designer):
#     app.routes.js structure.json models/screens_model/registry.json
#     ui/views/**/*_view.html (>=1) — Jinja templates served dynamically
#
# Checks (cheapest first, all must pass):
#   1. shape      — every required input present (per producer)
#   2. vocab      — [stacked_kit] tokens.json parses (DTCG $type/$value) and
#                   carries the kit token paths. N/A for htmx (no tokens.json).
#   3. exclusions — [stacked_kit] harness chrome in surfaces is covered by an
#                   exclusions entry. N/A for htmx.
#   3b. l10n      — [only when <design>/l10n/ exists] every locale ARB carries
#                   exactly the app_en.arb template's key set (@-prefixed
#                   metadata ignored) AND, per key, the same {placeholder}
#                   token set. A missing key or a drifted placeholder is a
#                   runtime lookup crash in the generated app's gen-l10n code.
#   4. render     — headless Chromium: every surface (stacked_kit: each
#                   surfaces/*.html file; htmx: each GET route from app.routes.js)
#                   loads with zero console / page errors at EVERY config viewport;
#                   screenshots land under .kit/state/prototype/evidence/. When
#                   <design>/l10n/ exists the htmx render adds a locale
#                   dimension: each GET route × viewport × locale (derived from
#                   the app_*.arb names, qps-ploc excluded — pseudolocale is
#                   tester-side layout stress), the locale passed as
#                   ?lang=<locale> on the route URL and stamped on the
#                   screenshot name. The
#                   htmx render is served by the designer's Node prototype server
#                   (serve.mjs, loopback, OS-assigned port) and rendered via the
#                   runtime's Playwright (render_htmx.mjs); P09: gates MAY use Node.
#                   stacked_kit render backend: `uv run --with playwright`.
#                   FREEZE_RENDER=skip skips render for hermetic non-browser runs.
#
# Findings route through gates/_common/sarif.sh (4.2). The console/page-error
# handler is registered on a FRESH page per surface (4.3): handlers can never
# accumulate across surfaces, so each error is reported exactly once.
#
# Usage: freeze.sh [--targets ios,android] [--approve] [app-root]   (0 pass / 1 FAIL / 2 env)
# --targets      explicit target set (6.3); absent => read from pipeline state (6.2)
# --approve      mint/refresh design/approval.lock against the current targets+inputs (6.7)
# $KIT_DESIGN_DIR selects the producer folder (default: design), app-root-relative.
set -uo pipefail

GATE_COMMON="$(cd "$(dirname "$0")/../_common" && pwd)"
# shellcheck source=../_common/sarif.sh
source "$GATE_COMMON/sarif.sh"
# shellcheck source=../_common/state_reader.sh
source "$GATE_COMMON/state_reader.sh"
# state_reader.sh enables `set -e`; gates run WITHOUT it (a failed check is a
# recorded status, not an abort — see pipeline.sh). Re-assert the gate's mode.
set -uo pipefail
set +e

# ---- args: --targets (explicit, 6.3) / --approve (mint approval stamp, 6.7) --
# Targets live in STATE for a live run (6.2); gate + golden runs pass them
# explicitly so the snapshot is deterministic — ambient state in a
# reproducibility run is the stale-green defect (6.3).
APPBOX_TARGETS=""
APPROVE=0
APP="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --targets) APPBOX_TARGETS="$2"; shift 2 ;;
    --approve) APPROVE=1; shift ;;
    --*) echo "FAIL: unknown flag: $1" >&2; exit 2 ;;
    *) APP="$1"; shift ;;
  esac
done
APP="$(cd "$APP" 2>/dev/null && pwd)" || { echo "FAIL: app root not found" >&2; exit 2; }
DESIGN_REL="${KIT_DESIGN_DIR:-design}"
case "$DESIGN_REL" in
  /*) echo "FAIL: KIT_DESIGN_DIR must be relative to the app root, got: $DESIGN_REL" >&2; exit 2 ;;
esac
DESIGN="$APP/$DESIGN_REL"
EVIDENCE="$APP/.kit/state/prototype/evidence"
GATE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$GATE_ROOT/config/appbox.config.json"
DERIVATION="$GATE_ROOT/pipeline/state/targets.derivation.json"

# resolve targets: explicit flag, else ambient pipeline state (6.2)
if [ -z "$APPBOX_TARGETS" ]; then
  APPBOX_TARGETS="$(state_targets 2>/dev/null | paste -sd ',' -)"
fi
if [ -z "$APPBOX_TARGETS" ]; then
  echo "FAIL: no --targets given and no targets in pipeline state — pass --targets explicitly (6.3); a reproducibility run that reads ambient state is the stale-green defect" >&2
  exit 1
fi

# derive the ordered viewport set (names) for these targets from the derivation
# table + config. Widths come ONLY from config (R3); never literals here.
DERIVED_VPS="$(python3 - "$APPBOX_TARGETS" "$DERIVATION" "$CONFIG" <<'PY'
import json,sys
targets=[t for t in sys.argv[1].split(',') if t]
tbl=json.load(open(sys.argv[2]))["targets"]
cfg_vps=json.load(open(sys.argv[3]))["viewports"]
unknown=[t for t in targets if t not in tbl]
if unknown:
    print(f"FAIL: unknown target(s): {', '.join(unknown)} — add an entry to pipeline/state/targets.derivation.json"); sys.exit(1)
def vps_of(t, seen=None):
    seen=seen or set()
    if t in seen: return []
    seen.add(t)
    e=tbl[t]; out=list(e.get("viewports",[]))
    if e.get("inherits"): out=vps_of(e["inherits"],seen)+out
    return out
union=[]
for t in targets:
    for v in vps_of(t):
        if v not in union: union.append(v)
ordered=[v for v in cfg_vps if v in union]   # config order; unknown names dropped
print(" ".join(ordered))
PY
)" || true
case "$DERIVED_VPS" in
  FAIL:*) echo "$DERIVED_VPS" >&2; exit 1 ;;
esac
[ -z "$DERIVED_VPS" ] && { echo "FAIL: could not derive viewports from targets ($APPBOX_TARGETS)" >&2; exit 1; }

F=0
fail(){ echo "FAIL: $1" >&2; F=$((F+1)); sarif_result "freeze" "error" "$DESIGN_REL" "$1"; }
ok(){ echo "  ✓ $1"; }

# ---- 0. the design dir itself (anchor) ----
if [ ! -d "$DESIGN" ]; then
  fail "no design dir at $DESIGN — the design SSOT must live at <project-root>/$DESIGN_REL; point the design session's output there, then re-run"
  exit 1
fi

# ---- 0b. producer shape (the producer-shape seam, dogfood P14 finding #1) ----
# Two producer contracts share this gate:
#   stacked_kit: surfaces/*.html + tokens.json + 4 docs (the vendored origin)
#   htmx:        app.routes.js + registry.json + ui/views/**/*_view.html, served
#                dynamically by the designer's Node prototype server (serve.mjs).
# Detection mirrors serve.mjs itself: app.routes.js at the design root is the
# htmx signal. The htmx render goes through the designer server (its views are
# Jinja templates, not standalone files); stacked_kit renders files directly.
if [ -f "$DESIGN/app.routes.js" ]; then
  PRODUCER=htmx
  ok "shape: htmx producer (app.routes.js present) — render via the designer Node server"
else
  PRODUCER=stacked_kit
fi

# ---- 1. shape (per producer) ----
if [ "$PRODUCER" = htmx ]; then
  # htmx frozen inputs: the route map, the shell/surface map, the registry SSOT,
  # and the view templates. No tokens.json/exclusions/docs — those stacked_kit
  # artifacts have no htmx analog; the htmx "clean render" check (step 4) replaces
  # vocab/exclusions.
  for f in app.routes.js structure.json; do
    if [ -f "$DESIGN/$f" ]; then ok "shape: $f"; else fail "shape: $DESIGN_REL/$f missing (htmx producer)"; fi
  done
  # the registry path is recorded in structure.json; fall back to the designer default
  REG_REL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("registry") or "models/screens_model/registry.json")' "$DESIGN/structure.json" 2>/dev/null || echo models/screens_model/registry.json)"
  if [ -f "$DESIGN/$REG_REL" ]; then ok "shape: $REG_REL"; else fail "shape: $DESIGN_REL/$REG_REL missing (registry SSOT for the screen model)"; fi
  VIEWS_COUNT="$(find "$DESIGN/ui/views" -type f -name '*_view.html' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${VIEWS_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    ok "shape: $VIEWS_COUNT view template(s) under $DESIGN_REL/ui/views/"
  else
    fail "shape: no view templates — $DESIGN_REL/ui/views/**/*_view.html missing"
  fi
else
  for f in tokens.json design-system.md exclusions.json direction-approved.md brand-spec.md structure.json; do
    if [ -f "$DESIGN/$f" ]; then ok "shape: $f"; else fail "shape: $DESIGN_REL/$f missing (see the prototype freeze contract)"; fi
  done
  SURFACES="$(ls "$DESIGN"/surfaces/*.html 2>/dev/null)"
  if [ -n "$SURFACES" ]; then
    ok "shape: $(printf '%s\n' "$SURFACES" | wc -l | tr -d ' ') surface(s) under $DESIGN_REL/surfaces/"
  else
    fail "shape: no surfaces — $DESIGN_REL/surfaces/*.html missing"
  fi
fi
[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F shape check(s))" >&2; exit 1; }

# ---- 1b. design-approval invalidation (6.7) --------------------------------
# The approval stamp records the targets + a hash of the frozen inputs it was
# minted against. Adding a target after approval changes the deliverable's
# width set, so the approval MUST go stale, loudly. This block VALIDATES an
# existing stamp; `--approve` mints it at the END of the gate, only after every
# check has passed (a broken design cannot be approved).
APPROVAL_LOCK="$DESIGN/approval.lock"
LOCK_HASH="$(python3 - "$DESIGN" "$APPBOX_TARGETS" "$PRODUCER" <<'PY'
import sys,hashlib,glob,os,json
design,targets,producer=sys.argv[1],sys.argv[2],sys.argv[3]
h=hashlib.sha256()
h.update(",".join(sorted(t for t in targets.split(',') if t)).encode())
if producer=="htmx":
    # the htmx frozen inputs: route map + structure + the registry it points at
    # + every view template under ui/views. The registry path lives in
    # structure.json's "registry" field (designer default if absent).
    reg="models/screens_model/registry.json"
    try: reg=json.load(open(os.path.join(design,"structure.json"))).get("registry") or reg
    except Exception: pass
    for f in ("app.routes.js","structure.json",reg):
        p=os.path.join(design,f); h.update(f.encode()); h.update(open(p,"rb").read() if os.path.isfile(p) else b"")
    for v in sorted(glob.glob(os.path.join(design,"ui","views","**","*_view.html"),recursive=True)):
        h.update(open(v,"rb").read())
else:
    for f in ("tokens.json","design-system.md","exclusions.json",
              "direction-approved.md","brand-spec.md","structure.json"):
        p=os.path.join(design,f)
        h.update(f.encode()); h.update(open(p,"rb").read() if os.path.isfile(p) else b"")
    for s in sorted(glob.glob(os.path.join(design,"surfaces","*.html"))):
        h.update(open(s,"rb").read())
print(h.hexdigest())
PY
)"
if [ -f "$APPROVAL_LOCK" ]; then
  stale="$(python3 - "$APPROVAL_LOCK" "$APPBOX_TARGETS" "$LOCK_HASH" <<'PY'
import json,sys
lock=json.load(open(sys.argv[1])); cur=set(t for t in sys.argv[2].split(',') if t)
if set(lock.get("targets",[]))!=cur:
    print(f"targets changed since approval (approved {lock.get('targets')}; now {sorted(cur)})")
elif lock.get("inputsHash")!=sys.argv[3]:
    print("frozen inputs changed since approval (re-mint with --approve)")
PY
)"
  if [ -n "$stale" ]; then
    fail "approval STALE — $stale; the frozen design no longer covers the deliverable. Re-approve: freeze.sh --targets $APPBOX_TARGETS --approve"
  else
    ok "approval: $DESIGN_REL/approval.lock valid (targets=$APPBOX_TARGETS)"
  fi
else
  echo "  (approval: no $DESIGN_REL/approval.lock — run 'freeze.sh --targets $APPBOX_TARGETS --approve' to mint the stamp)"
fi

# ---- 2/3. vocab + exclusions (stacked_kit only) ----
# These frozen artifacts belong to the stacked_kit producer. The htmx producer
# has no tokens.json/exclusions.json — its "clean vocab" is the rendered-routes
# check in step 4 (every route loads with zero console/page errors).
if [ "$PRODUCER" = stacked_kit ]; then

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

else
  ok "vocab/exclusions: N/A for the htmx producer (no tokens.json/exclusions.json; the render check in step 4 is the htmx analog)"
fi
[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F check group(s))" >&2; exit 1; }

# ---- 3b. l10n parity (only when the design carries an l10n/ catalog) --------
# app_en.arb is the template; every other locale ARB (incl. the generated
# app_qps-ploc.arb) must carry exactly its key set (@-prefixed metadata keys
# ignored) and, per key, the same {placeholder} token set. A missing key or a
# drifted placeholder is a runtime lookup crash in the generated app's gen-l10n
# code — catch it at freeze, not in the built app.
if [ -d "$DESIGN/l10n" ]; then
pyout="$(python3 - "$DESIGN/l10n" 2>&1 <<'PY'
import json,sys,glob,os,re
l10n=sys.argv[1]
tmpl_path=os.path.join(l10n,"app_en.arb")
if not os.path.isfile(tmpl_path):
    print("FAIL: l10n: app_en.arb (the template catalog) missing under l10n/"); sys.exit(1)
try: tmpl=json.load(open(tmpl_path))
except Exception as e: print(f"FAIL: l10n: app_en.arb does not parse — {e}"); sys.exit(1)
def keys(d): return {k for k in d if not k.startswith("@")}
def tokens(v): return set(re.findall(r"\{(\w+)\}", v)) if isinstance(v,str) else set()
tkeys=keys(tmpl)
bad=False; n=0
for path in sorted(glob.glob(os.path.join(l10n,"*.arb"))):
    name=os.path.basename(path)
    if name=="app_en.arb": continue
    try: loc=json.load(open(path))
    except Exception as e: print(f"FAIL: l10n: {name} does not parse — {e}"); bad=True; continue
    n+=1
    lkeys=keys(loc)
    missing=tkeys-lkeys; extra=lkeys-tkeys
    if missing: print(f"FAIL: l10n: {name} missing key(s): {sorted(missing)}"); bad=True
    if extra:   print(f"FAIL: l10n: {name} has extra key(s) not in the template: {sorted(extra)}"); bad=True
    for k in sorted(tkeys & lkeys):
        tt,lt=tokens(tmpl[k]),tokens(loc[k])
        if tt!=lt:
            print(f"FAIL: l10n: {name} key '{k}' placeholder drift — template {sorted(tt)} vs locale {sorted(lt)}"); bad=True
if bad: sys.exit(1)
print(f"  ✓ l10n: {n} locale catalog(s) at key + placeholder parity with app_en.arb ({len(tkeys)} keys)")
PY
)"
rc=$?
printf '%s\n' "$pyout"
fails="$(printf '%s\n' "$pyout" | grep '^FAIL:' || true)"
[ -n "$fails" ] && printf '%s\n' "$fails" | while IFS= read -r fl; do sarif_result "freeze" "error" "$DESIGN_REL/l10n" "$fl"; done
[ "$rc" -ne 0 ] && F=$((F+1))
fi
[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F check group(s))" >&2; exit 1; }

# ---- 4. render (headless Chromium; skip via FREEZE_RENDER=skip) ----
# Fresh page per (surface, viewport): the console/pageerror handler is registered
# on each new page, so it can never accumulate across surfaces — each error is
# reported exactly once (4.3). Viewports rendered = the DERIVED set for these
# targets (6.4); widths come ONLY from config (R3), never literals.
if [ "${FREEZE_RENDER:-}" = skip ]; then
  echo "  (render pass SKIPPED — FREEZE_RENDER=skip; hermetic/non-browser runs only)"
  echo "  (derived widths for targets [$APPBOX_TARGETS]: $DERIVED_VPS)"
else
  mkdir -p "$EVIDENCE"
  if [ "$PRODUCER" = htmx ]; then
    # htmx render: the views are Jinja templates served by the designer's Node
    # prototype server (serve.mjs), so they cannot be opened as files. Render
    # every GET route at every derived width via the runtime's Playwright, with
    # the console/page-error count asserted exact (4.3 — fresh page per route is
    # preserved structurally in render_htmx.mjs).
    if ! command -v node >/dev/null 2>&1; then
      echo "freeze: ERROR (exit 2) — htmx render needs Node (the designer runtime), not found on PATH" >&2
      echo "  the htmx producer is served and rendered by Node; install Node, or FREEZE_RENDER=skip for a hermetic run" >&2
      exit 2
    fi
    RUNTIME="$GATE_ROOT/skills/appbox-designer/runtime"
    SERVE_MJS="$RUNTIME/serve.mjs"
    RENDER_DRIVER="$(cd "$(dirname "$0")" && pwd)/render_htmx.mjs"
    # Locale dimension (3b's render half): when the design carries l10n/, every
    # GET route renders once per locale — derived from the app_*.arb names;
    # qps-ploc excluded (pseudolocale is tester-side layout stress, not a freeze
    # render). The driver appends ?lang=<locale> to the route URL and stamps
    # the locale on the screenshot name. Empty = single render, no ?lang.
    LOCALES=""
    if [ -d "$DESIGN/l10n" ]; then
      LOCALES="$(python3 - "$DESIGN/l10n" <<'PY'
import glob,os,re,sys
locs=[]
for p in sorted(glob.glob(os.path.join(sys.argv[1],"app_*.arb"))):
    m=re.match(r"app_(.+)\.arb$", os.path.basename(p))
    if m and not m.group(1).startswith("qps"): locs.append(m.group(1))
print(",".join(locs))
PY
)"
    fi
    VPS_JSON="$(python3 - "$CONFIG" "$DERIVED_VPS" <<'PY'
import json,sys
cfg=json.load(open(sys.argv[1]))["viewports"]; want=set(sys.argv[2].split())
print(json.dumps([{"name":n,"width":v["width"],"height":v["height"]} for n,v in cfg.items() if n in want]))
PY
)"
    _td="$(mktemp -d)"
    node "$SERVE_MJS" "$DESIGN" --port 0 --host 127.0.0.1 --json >"$_td/ready" 2>"$_td/err" &
    _serve_pid=$!
    _base=""
    for _ in $(seq 1 120); do
      grep -q '"port"' "$_td/ready" 2>/dev/null && { _base="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["url"])' "$_td/ready")"; break; }
      kill -0 "$_serve_pid" 2>/dev/null || break
      sleep 0.1
    done
    if [ -z "$_base" ]; then
      echo "FAIL: render: designer server did not start — $(cat "$_td/err" 2>/dev/null)" >&2
      sarif_result "freeze" "error" "$DESIGN_REL/app.routes.js" "designer server did not start"
      F=$((F+1))
    else
      node "$RENDER_DRIVER" "$DESIGN" "$_base" "$EVIDENCE" "$VPS_JSON" "$RUNTIME" "$LOCALES" || F=$((F+1))
    fi
    kill "$_serve_pid" >/dev/null 2>&1 || true
    wait "$_serve_pid" 2>/dev/null || true
    rm -rf "$_td"
  else
  RENDER_RC=""
  if command -v uv >/dev/null 2>&1; then
    uv run --with playwright python - "$DESIGN" "$EVIDENCE" "$CONFIG" "$DERIVED_VPS" <<'PY'
import sys,threading,functools,http.server,socketserver,os,glob,json
design,evidence,config,derived=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
all_vps=json.load(open(config))["viewports"]
# only the derived viewport set for these targets (6.4); unknown names dropped.
want=set(derived.split())
viewports=[(n,all_vps[n]["width"],all_vps[n]["height"]) for n in all_vps if n in want]
if not viewports:
    print(f"FAIL: render: derived viewports [{derived}] matched no config viewport"); sys.exit(1)
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
print(f"  render: {len(surfaces)*len(viewports)} surface/viewport render(s) across {len(viewports)} derived width(s), {len(errors)} error(s)")
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
fi

[ "$F" -gt 0 ] && { echo "freeze: FAIL ($F check group(s))" >&2; exit 1; }

# ---- §6 hash-bound approval: record the design hash on pass ------------------
# Every check above passed, so the design as it stands NOW is the approved one.
# Bind it: sha256 of the whole design tree (gates/_common/design_hash.sh) into
# state.designHash; structure/scaffold/coverage re-check it and fail if the
# design moved (§6). Writes only to a LIVE state (APPBOX_STATE / run.state.json)
# — the tracked seed default.state.json is read-only (state_set refuses it).
DESIGN_HASH="$(bash "$GATE_COMMON/design_hash.sh" "$DESIGN")"
if state_set designHash "$DESIGN_HASH"; then
  ok "designHash: recorded ${DESIGN_HASH:0:12}… in pipeline state (§6 — downstream gates fail if the design moves)"
else
  echo "  (designHash: no live pipeline state — hash not recorded; set APPBOX_STATE or create pipeline/state/run.state.json)"
fi

# ---- mint the approval stamp only once every check has passed (6.7) --------
# `--approve` is the human action that records "this frozen design is approved
# for THESE targets." It cannot stamp a design that fails freeze, so it runs
# after all checks pass. A later normal run re-validates the stamp (block 1b).
if [ "$APPROVE" = 1 ]; then
  python3 - "$APPROVAL_LOCK" "$APPBOX_TARGETS" "$LOCK_HASH" <<'PY'
import json,sys,datetime
json.dump({"targets":sorted(t for t in sys.argv[2].split(',') if t),
           "inputsHash":sys.argv[3],
           "approvedAt":datetime.datetime.now(datetime.timezone.utc).isoformat()},
          open(sys.argv[1],"w"),indent=2)
PY
  ok "approval: stamped $DESIGN_REL/approval.lock (targets=$APPBOX_TARGETS, inputsHash=${LOCK_HASH:0:12}…)"
  echo "freeze: APPROVED — $DESIGN_REL stamped (all checks passed)."
  exit 0
fi

echo "freeze: PASS — $DESIGN_REL is frozen SSOT material."
exit 0
