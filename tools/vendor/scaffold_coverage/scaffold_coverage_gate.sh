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
# Checks:
#   C1 coverage  — every frozen surface of an ADOPTED shell is mapped, and the
#                  mapped dir carries the 5-file form-factor set enforce_design
#                  check 5 requires. No partial credit: adopting a shell means
#                  all of it.
#   C2 orphans   — every real surface dir under an adopted shell is a mapped
#                  value (a view the design never asked for).
#   C3 undeclared— a shell with real surface dirs that is NOT in selfContained.
#                  This closes the escape hatch: you cannot dodge C1 by
#                  un-adopting a shell you have already started.
#   C4 progress  — unadopted shells are REPORTED with counts, never silent.
#                  Non-fatal: incremental adoption is the point.
#
# Incremental by design, non-vacuous anyway: `selfContained` bounds WHAT is
# checked, C1 admits no partial shell, and C3 stops the list from shrinking.
#
# Usage: scaffold_coverage_gate.sh [app-root]     (0 pass / 1 FAIL / 2 env)
#        scaffold_coverage_gate.sh --self-test
# $KIT_DESIGN_DIR selects the producer folder (default: design).
set -uo pipefail

# form-factor set is config-driven (R3): the keys of config/app-box.config.json
# viewports (mobile/tablet/desktop), not a hardcoded five-file list. Plans 05/06
# consume the same derivation.
GATE_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
FACTORS="$(python3 -c "import json;d=json.load(open('$GATE_ROOT/config/app-box.config.json'));print(' '.join(d['viewports'].keys()))" 2>/dev/null || echo "mobile tablet desktop")"

run_gate_for(){
  local APP="$1"
  APP="$(cd "$APP" 2>/dev/null && pwd)" || { echo "FAIL: app root not found: $1" >&2; return 2; }
  local DESIGN_REL="${KIT_DESIGN_DIR:-design}"
  python3 - "$APP" "$DESIGN_REL" "$FACTORS" <<'PY'
import json,os,sys,glob

app,rel,factors=sys.argv[1],sys.argv[2],sys.argv[3]
FACTORS=factors.split()
views=os.path.join(app,"lib","ui","views")
manifest=os.path.join(views,".shell-structure.json")
structure=os.path.join(app,rel,"structure.json")

# Not surfaces. Hard-coded rather than author-supplied for the same reason
# freeze check 4 hard-codes index.html: a name-anything-you-like escape turns
# the orphan check off.
NOT_SURFACE={"bottom_sheets","dialogs","widgets","shared","common","overlays"}

def fail(m): print(f"FAIL: coverage: {m}",file=sys.stderr)
def ok(m):   print(f"  ✓ coverage: {m}")

if not os.path.isdir(views):
    print(f"  (coverage N/A — no {os.path.relpath(views,app)}/)"); sys.exit(0)
if not os.path.isfile(structure):
    print(f"  (coverage N/A — no {rel}/structure.json; app is not design-driven)"); sys.exit(0)

try: st=json.load(open(structure))
except Exception as e: fail(f"{rel}/structure.json does not parse — {e}"); sys.exit(1)

frozen={}
for s in st.get("screens",[]):
    if s.get("surface") and s.get("shell"):
        frozen.setdefault(s["shell"],set()).add(s["surface"])
if not frozen:
    fail(f"{rel}/structure.json declares no surfaces — nothing to cover"); sys.exit(1)

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

    # the 5-file form-factor set enforce_design.dart check 5 requires
    for s in sorted(set(m)&want):
        d=m[s]; base=os.path.join(views,shell,d)
        if not os.path.isdir(base):
            fail(f"shell '{shell}': surface '{s}' maps to '{d}/' which does not exist under "
                 f"lib/ui/views/{shell}/"); F+=1; continue
        need=[f"{d}_view.dart"]+[f"{d}_view.{f}.dart" for f in FACTORS]+[f"{d}_viewmodel.dart"]
        gone=[n for n in need if not os.path.isfile(os.path.join(base,n))]
        if gone:
            fail(f"shell '{shell}': lib/ui/views/{shell}/{d}/ is missing {', '.join(gone)} — "
                 f"the design gate (enforce_design check 5) requires all four form factors "
                 f"plus the viewmodel"); F+=1

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
      f"of {len(frozen)}")
if todo:
    print(f"  not yet adopted ({sum(len(frozen[s]) for s in todo)} surface(s)):")
    for s in todo: print(f"      {s:18} {len(frozen[s])}")

sys.exit(1 if F else 0)
PY
}

# ---------------------------------------------------------------- self-test
self_test(){
  local P=0 Fc=0 T; T="$(mktemp -d)"; trap 'rm -rf "$T"' RETURN
  chk(){ [ "$1" = "$2" ] && P=$((P+1)) || { Fc=$((Fc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
  need(){ case "$1" in *"$2"*) P=$((P+1));; *) Fc=$((Fc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

  # plant <app> <manifest-json> [surface-dirs-to-make...]
  plant(){
    local a="$1" man="$2"; shift 2
    rm -rf "$a"; mkdir -p "$a/lib/ui/views/train_shell" "$a/design/new"
    cat > "$a/design/new/structure.json" <<'EOF'
{"$schema":"kit/design-structure@1","registry":null,"tabRoots":{},
 "screens":[
  {"id":"train.library","tab":"train","comp":"L","shell":"train_shell","surface":"train_shell_library_view"},
  {"id":"train.stats","tab":"train","comp":"S","shell":"train_shell","surface":"train_shell_stats_view"}]}
EOF
    printf '%s' "$man" > "$a/lib/ui/views/.shell-structure.json"
    local d; for d in "$@"; do
      mkdir -p "$a/lib/ui/views/train_shell/$d"
      local f; for f in _view.dart $(printf '_view.%s.dart ' $FACTORS) _viewmodel.dart; do
        : > "$a/lib/ui/views/train_shell/$d/$d$f"
      done
    done
  }
  run(){ ( KIT_DESIGN_DIR=design/new run_gate_for "$1" ) 2>&1; }

  local FULL='{"selfContained":["train_shell"],"surfaces":{"train_shell":{"train_shell_library_view":"library","train_shell_stats_view":"stats"}}}'
  local o

  # ---- good twin: both frozen surfaces mapped and complete
  plant "$T/a" "$FULL" library stats
  o=$(run "$T/a"); chk "$?" 0 "fully covered adopted shell PASSES"
  need "$o" "2/2 frozen surfaces scaffolded" "good twin reports full coverage"

  # ---- C1: a frozen surface left unmapped (the sample-app defect)
  plant "$T/a" '{"selfContained":["train_shell"],"surfaces":{"train_shell":{"train_shell_library_view":"library"}}}' library
  o=$(run "$T/a"); chk "$?" 1 "unmapped frozen surface FAILS"
  need "$o" "is not mapped" "names the unmapped surface"

  # ---- C1: mapped but the directory does not exist
  plant "$T/a" "$FULL" library
  o=$(run "$T/a"); chk "$?" 1 "mapped dir that does not exist FAILS"
  need "$o" "which does not exist" "names the missing dir"
  # ...and the per-shell tally must NOT read 2/2 next to that failure. A fully
  # mapped shell with unbuilt dirs is the exact false-green this gate exists to
  # prevent, so assert the count, not just the exit code.
  need "$o" "✗ coverage: train_shell: 1/2" "reports 1/2, not a green 2/2, when a mapped dir is unbuilt"
  case "$o" in *"✓ coverage: train_shell"*) Fc=$((Fc+1)); echo "  FAIL: printed a ✓ shell line inside a failing shell";; *) P=$((P+1));; esac

  # ---- C1: dir exists but the form-factor set is incomplete
  plant "$T/a" "$FULL" library stats
  rm "$T/a/lib/ui/views/train_shell/stats/stats_view.tablet.dart"
  o=$(run "$T/a"); chk "$?" 1 "missing form-factor file FAILS"
  need "$o" "stats_view.tablet.dart" "names the missing form factor"

  # ---- C2: a view the design never froze
  plant "$T/a" "$FULL" library stats ghost
  o=$(run "$T/a"); chk "$?" 1 "unfrozen surface dir FAILS"
  need "$o" "the design never froze" "names the orphan view"

  # ---- C1: mapping a surface the design does not freeze for this shell
  plant "$T/a" '{"selfContained":["train_shell"],"surfaces":{"train_shell":{"train_shell_library_view":"library","train_shell_stats_view":"stats","train_shell_ghost_view":"ghost"}}}' library stats ghost
  o=$(run "$T/a"); chk "$?" 1 "mapping an unfrozen surface FAILS"
  need "$o" "does not" "names the unfrozen mapping"

  # ---- C1: two surfaces claiming one directory
  plant "$T/a" '{"selfContained":["train_shell"],"surfaces":{"train_shell":{"train_shell_library_view":"library","train_shell_stats_view":"library"}}}' library
  o=$(run "$T/a"); chk "$?" 1 "duplicate dir claim FAILS"
  need "$o" "is claimed by 2 surfaces" "names the duplicate"

  # ---- C3: the escape hatch — un-adopt a shell you have already started
  plant "$T/a" '{"selfContained":[],"surfaces":{}}' library
  o=$(run "$T/a"); chk "$?" 1 "started-but-undeclared shell FAILS (escape hatch closed)"
  need "$o" "must be declared" "explains why un-adopting is not an out"

  # ---- C4: a greenfield app with nothing built yet is NOT a failure
  plant "$T/a" '{"selfContained":[],"surfaces":{}}'
  o=$(run "$T/a"); chk "$?" 0 "nothing scaffolded yet PASSES (incremental adoption)"
  need "$o" "not yet adopted" "still REPORTS the outstanding surfaces"
  need "$o" "0/2" "counts the uncovered surfaces"

  # ---- N/A paths never rubber-stamp silently
  rm -rf "$T/b"; mkdir -p "$T/b/lib/ui/views"
  o=$( KIT_DESIGN_DIR=design/new run_gate_for "$T/b" 2>&1 ); chk "$?" 0 "no structure.json -> N/A exit 0"
  need "$o" "not design-driven" "says WHY it is N/A"

  echo
  echo "scaffold_coverage_gate self-test: passed=$P failed=$Fc"
  [ "$Fc" -eq 0 ] && { echo "ALL GREEN"; return 0; } || return 1
}

case "${1:-}" in
  --self-test) self_test; exit $?;;
  *) run_gate_for "${1:-${KIT_APP:-$PWD}}"; exit $?;;
esac
