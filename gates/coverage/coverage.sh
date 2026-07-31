#!/usr/bin/env bash
# scaffold_coverage_gate.sh — the SCAFFOLD COVERAGE gate (SCAFFOLD_GATE_E).
#
# The seam nothing crossed: freeze_design.sh check 4 guarantees the design's
# shell/surface map, and shell_structure_gate.sh (SCAFFOLD_GATE_D) validates the
# SHAPE of whatever shells exist in lib/ui/views/. Neither compares the two. So
# an app could freeze 46 surfaces, scaffold one, and pass every gate — which is
# exactly the state sample-app was in when this gate was written.
#
# Contract: lib/ui/views/.shell-structure.json gains a "surfaces" map.
#
#   { "selfContained": ["train_shell"],
#     "surfaces": {
#       "train_shell": {
#         "train_shell_training_library_view": "training_library",
#         "train_shell_today_view":            "today"
#       } } }
#
# WHY A DECLARED MAP AND NOT A DERIVED ONE. There is no rule that turns a frozen
# surface id into a directory name. Measured across the two real scaffolded
# corpora: sample-app maps train_shell_training_library_view -> training_library/, while
# design/new-flutter maps the same surface -> library/, and maps
# train_shell_today_view -> home/. 40 of 46 surfaces disagree under any
# strip-prefix rule. The directory name is a scaffolder DECISION, so it is
# recorded, not guessed — the same finding that produced structure.json, one
# layer downstream.
#
# Producer shape (dogfood P14 finding #1): app.routes.js at the design root =>
# htmx producer. The htmx producer IS the authored layer; its Flutter scaffold is
# downstream of the scaffolder and not yet present, so coverage DERIVES + REPORTS
# the target form-factor set the scaffold will require and DEFERS the scaffold/
# ceremony checks (C4 incremental). Missing structure.json still fails (4.4).
#
# Targets drive coverage (plan 06):
#   §6 fresh   — if freeze recorded state.designHash, the design tree must still
#                hash to it (gates/_common/assert_design_fresh.sh); a moved
#                design fails before any coverage check. Legacy empty hash:
#                pass with a note.
#   C1 coverage  — every frozen surface of an ADOPTED shell is mapped, and the
#                  mapped dir carries EXACTLY the derived form-factor set (6.5):
#                  _view.dart + _view.<viewport>.dart for each viewport the
#                  --targets imply + _viewmodel.dart. --targets macos -> desktop
#                  only -> THREE files; no empty .mobile/.tablet is ever demanded
#                  (6.6). Adding a factor is a target edit, not a gate edit.
#   C2 orphans   — every real surface dir under an adopted shell is a mapped
#                  value (a view the design never asked for).
#   C3 undeclared— a shell with real surface dirs that is NOT in selfContained.
#                  This closes the escape hatch: you cannot dodge C1 by
#                  un-adopting a shell you have already started.
#   C4 progress  — unadopted shells are REPORTED with counts, never silent.
#                  Non-fatal: incremental adoption is the point.
#   C5 ceremonies— every active target's platform ceremonies (from the derivation
#                  table) are present: file exists and, if a key is named, the
#                  file carries it. Absence fails naming the missing file (6.8).
#
# Incremental by design, non-vacuous anyway: `selfContained` bounds WHAT is
# checked, C1 admits no partial shell, and C3 stops the list from shrinking.
#
# Usage: coverage.sh [--targets ios,android] [app-root]     (0 pass / 1 FAIL / 2 env)
#        coverage.sh --self-test
# --targets  explicit target set (6.3); absent => read from pipeline state (6.2)
# $KIT_DESIGN_DIR selects the producer folder (default: design).
set -uo pipefail

GATE_COMMON="$(cd "$(dirname "$0")/../_common" && pwd)"
# shellcheck source=../_common/sarif.sh
source "$GATE_COMMON/sarif.sh"
# shellcheck source=../_common/state_reader.sh
source "$GATE_COMMON/state_reader.sh"
# state_reader.sh enables `set -e`; gates run WITHOUT it (a failed check is a
# recorded status, not an abort). Re-assert the gate's mode.
set -uo pipefail
set +e

GATE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$GATE_ROOT/config/appbox.config.json"
DERIVATION="$GATE_ROOT/pipeline/state/targets.derivation.json"

# targets: explicit --targets (6.3) for deterministic gate/golden runs, else
# ambient pipeline state (6.2). The form-factor set DERIVES from these (6.5).
SELF_TEST=0
APPBOX_TARGETS=""
APP="${APPBOX_APP:-$PWD}"
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELF_TEST=1; shift ;;
    --targets)   APPBOX_TARGETS="$2"; shift 2 ;;
    --*)         echo "FAIL: unknown flag: $1" >&2; exit 2 ;;
    *)           APP="$1"; shift ;;
  esac
done

run_gate_for(){
  local APP="$1"
  APP="$(cd "$APP" 2>/dev/null && pwd)" || { echo "FAIL: app root not found: $1" >&2; sarif_result "coverage" "error" "$1" "app root not found"; return 2; }
  local DESIGN_REL="${KIT_DESIGN_DIR:-design}"
  local DESIGN="$APP/$DESIGN_REL"
  # producer shape (the producer-shape seam, dogfood P14 finding #1): app.routes.js
  # at the design root => htmx producer (appbox-designer). The stacked_kit
  # producer carries surfaces/*.html + tokens.json and has no app.routes.js.
  local PRODUCER=stacked_kit
  [ -f "$DESIGN/app.routes.js" ] && PRODUCER=htmx
  # ---- §6: design freshness (hash-bound approval), before any assertion ----
  # Fail-open ONLY for a legacy empty designHash; a written hash that no longer
  # matches the tree means the design moved after freeze.
  local fresh
  if ! fresh="$(bash "$GATE_COMMON/assert_design_fresh.sh" "$DESIGN" 2>&1)"; then
    printf '%s\n' "$fresh"
    sarif_result "coverage" "error" "$APP" "design moved after freeze (designHash mismatch, §6)"
    return 1
  fi
  printf '%s\n' "$fresh"
  local pyout rc fails
  pyout="$(python3 - "$APP" "$DESIGN_REL" "$APPBOX_TARGETS" "$DERIVATION" "$CONFIG" "$PRODUCER" 2>&1 <<'PY'
import json,os,sys,glob

app,rel,targets_csv,derivation_path,config_path,producer=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4],sys.argv[5],sys.argv[6]

# ---- derive the form-factor set + ceremonies for these targets (6.1/6.5/6.8)
targets=[t for t in targets_csv.split(',') if t]
tbl=json.load(open(derivation_path))["targets"]
cfg_vps=json.load(open(config_path))["viewports"]
unknown=[t for t in targets if t not in tbl]
if unknown:
    print(f"FAIL: coverage: unknown target(s): {', '.join(unknown)} — add an entry to "
          f"pipeline/state/targets.derivation.json",file=sys.stderr); sys.exit(1)
def resolve(t, seen=None):
    seen=seen or set()
    if t in seen: return [],[]
    seen.add(t); e=tbl[t]
    vps=list(e.get("viewports",[])); cers=list(e.get("ceremonies",[]))
    if e.get("inherits"):
        pv,pc=resolve(e["inherits"],seen); vps=pv+vps; cers=pc+cers
    return vps,cers
vp_union=[]; ceremony_list=[]
for t in targets:
    v,c=resolve(t)
    for x in v:
        if x not in vp_union: vp_union.append(x)
    for ce in c:
        if ce not in ceremony_list: ceremony_list.append(ce)
# config order; unknown names dropped. Widths come ONLY from config (R3).
FACTORS=[v for v in cfg_vps if v in vp_union]

views=os.path.join(app,"lib","ui","views")
manifest=os.path.join(views,".shell-structure.json")
structure=os.path.join(app,rel,"structure.json")

# Not surfaces. Hard-coded rather than author-supplied for the same reason
# freeze check 4 hard-codes index.html: a name-anything-you-like escape turns
# the orphan check off.
NOT_SURFACE={"bottom_sheets","dialogs","widgets","shared","common","overlays"}

def fail(m): print(f"FAIL: coverage: {m}",file=sys.stderr)
def ok(m):   print(f"  ✓ coverage: {m}")

# 4.4: a gate that cannot find its input MUST fail. Missing structure.json used
# to print "coverage N/A" and exit 0 — a silent pass on missing design state.
if not os.path.isfile(structure):
    fail(f"{rel}/structure.json not found — coverage gate input is missing; "
         f"a gate that cannot find its input never passes quietly (4.4). "
         f"Freeze the design, or point KIT_DESIGN_DIR at the producer folder.")
    sys.exit(1)

try: st=json.load(open(structure))
except Exception as e: fail(f"{rel}/structure.json does not parse — {e}"); sys.exit(1)

frozen={}
for s in st.get("screens",[]):
    if s.get("surface") and s.get("shellDir"):
        frozen.setdefault(s["shellDir"],set()).add(s["surface"])
if not frozen:
    fail(f"{rel}/structure.json declares no surfaces — nothing to cover"); sys.exit(1)

# ---- htmx producer: derive + report the form-factor set; defer scaffold checks
# The htmx producer IS the authored layer; its Flutter scaffold is downstream of
# the scaffolder and does not exist yet (dogfood P14 honest-bar #2). So the
# scaffold/ceremony checks (C1-C5 over lib/ui/views) have nothing to assert here
# — coverage derives the form-factor set the scaffold WILL require and defers the
# rest (C4 incremental: a shell not yet scaffolded is reported, never silently
# green). The derivation itself is identical to the stacked_kit path.
if producer=="htmx":
    n=sum(len(v) for v in frozen.values())
    files_per=1+len(FACTORS)+1   # _view.dart + one _view.<factor>.dart per derived viewport + _viewmodel.dart
    ok(f"htmx producer — {n} frozen surface(s) across {len(frozen)} shell(s)")
    print(f"  coverage: targets [{','.join(targets)}] -> form factors [{', '.join(FACTORS) or 'none'}] "
          f"-> {files_per} file(s)/surface when the Flutter scaffold is emitted")
    print(f"  coverage: no Flutter scaffold layer for this htmx producer yet — "
          f"scaffold/ceremony checks deferred (C4 incremental); {rel}/structure.json verified")
    sys.exit(0)

mf={}
if os.path.isfile(manifest):
    try: mf=json.load(open(manifest))
    except Exception as e: fail(f"lib/ui/views/.shell-structure.json does not parse — {e}"); sys.exit(1)
adopted=mf.get("selfContained") or []
smap=mf.get("surfaces") or {}
if not isinstance(smap,dict):
    fail('.shell-structure.json "surfaces" must be an object of {shell: {surfaceId: dir}}'); sys.exit(1)

# real surface dirs actually on disk, per shell
def real_dirs(shell):
    d=os.path.join(views,shell)
    if not os.path.isdir(d): return set()
    return {n for n in os.listdir(d)
            if os.path.isdir(os.path.join(d,n)) and not n.startswith('.') and n not in NOT_SURFACE}

F=0

# ---- C3: a shell you have started building must be declared ----------------
for shell in sorted(os.listdir(views) if os.path.isdir(views) else []):
    if not os.path.isdir(os.path.join(views,shell)) or shell.startswith('.'): continue
    if shell in adopted: continue
    got=real_dirs(shell)
    if got:
        fail(f"shell '{shell}' has {len(got)} surface dir(s) ({', '.join(sorted(got))}) but is not in "
             f".shell-structure.json selfContained — a shell you have started building must be declared, "
             f"or coverage silently stops applying to it"); F+=1

# ---- C1 + C2: adopted shells are covered completely ------------------------
for shell in sorted(adopted):
    want=frozen.get(shell)
    if want is None:
        fail(f"shell '{shell}' is adopted but {rel}/structure.json freezes no surface for it"); F+=1
        continue
    m=smap.get(shell) or {}
    if not isinstance(m,dict):
        fail(f'surfaces["{shell}"] must be an object of {{surfaceId: dir}}'); F+=1; continue

    F0=F     # this shell's ✓ line must depend on THIS shell's findings, not on
             # "was everything mapped" — a mapped surface whose directory does
             # not exist is unbuilt, and printing 5/5 next to four such failures
             # is exactly the false-green a coverage gate exists to prevent.
    missing=sorted(want-set(m))
    for s in missing:
        fail(f"shell '{shell}': frozen surface '{s}' is not mapped in .shell-structure.json "
             f'surfaces["{shell}"] — adopting a shell means covering all of it'); F+=1
    for s in sorted(set(m)-want):
        fail(f"shell '{shell}': surfaces[\"{shell}\"] maps '{s}', which {rel}/structure.json does not "
             f"freeze for this shell"); F+=1

    dirs=list(m.values())
    for d in sorted({x for x in dirs if dirs.count(x)>1}):
        fail(f"shell '{shell}': directory '{d}' is claimed by {dirs.count(d)} surfaces"); F+=1

    # the DERIVED form-factor set (6.5): base _view.dart + one _view.<factor>.dart
    # per derived viewport + _viewmodel.dart. Never demands a factor the targets
    # do not imply, so no empty .mobile/.tablet is created just to pass (6.6).
    for s in sorted(set(m)&want):
        d=m[s]; base=os.path.join(views,shell,d)
        if not os.path.isdir(base):
            fail(f"shell '{shell}': surface '{s}' maps to '{d}/' which does not exist under "
                 f"lib/ui/views/{shell}/"); F+=1; continue
        need=[f"{d}_view.dart"]+[f"{d}_view.{f}.dart" for f in FACTORS]+[f"{d}_viewmodel.dart"]
        gone=[n for n in need if not os.path.isfile(os.path.join(base,n))]
        if gone:
            factors_desc=' '.join(FACTORS) or '(none)'
            fail(f"shell '{shell}': lib/ui/views/{shell}/{d}/ is missing {', '.join(gone)} — "
                 f"targets [{','.join(targets)}] derive form-factor(s) [{factors_desc}]; "
                 f"the gate requires _view.dart + each derived _view.<factor>.dart + _viewmodel.dart"); F+=1

    for d in sorted(real_dirs(shell)-set(m.values())):
        fail(f"shell '{shell}': lib/ui/views/{shell}/{d}/ is a view the design never froze "
             f"(not a value in surfaces[\"{shell}\"])"); F+=1

    built=len(want)-(F-F0)
    if F==F0:
        ok(f"{shell}: {len(want)}/{len(want)} frozen surfaces scaffolded")
    else:
        print(f"  ✗ coverage: {shell}: {max(built,0)}/{len(want)} frozen surfaces scaffolded")

# ---- C4: progress, always visible ------------------------------------------
todo=sorted(set(frozen)-set(adopted))
covered=sum(len(frozen[s]) for s in adopted if s in frozen)
total=sum(len(v) for v in frozen.values())
print(f"  coverage: {covered}/{total} frozen surface(s) in {len(adopted)} adopted shell(s) "
      f"of {len(frozen)}; targets [{','.join(targets)}] -> form factors [{', '.join(FACTORS) or 'none'}]")
if todo:
    print(f"  not yet adopted ({sum(len(frozen[s]) for s in todo)} surface(s)):")
    for s in todo: print(f"      {s:18} {len(frozen[s])}")

# ---- C5: platform ceremonies fire from targets (6.8) -----------------------
# Each ceremony is a list of {path, key?} checks relative to the app root. A
# missing file, or a named key absent from the file, fails the gate naming it.
for ce in ceremony_list:
    cid=ce.get("id","?"); cdesc=ce.get("desc","")
    for chk in ce.get("checks",[]):
        p=chk.get("path"); key=chk.get("key"); full=os.path.join(app,p)
        if not os.path.isfile(full):
            fail(f"ceremony '{cid}' ({cdesc}): {p} missing — targets [{','.join(targets)}] "
                 f"require it"); F+=1
        elif key:
            try: body=open(full,errors="replace").read()
            except Exception: body=""
            if key not in body:
                fail(f"ceremony '{cid}' ({cdesc}): {p} present but lacks key '{key}'"); F+=1

sys.exit(1 if F else 0)
PY
)"
  rc=$?
  printf '%s\n' "$pyout"
  fails="$(printf '%s\n' "$pyout" | grep '^FAIL:' || true)"
  [ -n "$fails" ] && printf '%s\n' "$fails" | while IFS= read -r fl; do sarif_result "coverage" "error" "$APP" "$fl"; done
  return $rc
}

# ---------------------------------------------------------------- self-test
self_test(){
  local P=0 Fc=0 T; T="$(mktemp -d)"; trap 'rm -rf "$T"' RETURN
  chk(){ [ "$1" = "$2" ] && P=$((P+1)) || { Fc=$((Fc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
  need(){ case "$1" in *"$2"*) P=$((P+1));; *) Fc=$((Fc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }
  avoid(){ case "$1" in *"$2"*) Fc=$((Fc+1)); echo "  FAIL: output should NOT mention [$2] — $3";; *) P=$((P+1));; esac; }

  # factors_of <targets_csv> -> space-separated derived viewport names
  factors_of(){ python3 - "$1" "$DERIVATION" "$CONFIG" <<'PY'
import json,sys
targets=[t for t in sys.argv[1].split(',') if t]
tbl=json.load(open(sys.argv[2]))["targets"]; cfg=json.load(open(sys.argv[3]))["viewports"]
def vps_of(t,seen=None):
    seen=seen or set()
    if t in seen: return []
    seen.add(t); e=tbl[t]; out=list(e.get("viewports",[]))
    if e.get("inherits"): out=vps_of(e["inherits"],seen)+out
    return out
union=[]
for t in targets:
    for v in vps_of(t):
        if v not in union: union.append(v)
print(" ".join(v for v in cfg if v in union))
PY
  }
  # build the platform ceremony files a target set requires under <app>
  ceremonies_of(){ python3 - "$1" "$2" "$DERIVATION" <<'PY'
import json,sys,os
app=sys.argv[1]; targets=sys.argv[2].split(','); tbl=json.load(open(sys.argv[3]))["targets"]
def resolve(t,seen=None):
    seen=seen or set(); 
    if t in seen: return []
    seen.add(t); e=tbl[t]; out=list(e.get("ceremonies",[]))
    if e.get("inherits"): out=resolve(e["inherits"],seen)+out
    return out
cers=[]
for t in targets:
    for c in resolve(t):
        if c not in cers: cers.append(c)
for ce in cers:
    for chk in ce.get("checks",[]):
        p=os.path.join(app,chk.get("path","")); key=chk.get("key")
        os.makedirs(os.path.dirname(p),exist_ok=True)
        body=open(p).read() if os.path.isfile(p) else ""
        if key and key not in body:
            with open(p,"a") as fh: fh.write(f"<key>{key}</key>\n")
        elif not os.path.isfile(p):
            open(p,"w").close()
PY
  }

  # plant <app> <manifest-json> <targets> [surface-dirs-to-make...]
  plant(){
    local a="$1" man="$2" tg="$3"; shift 3
    rm -rf "$a"; mkdir -p "$a/lib/ui/views/train_shell" "$a/design/new"
    cat > "$a/design/new/structure.json" <<'EOF'
{"$schema":"kit/design-structure@1","registry":null,"shellRoots":{},
 "screens":[
  {"id":"train.library","shell":"train","comp":"L","shellDir":"train_shell","surface":"train_shell_library_view"},
  {"id":"train.stats","shell":"train","comp":"S","shellDir":"train_shell","surface":"train_shell_stats_view"}]}
EOF
    printf '%s' "$man" > "$a/lib/ui/views/.shell-structure.json"
    local fs; fs="$(factors_of "$tg")"
    local d f; for d in "$@"; do
      mkdir -p "$a/lib/ui/views/train_shell/$d"
      : > "$a/lib/ui/views/train_shell/$d/${d}_view.dart"
      for f in $fs; do : > "$a/lib/ui/views/train_shell/$d/${d}_view.$f.dart"; done
      : > "$a/lib/ui/views/train_shell/$d/${d}_viewmodel.dart"
    done
    ceremonies_of "$a" "$tg"
  }
  run(){ ( KIT_DESIGN_DIR=design/new APPBOX_TARGETS="$2" run_gate_for "$1" ) 2>&1; }

  local FULL='{"selfContained":["train_shell"],"surfaces":{"train_shell":{"train_shell_library_view":"library","train_shell_stats_view":"stats"}}}'
  local o

  # ---- 6.5 proof: --targets macos -> desktop only -> THREE files -----------
  plant "$T/a" "$FULL" macos library stats
  o=$(run "$T/a" macos); chk "$?" 0 "macos: 3-file desktop set PASSES"
  need "$o" "2/2 frozen surfaces scaffolded" "macos reports full coverage"
  # the macos set is exactly _view, _view.desktop, _viewmodel — no .mobile/.tablet
  [ -f "$T/a/lib/ui/views/train_shell/library/library_view.dart" ] && P=$((P+1)) || { Fc=$((Fc+1)); echo "  FAIL: base _view.dart should exist"; }
  [ -f "$T/a/lib/ui/views/train_shell/library/library_view.desktop.dart" ] && P=$((P+1)) || { Fc=$((Fc+1)); echo "  FAIL: _view.desktop.dart should exist"; }
  [ -f "$T/a/lib/ui/views/train_shell/library/library_viewmodel.dart" ] && P=$((P+1)) || { Fc=$((Fc+1)); echo "  FAIL: _viewmodel.dart should exist"; }
  avoid "$o" "_view.mobile.dart" "macos must NOT demand a mobile factor (6.6)"
  avoid "$o" "_view.tablet.dart" "macos must NOT demand a tablet factor (6.6)"

  # ---- NEGATIVE (6.5): macos but a derived factor file is missing ---------
  plant "$T/a" "$FULL" macos library stats
  rm "$T/a/lib/ui/views/train_shell/stats/stats_view.desktop.dart"
  o=$(run "$T/a" macos); chk "$?" 1 "macos: missing desktop factor FAILS"
  need "$o" "stats_view.desktop.dart" "names the missing derived factor"

  # ---- 6.5 proof: --targets ios,android -> mobile+tablet -> FOUR files -----
  plant "$T/a" "$FULL" ios,android library stats
  o=$(run "$T/a" ios,android); chk "$?" 0 "ios,android: 4-file mobile+tablet set PASSES"
  need "$o" "form factors [mobile, tablet]" "ios,android derives mobile+tablet"
  avoid "$o" "_view.desktop.dart" "ios,android must NOT demand desktop"

  # ---- 6.5 proof: --targets web -> mobile+tablet+desktop -> FIVE files -----
  plant "$T/a" "$FULL" web library stats
  o=$(run "$T/a" web); chk "$?" 0 "web: 5-file mobile+tablet+desktop set PASSES"
  need "$o" "form factors [mobile, tablet, desktop]" "web derives all three factors (§11)"
  need "$o" "2/2 frozen surfaces scaffolded" "web reports full coverage of the 5-file set"

  # ---- NEGATIVE (6.5): web but a derived factor file is missing ------------
  plant "$T/a" "$FULL" web library stats
  rm "$T/a/lib/ui/views/train_shell/stats/stats_view.desktop.dart"
  o=$(run "$T/a" web); chk "$?" 1 "web: missing desktop factor FAILS"
  need "$o" "stats_view.desktop.dart" "names the missing derived factor"

  # ---- 6.5 proof: --targets android alone -> same 4-file set as ios --------
  plant "$T/a" "$FULL" android library stats
  o=$(run "$T/a" android); chk "$?" 0 "android alone: 4-file mobile+tablet set PASSES"
  need "$o" "form factors [mobile, tablet]" "android derives mobile+tablet, no desktop"
  avoid "$o" "_view.desktop.dart" "android must NOT demand desktop"

  # ---- NEGATIVE (6.6): an UNWANTED empty .mobile file must not satisfy ----
  # the counter. macos (desktop only) with a stray .mobile present still passes
  # (its absence is not a failure) — but removing the required .desktop must
  # still fail even though .mobile exists (proof the gate counts derived, not
  # total, files).
  plant "$T/a" "$FULL" macos library stats
  rm "$T/a/lib/ui/views/train_shell/stats/stats_view.desktop.dart"
  : > "$T/a/lib/ui/views/train_shell/stats/stats_view.mobile.dart"   # empty, unwanted
  o=$(run "$T/a" macos); chk "$?" 1 "6.6: empty .mobile does not satisfy the desktop requirement"
  need "$o" "stats_view.desktop.dart" "still names the required derived factor"

  # ---- C1: a frozen surface left unmapped (the sample-app defect) ----------
  plant "$T/a" '{"selfContained":["train_shell"],"surfaces":{"train_shell":{"train_shell_library_view":"library"}}}' macos library
  o=$(run "$T/a" macos); chk "$?" 1 "unmapped frozen surface FAILS"
  need "$o" "is not mapped" "names the unmapped surface"

  # ---- C1: mapped but the directory does not exist -------------------------
  plant "$T/a" "$FULL" macos library
  o=$(run "$T/a" macos); chk "$?" 1 "mapped dir that does not exist FAILS"
  need "$o" "which does not exist" "names the missing dir"
  need "$o" "✗ coverage: train_shell: 1/2" "reports 1/2, not a green 2/2, when a mapped dir is unbuilt"
  case "$o" in *"✓ coverage: train_shell"*) Fc=$((Fc+1)); echo "  FAIL: printed a ✓ shell line inside a failing shell";; *) P=$((P+1));; esac

  # ---- C2: a view the design never froze -----------------------------------
  plant "$T/a" "$FULL" macos library stats ghost
  o=$(run "$T/a" macos); chk "$?" 1 "unfrozen surface dir FAILS"
  need "$o" "the design never froze" "names the orphan view"

  # ---- C3: the escape hatch — un-adopt a shell you have already started -----
  plant "$T/a" '{"selfContained":[],"surfaces":{}}' macos library
  o=$(run "$T/a" macos); chk "$?" 1 "started-but-undeclared shell FAILS (escape hatch closed)"
  need "$o" "must be declared" "explains why un-adopting is not an out"

  # ---- C4: a greenfield app with nothing built yet is NOT a failure ---------
  plant "$T/a" '{"selfContained":[],"surfaces":{}}' macos
  o=$(run "$T/a" macos); chk "$?" 0 "nothing scaffolded yet PASSES (incremental adoption)"
  need "$o" "not yet adopted" "still REPORTS the outstanding surfaces"
  need "$o" "0/2" "counts the uncovered surfaces"

  # ---- 6.8 proof: a ceremony's absence fails, naming the missing file ------
  # pwa requires (via web) web/index.html + web/manifest.json + web/sw.js.
  plant "$T/a" "$FULL" pwa library stats      # ceremonies_of builds them
  o=$(run "$T/a" pwa); chk "$?" 0 "pwa: all ceremonies present PASSES"
  rm "$T/a/web/manifest.json"                  # now a ceremony is missing
  o=$(run "$T/a" pwa); chk "$?" 1 "pwa: missing manifest.json ceremony FAILS"
  need "$o" "web/manifest.json missing" "names the missing ceremony file"

  # ---- 6.8 proof: ceremony file present but key absent --------------------
  plant "$T/a" "$FULL" macos library stats    # builds entitlements w/ keychain-access-groups
  o=$(run "$T/a" macos); chk "$?" 0 "macos: keychain ceremony present PASSES"
  printf '<?xml version="1.0"?>\n<plist><dict></dict></plist>\n' > "$T/a/macos/Runner/Release.entitlements"
  o=$(run "$T/a" macos); chk "$?" 1 "macos: entitlement lacks keychain-access-groups key FAILS"
  need "$o" "Release.entitlements" "names the offending ceremony file"
  need "$o" "keychain-access-groups" "names the missing key"

  # ---- 6.8 proof: android ceremonies fire from --targets android alone -----
  plant "$T/a" "$FULL" android library stats  # ceremonies_of builds adaptive icons + splash
  o=$(run "$T/a" android); chk "$?" 0 "android: all ceremonies present PASSES"
  rm "$T/a/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
  o=$(run "$T/a" android); chk "$?" 1 "android: missing adaptive-icon ceremony FAILS"
  need "$o" "ic_launcher.xml missing" "names the missing ceremony file"

  # ---- 6.8 proof: web ceremony fires from --targets web alone ---------------
  plant "$T/a" "$FULL" web library stats      # ceremonies_of builds web/index.html
  o=$(run "$T/a" web); chk "$?" 0 "web: index.html ceremony present PASSES"
  rm "$T/a/web/index.html"
  o=$(run "$T/a" web); chk "$?" 1 "web: missing index.html ceremony FAILS"
  need "$o" "web/index.html missing" "names the missing ceremony file"

  # ---- 4.4: missing structure.json MUST fail (was: silent N/A exit 0) ------
  rm -rf "$T/b"; mkdir -p "$T/b/lib/ui/views"
  o=$( APPBOX_TARGETS=macos KIT_DESIGN_DIR=design/new run_gate_for "$T/b" 2>&1 ); chk "$?" 1 "no structure.json -> FAILS (4.4: missing input)"
  need "$o" "structure.json not found" "names the missing input"

  # ---- 6.3 proof: unknown target fails loudly ------------------------------
  plant "$T/a" "$FULL" macos library stats
  o=$(run "$T/a" zxspectrum); chk "$?" 1 "unknown target FAILS"
  need "$o" "unknown target" "names the unknown target"

  # ---- htmx producer: derive form-factor set, defer scaffold (seam) --------
  # app.routes.js at the design root => htmx producer. coverage derives the
  # target form-factor set and defers scaffold/ceremony checks (no Flutter layer
  # for an htmx design). 4.4 still applies: missing structure.json fails loudly.
  rm -rf "$T/h"; mkdir -p "$T/h/design/htmx"
  printf 'export default [["GET","/",{}]];\n' > "$T/h/design/htmx/app.routes.js"
  printf '{"registry":"registry.json","shellRoots":{},"screens":[{"id":"a","shell":"sh","shellDir":"sh","surface":"sh_a_view"}]}\n' > "$T/h/design/htmx/structure.json"
  printf '[{"id":"a","surface":"sh_a_view","shell":"sh","comp":"A"}]\n' > "$T/h/design/htmx/registry.json"
  o=$( KIT_DESIGN_DIR=design/htmx APPBOX_TARGETS=macos run_gate_for "$T/h" 2>&1 ); chk "$?" 0 "htmx macos: derives set, passes (no scaffold)"
  need "$o" "htmx producer — 1 frozen surface" "htmx reports the frozen surface count"
  need "$o" "form factors [desktop]" "htmx derives desktop for macos"
  need "$o" "3 file(s)/surface" "htmx reports the macos 3-file requirement"
  o=$( KIT_DESIGN_DIR=design/htmx APPBOX_TARGETS=ios,android run_gate_for "$T/h" 2>&1 ); chk "$?" 0 "htmx ios,android: derives mobile+tablet"
  need "$o" "form factors [mobile, tablet]" "htmx derives mobile+tablet for ios,android"
  need "$o" "4 file(s)/surface" "htmx reports the 4-file mobile+tablet requirement"
  rm -rf "$T/h2"; mkdir -p "$T/h2/design/htmx"   # htmx signal, no structure.json
  printf 'export default [["GET","/",{}]];\n' > "$T/h2/design/htmx/app.routes.js"
  o=$( KIT_DESIGN_DIR=design/htmx APPBOX_TARGETS=macos run_gate_for "$T/h2" 2>&1 ); chk "$?" 1 "htmx: missing structure.json FAILS (4.4)"
  need "$o" "structure.json not found" "names the missing input"

  echo
  echo "scaffold_coverage_gate self-test: passed=$P failed=$Fc"
  [ "$Fc" -eq 0 ] && { echo "ALL GREEN"; return 0; } || return 1
}

if [ "$SELF_TEST" = 1 ]; then self_test; exit $?; fi
# resolve targets: explicit flag, else ambient pipeline state (6.2)
if [ -z "$APPBOX_TARGETS" ]; then
  APPBOX_TARGETS="$(state_targets 2>/dev/null | paste -sd ',' -)"
fi
if [ -z "$APPBOX_TARGETS" ]; then
  echo "FAIL: no --targets given and no targets in pipeline state — pass --targets explicitly (6.3); a reproducibility run that reads ambient state is the stale-green defect" >&2
  exit 1
fi
run_gate_for "$APP"; exit $?
