#!/usr/bin/env bash
# pipeline.sh — the stacked_kit skill constellation orchestrator.
#
# Enforces the gated pipeline (prototype → design → scaffold → review) and the
# invariant that the REVIEWER always has the last word: nothing is `done` unless the
# review phase is `approved` AND no gated skill has touched code since.
# Ungated skills (kit-tester, feature-implementer) may run any time, but any code
# they change marks the pipeline dirty → the reviewer must re-approve.
#
# Operates on a tree of stacked_kit surfaces. Default target = the stacked_kit
# monorepo itself (ROOT). Set KIT_APP=<dir> for CONSUMER mode — any authentic
# stacked_kit app (path-deps a kit + @StackedApp), e.g. this repo's own sample-app/.
# With KIT_APP unset, running from a cwd OUTSIDE the kit tree is refused
# (phantom-state guard — keeps state from silently splitting into the kit);
# escape hatches: KIT_PIPELINE_STATE_DIR=<dir> or KIT_MONOREPO=1.
# Consumer mode retargets cwd + state to the app and drops the monorepo-only
# tools/gate.sh from scaffold/review (gate.sh hard-codes stacked_kit/ and
# validates the *kits*, not an app); scaffold_gate.sh (app authenticity),
# enforce_design.dart (surface quality), and review_checklist.sh (cwd app tree)
# remain. Every per-phase gate still delegates to a REAL gate.
#
# State lives in pipeline/state/ under the target (gitignored): phase.json (the FSM),
# runs.jsonl (append-only per-invocation run records), golden_audit.jsonl (deliberate
# golden accepts), checkpoints.jsonl (Commit Checkpoints). bash 3.2-safe (python3 for
# JSON, no assoc arrays / mapfile / readlink -f). Deliberately no `set -e` — a failed
# gate is a recorded status, not an abort.
#
#   pipeline.sh init                          # new pipeline (phase=prototype)
#   pipeline.sh status                        # current phase + each gate + done?
#   pipeline.sh gate prototype                # freeze gate: validate the design/ SSOT (ADR-0010)
#   pipeline.sh gate prototype --approve [note]  # Human Gate 1: browser-approved (freeze must be green)
#   pipeline.sh gate prototype --rework <note>   # Human Gate 1: back to HTML-level rework
#   pipeline.sh gate design|scaffold|review   # run that phase's stacked_kit gate
#   pipeline.sh gate reproducibility          # Golden Gate: region_diff golden vs fixture/actual
#   pipeline.sh golden --accept               # deliberate golden update (audit-trailed)
#   pipeline.sh advance                       # phase++ iff current gate passed
#   pipeline.sh checkpoint [note]             # Commit Checkpoint: deliberate recorded git commit
#   pipeline.sh review approve|reject [reason]# reviewer-only terminal authority
#   pipeline.sh touch [note]                  # implementer/kit-tester changed code → dirty
#   pipeline.sh done                          # exit 0 iff review approved & clean
#   pipeline.sh reset                         # clear review rejection counter (human override)
#   pipeline.sh loop [--max N] [--fix-cmd '…'] # evaluator-optimizer driver: gate→fix→re-gate→approve
#   pipeline.sh selftest                      # exercise the FSM on a temp state
#
# Every gate/advance/review/touch/golden invocation appends one JSON line to
# pipeline/state/runs.jsonl: {run_id, ts, phase, action, result, duration_ms,
# failing_signature?} — the Input Tuple-era audit stream (ADR 0009).
#
# Gate delegation (override via env, e.g. PIPELINE_DESIGN_GATE=...):
#   prototype → tools/freeze_design.sh "$APP"  (design-dir freeze: shape/vocab/
#              exclusions/render; app-only — pass sentinel at the monorepo root.
#              PROTOTYPE_TARGET=native → kit-designer-authored design (ADR-0015);
#              =none → non-UI slice bypass, grill Q6/ADR-0010.
#              advance past prototype needs the second key: --approve, D5.)
#   design   → skills/kit-designer/scripts/enforce_design.dart "$DESIGN_TARGET"
#              (DESIGN_TARGET=none → non-UI slice: design N/A, review gate still runs)
#   scaffold → skills/kit-scaffolder/scripts/scaffold_gate.sh && tools/gate.sh
#             && branding/scripts/branding_gate.sh   (app brand layer; consumer mode)
#   review   → tools/gate.sh && skills/kit-reviewer/scripts/review_checklist.sh
#   reproducibility → tools/region_diff.sh "$KIT_GOLDEN_DIR" "$KIT_FIXTURE_DIR/actual"
#             (the SKILL renders the fixture first — e.g. via tools/render_template.sh —
#             and sets both env vars, absolute paths; missing actual/ is exit 2 with
#             "skill must render fixture first", never a gate FAIL. Not a phase:
#             advance is unaffected.)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"            # app-box repo root — where gates/config live
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"   # absolute path to this script (selftest re-invokes)
CONFIG="$ROOT/config/app-box.config.json"           # R3: configurable values live here, never inline
# cfg <python-subscript>: read a value from CONFIG, empty on missing/unreadable.
cfg(){ python3 -c "import json;d=json.load(open('$CONFIG'));print(d$1)" 2>/dev/null || true; }
APP="${KIT_APP:-$ROOT}"                              # tree to operate on (default: the repo)
CONSUMER=0; [ "$APP" != "$ROOT" ] && CONSUMER=1      # consumer-app mode?
# Phantom-state guard: with KIT_APP unset, state defaults into the repo
# ($ROOT/pipeline/state). Invoked from a cwd OUTSIDE the repo tree (e.g. an app's root,
# forgetting KIT_APP=$PWD) that silently manufactures a split state inside the repo —
# the split-state phantom. Fail loud instead. Escape hatches: set
# KIT_PIPELINE_STATE_DIR explicitly, or KIT_MONOREPO=1 to confirm you really mean the
# repo itself. (cwd inside the repo tree = plausible intent, allowed.)
if [ -z "${KIT_APP:-}" ] && [ -z "${KIT_PIPELINE_STATE_DIR:-}" ] && [ "${KIT_MONOREPO:-0}" != "1" ]; then
  case "$(pwd)/" in
    "$ROOT/"*) : ;;  # standing inside the repo — fine
    *) echo "FAIL: KIT_APP is unset and cwd is outside the repo — state would land in $ROOT/pipeline/state (split-brain)." >&2
       echo "     consumer mode:  KIT_APP=\$PWD $0 $*" >&2
       echo "     repo mode:      cd $ROOT first, or prefix KIT_MONOREPO=1" >&2
       exit 2;;
  esac
fi
cd "$APP"                                            # operate in-target (gates are cwd/target-based)
STATE_DIR="${KIT_PIPELINE_STATE_DIR:-$APP/pipeline/state}"
STATE="$STATE_DIR/phase.json"
# escalation limit is config-driven (config/app-box.config.json escalationLimit); env wins.
ESC_LIMIT="${KIT_PIPELINE_REVIEW_ESCALATION:-$(cfg "['escalationLimit']")}"
ESC_LIMIT="${ESC_LIMIT:-3}"                          # fallback if config absent

DESIGN_GATE="${PIPELINE_DESIGN_GATE:-tools/vendor/enforce_design/enforce_design.dart}"
SCAFFOLD_GATE_A="${PIPELINE_SCAFFOLD_GATE_A:-skills/kit-scaffolder/scripts/scaffold_gate.sh}"
SCAFFOLD_GATE_B="${PIPELINE_SCAFFOLD_GATE_B:-tools/gate.sh}"
REVIEW_GATE_A="${PIPELINE_REVIEW_GATE_A:-tools/gate.sh}"
REVIEW_GATE_B="${PIPELINE_REVIEW_GATE_B:-skills/kit-reviewer/scripts/review_checklist.sh}"
REPRO_GATE="${PIPELINE_REPRO_GATE:-tools/region_diff.sh}"

# Branding gate (scaffold sub-gate C): validates the host app's generated brand
# layer (colors/icons/splash). App-only — at the monorepo root there is no app
# to brand, so it no-ops there (inverse of the monorepo-only tools/gate.sh).
BRANDING_GATE_DEFAULT="branding/scripts/branding_gate.sh"
[ "$CONSUMER" = 0 ] && BRANDING_GATE_DEFAULT="pass"
SCAFFOLD_GATE_C="${PIPELINE_BRANDING_GATE:-$BRANDING_GATE_DEFAULT}"

# Shell-structure gate (scaffold sub-gate D): validates the self-contained
# shell pattern on the host app's lib/ui/views tree (manifest-driven, S0–S4 —
# docs/plans/shell-structure-transformation.md). App-only — at the monorepo
# root there are no app shells, so it no-ops there (same inverse as the
# branding gate).
SHELL_STRUCTURE_GATE_DEFAULT="tools/vendor/shell_structure/shell_structure_gate.sh"
[ "$CONSUMER" = 0 ] && SHELL_STRUCTURE_GATE_DEFAULT="pass"
SCAFFOLD_GATE_D="${PIPELINE_SHELL_STRUCTURE_GATE:-$SHELL_STRUCTURE_GATE_DEFAULT}"

# Scaffold-coverage gate (scaffold sub-gate E): compares the frozen design's
# shell/surface map (design/<dir>/structure.json, guaranteed by freeze check 4)
# against what lib/ui/views actually contains. D validates the SHAPE of the
# shells that exist; nothing before E asked whether the design was BUILT — so an
# app could freeze 46 surfaces, scaffold 1, and pass every gate. App-only, same
# inverse as D.
SCAFFOLD_COVERAGE_GATE_DEFAULT="tools/vendor/scaffold_coverage/scaffold_coverage_gate.sh"
[ "$CONSUMER" = 0 ] && SCAFFOLD_COVERAGE_GATE_DEFAULT="pass"
SCAFFOLD_GATE_E="${PIPELINE_SCAFFOLD_COVERAGE_GATE:-$SCAFFOLD_COVERAGE_GATE_DEFAULT}"

# Prototype gate (design-dir freeze, ADR-0010): validates the host app's frozen
# design/ SSOT (shape / token vocab / exclusion coverage / headless render).
# App-only — at the monorepo root there is no app design dir, so it no-ops
# there (same inverse as the branding gate).
PROTO_GATE_DEFAULT="tools/vendor/freeze/freeze_design.sh"
[ "$CONSUMER" = 0 ] && PROTO_GATE_DEFAULT="pass"
PROTO_GATE="${PIPELINE_PROTOTYPE_GATE:-$PROTO_GATE_DEFAULT}"

# Consumer mode: tools/gate.sh is monorepo-only (cd's into stacked_kit/, validates
# kit docs/conventions). An app isn't a kit monorepo, so neutralize it with the
# `pass` sentinel (handled in run_gate). Explicit PIPELINE_*_GATE env still wins.
if [ "$CONSUMER" = 1 ]; then
  SCAFFOLD_GATE_B="${PIPELINE_SCAFFOLD_GATE_B:-pass}"
  REVIEW_GATE_A="${PIPELINE_REVIEW_GATE_A:-pass}"
fi

# ---- JSON helpers (python3 — repo already depends on it) ----
jget(){ python3 -c "
import json
d=json.load(open('$STATE'))
for p in '$1'.split('.'): d=d[p]
print(json.dumps(d))" 2>/dev/null; }
jwrite(){ python3 -c "import json,sys;d=json.loads(sys.stdin.read());json.dump(d,open('$STATE','w'),indent=2)" <<<"$1"; }

init_state(){
  mkdir -p "$STATE_DIR"
  local ts; ts=$(now)
  jwrite "{
    \"schema\":3,
    \"phase\":\"prototype\",
    \"createdAt\":\"$ts\",
    \"updatedAt\":\"$ts\",
    \"prototype\":{\"status\":\"ready\",\"gate\":\"$PROTO_GATE\",\"humanApproved\":false,\"rework\":0,\"ts\":null,\"attempts\":0},
    \"design\":{\"status\":\"blocked\",\"gate\":\"$DESIGN_GATE\",\"ts\":null,\"attempts\":0},
    \"scaffold\":{\"status\":\"blocked\",\"gate\":\"$SCAFFOLD_GATE_A + $SCAFFOLD_GATE_B + $SCAFFOLD_GATE_C + $SCAFFOLD_GATE_D + $SCAFFOLD_GATE_E\",\"ts\":null,\"attempts\":0},
    \"review\":{\"status\":\"blocked\",\"gate\":\"$REVIEW_GATE_A + $REVIEW_GATE_B\",\"approved\":false,\"rejections\":0,\"ts\":null,\"attempts\":0},
    \"dirty\":false,
    \"history\":[]
  }"
  echo ">> pipeline initialized at $STATE (phase=prototype, target=$APP$([ "$CONSUMER" = 1 ] && echo ", consumer mode"))"
}

require_state(){ [ -f "$STATE" ] || { echo "FAIL: no pipeline state — run 'pipeline.sh init' first" >&2; exit 2; }; }
# now(): device-local wall-clock WITH offset (astimezone attaches the local tz), so
# every stamp is self-evidently local — not a bare naive string a reader could mistake
# for UTC. Single source of truth: record/hist/review/init all route through it.
now(){ python3 -c 'import datetime;print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))'; }
# hist(): append a structured {ts, event} entry (was a bare string — no timestamp) and
# bump top-level updatedAt. Every state-changing op calls hist, so updatedAt tracks last activity for free.
hist(){ local ts; ts=$(now); python3 -c "import json;d=json.load(open('$STATE'));d.setdefault('history',[]).append({'ts':'$ts','event':'''$1'''});d['updatedAt']='$ts';json.dump(d,open('$STATE','w'),indent=2)"; }

# ms_now(): epoch milliseconds (run durations). python3 because bash 3.2 has no
# EPOCHREALTIME and macOS `date` has no %N.
ms_now(){ python3 -c 'import time;print(int(time.time()*1000))'; }

# record_run(): append one JSON line to pipeline/state/runs.jsonl — the per-invocation
# audit stream (ADR 0009 "comprehensive pipeline state"). The path derives from
# STATE's directory, so hermetic selftests (STATE in a tmp dir) never touch a real
# tree. Args pass through argv (never string-interpolated into the Python source),
# so failing signatures with quotes are safe. Best-effort (`|| true`): an audit
# append failure must not abort the FSM — there is deliberately no set -e.
record_run(){ # phase action result duration_ms [failing_signature]
  python3 - "$STATE" "$$" "$1" "$2" "$3" "$4" "${5:-}" <<'PY' || true
import json,os,sys,time,datetime
state,pid,phase,action,result,dur,sig=sys.argv[1:8]
rec={"run_id":"%d-%s"%(int(time.time()*1000),pid),
     "ts":datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
     "phase":phase,"action":action,"result":result,"duration_ms":int(dur)}
if sig: rec["failing_signature"]=sig
with open(os.path.join(os.path.dirname(state),"runs.jsonl"),"a") as f: f.write(json.dumps(rec)+"\n")
PY
}

run_gate(){
  local script="$1"; shift
  [ "$script" = "pass" ] && { echo "   (pass — no-op gate, consumer mode)"; return 0; }   # monorepo-only gate dropped for apps
  local full="$script"; [ -f "$full" ] || full="$ROOT/$script"   # absolute or repo-relative
  [ -f "$full" ] || { echo "   (gate script missing: $script — treating as FAIL)"; return 1; }
  local runner=bash
  case "$full" in *.dart) runner=dart;; esac
  $runner "$full" "$@" 2>&1 | sed 's/^/   /'
  return "${PIPESTATUS[0]}"
}

gate_prototype(){ echo ">> prototype gate ($PROTO_GATE)"
  # Non-UI slice bypass (grill Q6, ADR-0010): PROTOTYPE_TARGET=none records the
  # phase passed with an audit reason — same pattern as DESIGN_TARGET=none.
  [ "${PROTOTYPE_TARGET:-.}" = none ] && { echo "   (prototype N/A — non-UI slice; PROTOTYPE_TARGET=none)"; return 0; }
  # Native design producer (ADR-0015): PROTOTYPE_TARGET=native — kit-designer
  # authors the surfaces in-pipeline from a brief, so there is no external
  # design/ SSOT to freeze: freeze_design.sh is skipped and the phase records
  # passed WITH the audit reason in state (prototype.reason). Human Gate 1 is
  # untouched — advance still needs --approve (the human approves the design
  # brief/direction; the authored surfaces are reviewed in design + review).
  if [ "${PROTOTYPE_TARGET:-.}" = native ]; then
    python3 -c "import json;d=json.load(open('$STATE'));p=d.setdefault('prototype',{});p['reason']='native: kit-designer-authored design (ADR-0015)';json.dump(d,open('$STATE','w'),indent=2)"
    echo "   (prototype N/A — native: kit-designer-authored design (ADR-0015); Human Gate 1 still keys advance)"
    return 0
  fi
  run_gate "$PROTO_GATE" "$APP"; }

gate_design(){  echo ">> design gate ($DESIGN_GATE)"
  # Non-UI slice (guard / routing / service) has no design surface to validate.
  # DESIGN_TARGET=none records design passed without enforce_design, with an audit
  # reason — the tree-wide review gate (review_checklist.sh) stays the backstop.
  # (PIPELINE_DESIGN_GATE=pass also no-ops the gate but records no reason.)
  [ "${DESIGN_TARGET:-.}" = none ] && { echo "   (design N/A — non-UI slice; DESIGN_TARGET=none)"; return 0; }
  run_gate "$DESIGN_GATE" "${DESIGN_TARGET:-.}"; }
gate_scaffold(){ echo ">> scaffold gate ($SCAFFOLD_GATE_A)"; run_gate "$SCAFFOLD_GATE_A" || return 1
                  echo ">> scaffold gate ($SCAFFOLD_GATE_B)"; run_gate "$SCAFFOLD_GATE_B" || return 1
                  echo ">> branding gate ($SCAFFOLD_GATE_C)"; run_gate "$SCAFFOLD_GATE_C" || return 1
                  echo ">> shell-structure gate ($SCAFFOLD_GATE_D)"; run_gate "$SCAFFOLD_GATE_D" || return 1
                  # E closes the seam D leaves open: D validates the SHAPE of the
                  # shells that exist, never whether the frozen design was built.
                  echo ">> scaffold-coverage gate ($SCAFFOLD_GATE_E)"; run_gate "$SCAFFOLD_GATE_E"; }
gate_review(){  echo ">> review gate ($REVIEW_GATE_A)"; run_gate "$REVIEW_GATE_A" || return 1
                  echo ">> review gate ($REVIEW_GATE_B)"; run_gate "$REVIEW_GATE_B"; }

# gate_reproducibility: the Golden Gate (ADR 0009). The SKILL regenerates its
# fixture first (render_template.sh → $KIT_FIXTURE_DIR/actual/); this gate only
# DIFFS — region_diff.sh expected=$KIT_GOLDEN_DIR actual=$KIT_FIXTURE_DIR/actual.
# Missing inputs are exit 2 (usage/input error — "skill must render fixture
# first"), never a gate FAIL. Env: KIT_FIXTURE_DIR + KIT_GOLDEN_DIR, absolutized
# here so consumer mode's cd can't confuse relative paths.
gate_reproducibility(){
  local fx="${KIT_FIXTURE_DIR:-}" gd="${KIT_GOLDEN_DIR:-}"
  if [ -z "$fx" ] || [ -z "$gd" ]; then
    echo "FAIL: gate reproducibility needs KIT_FIXTURE_DIR and KIT_GOLDEN_DIR (the skill sets both — see skills/_pipeline.md)"
    return 2
  fi
  [ -d "$fx" ] || { echo "FAIL: KIT_FIXTURE_DIR not found: $fx"; return 2; }
  fx="$(cd "$fx" && pwd)"
  if [ ! -d "$fx/actual" ]; then
    echo "FAIL: $fx/actual missing — the skill must render the fixture first:"
    echo "  tools/render_template.sh <template> <manifest.json> -o $fx/actual/<file>"
    echo "then re-run: pipeline.sh gate reproducibility"
    return 2
  fi
  if [ ! -d "$gd" ]; then
    echo "FAIL: KIT_GOLDEN_DIR not found: $gd — first run? render the fixture, eyeball the output, then adopt it: pipeline.sh golden --accept"
    return 2
  fi
  gd="$(cd "$gd" && pwd)"
  echo ">> reproducibility gate ($REPRO_GATE $gd $fx/actual)"
  run_gate "$REPRO_GATE" "$gd" "$fx/actual"
}

record(){ # phase status — setdefault so non-FSM gates (reproducibility) get a
  # status block in phase.json without a schema bump, and schema-2 states from
  # before the Golden Gate keep working.
  local ts; ts=$(now)
  python3 -c "import json;d=json.load(open('$STATE'));p=d.setdefault('$1',{});p['status']='$2';p['ts']='$ts';p['attempts']=p.get('attempts',0)+1;json.dump(d,open('$STATE','w'),indent=2)"
}

do_gate(){
  require_state
  local p="$1"; shift
  local rc start end dur outtmp sig=""
  outtmp=$(mktemp); start=$(ms_now)
  # tee: streams the gate output live AND captures it, so a failing run record
  # can carry the failing-check signature (same extraction as the loop driver).
  case "$p" in
    prototype)
      # Human Gate 1 verdicts ride the same command (grill D5): --approve/--rework
      # are recorded by the verdict seam, not by a gate run.
      case "${1:-}" in
        --approve|--rework) rm -f "$outtmp"; do_prototype_verdict "${1#--}" "${2:-}"; return $?;;
      esac
      gate_prototype 2>&1 | tee "$outtmp"; rc=${PIPESTATUS[0]};;
    design)   gate_design   2>&1 | tee "$outtmp"; rc=${PIPESTATUS[0]};;
    scaffold) gate_scaffold 2>&1 | tee "$outtmp"; rc=${PIPESTATUS[0]};;
    review)   gate_review   2>&1 | tee "$outtmp"; rc=${PIPESTATUS[0]};;
    reproducibility) gate_reproducibility 2>&1 | tee "$outtmp"; rc=${PIPESTATUS[0]};;
    *) echo "unknown phase: $p (prototype|design|scaffold|review|reproducibility)" >&2; rm -f "$outtmp"; exit 2;;
  esac
  end=$(ms_now); dur=$((end-start))
  # Input/usage error (Golden Gate: unset env, fixture not rendered; freeze:
  # missing render backend, bad invocation): an ERROR, not a gate failure —
  # phase status untouched, exit 2 with the guidance.
  if { [ "$p" = reproducibility ] || [ "$p" = prototype ]; } && [ "$rc" -eq 2 ]; then
    record_run "$p" gate error "$dur"
    hist "gate $p -> ERROR (env/input — see gate output)"
    rm -f "$outtmp"
    echo ">> $p gate ERROR (exit 2) — see above" >&2
    return 2
  fi
  [ "$rc" -ne 0 ] && sig=$(grep -iE 'fail|✗|error|missing|blocked|drift' "$outtmp" | sort -u | tr '\n' ';')
  rm -f "$outtmp"
  record "$p" "$([ $rc -eq 0 ] && echo passed || echo failed)"
  record_run "$p" gate "$([ $rc -eq 0 ] && echo pass || echo fail)" "$dur" "$sig"
  hist "gate $p -> $([ $rc -eq 0 ] && echo PASS || echo FAIL)"
  [ $rc -eq 0 ] && echo ">> $p gate PASSED" || { echo ">> $p gate FAILED — not advancing" >&2; return 1; }
}

# prototype verdict (Human Gate 1, grill D5 / ADR-0010): the deterministic
# freeze gate records `passed`; the HUMAN's browser verdict rides the same
# command —
#   pipeline.sh gate prototype --approve [note]   (freeze must be green first)
#   pipeline.sh gate prototype --rework <note>    (back to HTML-level rework)
# approve is the SECOND KEY advance requires (deterministic gate + human eye —
# the generator never grades its own homework). rework pulls the FSM back to
# prototype from ANY later phase and re-blocks downstream: the design SSOT
# changed, so everything derived from it is stale.
do_prototype_verdict(){
  require_state
  local v="$1" note="${2:-}" start end; start=$(ms_now)
  if [ "$v" = approve ]; then
    local st; st=$(jget prototype.status | tr -d '"')
    [ "$st" = passed ] || { echo "FAIL: cannot approve — prototype freeze gate is '$st' (run 'pipeline.sh gate prototype' first)" >&2; exit 1; }
    python3 -c "import json;d=json.load(open('$STATE'));d['prototype']['humanApproved']=True;json.dump(d,open('$STATE','w'),indent=2)"
    end=$(ms_now); record_run prototype verdict approved "$((end-start))"
    hist "prototype APPROVED (Human Gate 1)${note:+ — $note}"; echo ">> prototype APPROVED by human — 'pipeline.sh advance' moves to design"
  else
    [ -n "$note" ] || { echo "usage: pipeline.sh gate prototype --rework <note>" >&2; exit 2; }
    local n
    n=$(python3 -c "
import json
d=json.load(open('$STATE'))
p=d.setdefault('prototype',{}); p['humanApproved']=False; p['status']='ready'; p['rework']=p.get('rework',0)+1
d['phase']='prototype'
for k in ('design','scaffold'):
    if k in d: d[k]['status']='blocked'
json.dump(d,open('$STATE','w'),indent=2); print(p['rework'])")
    end=$(ms_now); record_run prototype verdict rework "$((end-start))"
    hist "prototype REWORK #$n — $note (HTML-level only; freeze re-runs on next gate)"
    echo ">> prototype REWORK #$n — phase back to prototype; rework at the HTML level, then re-run 'pipeline.sh gate prototype'" >&2
    return 1
  fi
}

do_advance(){
  require_state
  local start end; start=$(ms_now)
  local phase; phase=$(jget "phase" | tr -d '"')
  local cur; cur=$(jget "$phase.status" | tr -d '"')
  if [ "$cur" != passed ]; then
    end=$(ms_now); record_run "$phase" advance refused "$((end-start))"
    echo "FAIL: cannot advance — $phase gate is '$cur' (must be passed)" >&2; exit 1
  fi
  # Human Gate 1 second key (grill D5): a green freeze is necessary but not
  # sufficient — the human must have approved the design in the browser.
  if [ "$phase" = prototype ]; then
    local ha; ha=$(jget prototype.humanApproved)
    if [ "$ha" != true ]; then
      end=$(ms_now); record_run "$phase" advance refused "$((end-start))"
      echo "FAIL: cannot advance — Human Gate 1 has not approved (freeze is green; review the served design/ then 'pipeline.sh gate prototype --approve [note]')" >&2; exit 1
    fi
  fi
  local next=""
  case "$phase" in prototype) next=design;; design) next=scaffold;; scaffold) next=review;; review) next=review;; esac
  python3 -c "import json;d=json.load(open('$STATE'));d['phase']='$next';d['$next']['status']='ready';json.dump(d,open('$STATE','w'),indent=2)"
  end=$(ms_now); record_run "$phase" advance ok "$((end-start))"
  hist "advance $phase -> $next"; echo ">> phase: $phase → $next"
  # Commit Checkpoint proposal (advisory): gate-green work should not linger
  # uncommitted — dispose with `pipeline.sh checkpoint [note]`.
  # `return 0` is LOAD-BEARING, not decoration: a bare trailing `[ … ] && echo`
  # makes the test the function's exit status, so on a CLEAN tree (test false,
  # && short-circuits) advance returned 1 *on success* — and do_loop reads that
  # rc and falsely escalated "gate green but advance refused", i.e. the
  # unattended loop only worked while work was uncommitted. Selftest missed it
  # because its only advance exit-code case dirties the tree first; the
  # clean-tree mirror case now lives beside it. Never let this be the last
  # statement without an explicit status.
  [ -n "$(git status --porcelain 2>/dev/null)" ] && echo ">> checkpoint suggested: uncommitted work — 'pipeline.sh checkpoint [note]'"
  return 0
}

do_review(){
  require_state
  local start end; start=$(ms_now)
  local verdict="$1" reason="${2:-}" back="${3:-design}"
  local phase; phase=$(jget phase | tr -d '"')
  if [ "$phase" != review ]; then
    end=$(ms_now); record_run "$phase" review refused "$((end-start))"
    echo "FAIL: review verdict only valid in review phase (now: $phase)" >&2; exit 1
  fi
  if [ "$verdict" = approve ]; then
    local ts; ts=$(now)
    python3 -c "import json;d=json.load(open('$STATE'));d['review'].update({'approved':True,'status':'approved','ts':'$ts'});d['dirty']=False;json.dump(d,open('$STATE','w'),indent=2)"
    end=$(ms_now); record_run review review approved "$((end-start))"
    hist "review APPROVED${reason:+ — $reason}"; echo ">> review APPROVED — pipeline done-eligible"
  elif [ "$verdict" = reject ]; then
    case "$back" in prototype|design|scaffold) ;; *) echo "usage: pipeline.sh review reject [reason] [prototype|design|scaffold]" >&2; exit 2;; esac
    # Human override: KIT_PIPELINE_FORCE_RESET clears the rejection counter first, so
    # the forced reject counts as #1 (the standalone `reset` subcommand does the same).
    # Both exist so a human can unblock an escalated pipeline without hand-editing state.
    if [ "${KIT_PIPELINE_FORCE_RESET:-0}" = 1 ]; then
      python3 -c "import json;d=json.load(open('$STATE'));d['review']['rejections']=0;json.dump(d,open('$STATE','w'),indent=2)"
      hist "review reject — KIT_PIPELINE_FORCE_RESET cleared rejection counter"
    fi
    local cur_rej; cur_rej=$(jget review.rejections | tr -d '"')
    # Hard stop: the reject that REACHES the limit still loops back (and fires the
    # ESCALATE line below); a reject attempted PAST the limit is refused — exit 3,
    # state untouched — until a human clears the counter. `approve` and `gate` are
    # unaffected. (Advisory ESCALATE echo replaced with a real hard block, not a halt
    # of approve/gate — only the reject loop is gated.)
    if [ "$cur_rej" -ge "$ESC_LIMIT" ]; then
      end=$(ms_now); record_run review review blocked "$((end-start))"
      hist "review REJECT BLOCKED — $cur_rej rejections ≥ escalation limit $ESC_LIMIT (human override required)"
      echo ">> BLOCKED: $cur_rej rejections ≥ escalation limit $ESC_LIMIT — review cannot reject again." >&2
      echo ">> Human override: run 'pipeline.sh reset' to clear the counter, or prepend" >&2
      echo ">> KIT_PIPELINE_FORCE_RESET=1 to this reject (clears + counts as #1)." >&2
      exit 3
    fi
    local rej; rej=$(python3 -c "
import json
d=json.load(open('$STATE'))
r=d['review']; r['rejections']+=1; r['approved']=False; r['status']='rejected'
d['phase']='$back'; d['$back']['status']='ready'
if '$back' in ('prototype','design'): d['scaffold']['status']='blocked'
if '$back'=='prototype': d['design']['status']='blocked'
print(r['rejections']); json.dump(d,open('$STATE','w'),indent=2)")
    end=$(ms_now); record_run review review rejected "$((end-start))"
    hist "review REJECTED #$rej -> back to $back${reason:+ — $reason}"
    if [ "$rej" -ge "$ESC_LIMIT" ]; then echo ">> ESCALATE: $rej rejections ≥ limit $ESC_LIMIT — human decision required (next reject will be BLOCKED → exit 3)" >&2; fi
    echo ">> review REJECTED (#$rej) — phase set back to $back" >&2; return 1
  else echo "usage: pipeline.sh review approve|reject [reason] [prototype|design|scaffold]" >&2; exit 2; fi
}

do_touch(){
  require_state
  local start end; start=$(ms_now)
  local note="${1:-code changed by ungated skill}"
  python3 -c "import json;d=json.load(open('$STATE'));d['dirty']=True;d['review']['approved']=False;d['review']['status']='pending';json.dump(d,open('$STATE','w'),indent=2)"
  end=$(ms_now); record_run "$(jget phase | tr -d '"')" touch ok "$((end-start))"
  hist "touch — $note"; echo ">> pipeline marked dirty — reviewer must re-approve before done"
}

# checkpoint [note] — Commit Checkpoint (CONTEXT.md § Reproducibility): commit the
# current tree as a deliberate, recorded checkpoint. The pipeline PROPOSES (advance/
# done print the suggestion on a dirty tree); the operator/agent DISPOSES by invoking
# this — never automatic, because a script cannot judge tree contents. Gate-green
# checkpoints are the norm (current phase gate passed, review approved, or the Golden
# Gate passed); mid-phase checkpoints are allowed but recorded gate_green=false.
# Appends one JSON line to pipeline/state/checkpoints.jsonl {run_id, ts, phase,
# gate_green, sha, message} + the usual run record. git identity comes from the
# repo's own config. Exit 0 on success or clean tree; exit 1 outside a git work
# tree or on commit failure.
do_checkpoint(){
  require_state
  local note="${1:-}" start end; start=$(ms_now)
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "FAIL: not a git work tree — checkpoint needs git" >&2; exit 1; }
  local phase green
  phase=$(jget phase | tr -d '"')
  green=$(python3 -c "
import json
d=json.load(open('$STATE'))
g = d.get(d['phase'],{}).get('status')=='passed' or d['review'].get('approved') or d.get('reproducibility',{}).get('status')=='passed'
print('true' if g else 'false')")
  [ -z "$(git status --porcelain)" ] && { echo ">> nothing to checkpoint (tree clean)"; exit 0; }
  [ "$green" = true ] || echo ">> WARN: no gate green yet — checkpointing mid-phase work (recorded gate_green=false)" >&2
  local msg="chore(pipeline): checkpoint [$phase]${note:+ — $note}"
  git add -A && git commit -m "$msg" || { echo "FAIL: git commit failed" >&2; exit 1; }
  local sha; sha=$(git rev-parse --short HEAD)
  end=$(ms_now)
  python3 - "$STATE" "$$" "$phase" "$green" "$sha" "$msg" <<'PY' || true
import json,os,sys,time,datetime
state,pid,phase,green,sha,msg=sys.argv[1:7]
rec={"run_id":"%d-%s"%(int(time.time()*1000),pid),
     "ts":datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
     "phase":phase,"gate_green":green=="true","sha":sha,"message":msg}
with open(os.path.join(os.path.dirname(state),"checkpoints.jsonl"),"a") as f: f.write(json.dumps(rec)+"\n")
PY
  record_run "$phase" checkpoint ok "$((end-start))"
  hist "checkpoint $sha [$phase]${note:+ — $note}"
  echo ">> checkpoint COMMITTED $sha: $msg"
  git show --stat --format= HEAD | tail -3 | sed 's/^/   /'
}

done_ok(){
  require_state
  python3 -c "
import json,sys
d=json.load(open('$STATE'));r=d['review']
sys.exit(0 if (d['phase']=='review' and r['approved'] and not d['dirty']) else 1)"
}
do_status(){
  require_state
  echo "target : $APP$([ "$CONSUMER" = 1 ] && echo " (consumer mode)")"
  python3 -c "
import json;d=json.load(open('$STATE'))
print('phase :',d['phase'])
p=d.get('prototype',{})
print('prototype:',p.get('status','-'),'humanApproved='+str(p.get('humanApproved')),'rework='+str(p.get('rework',0)))
for k in ['design','scaffold']: print(f'{k:9}:',d[k]['status'])
r=d['review'];print('review   :',r['status'],'approved='+str(r['approved']),'rejections='+str(r['rejections']))
if 'reproducibility' in d: print('repro    :',d['reproducibility'].get('status'))
print('dirty    :',d['dirty'])"
  done_ok >/dev/null 2>&1 && echo 'DONE   : YES' || echo 'DONE   : NO'
  # last Commit Checkpoint, if any (ledger lives next to phase.json)
  [ -f "$(dirname "$STATE")/checkpoints.jsonl" ] && tail -1 "$(dirname "$STATE")/checkpoints.jsonl" | python3 -c "import json,sys;r=json.loads(sys.stdin.read());print('ckpt   :',r['sha'],r['ts'],'green='+str(r['gate_green']))"
}

do_done(){ require_state; done_ok && { [ -n "$(git status --porcelain 2>/dev/null)" ] && echo ">> WARN: done-eligible with uncommitted work — 'pipeline.sh checkpoint [note]'"; echo ">> DONE — reviewer-approved & clean"; exit 0; } || { echo "FAIL: not done — review must approve (and pipeline clean)" >&2; exit 1; }; }

# golden --accept: the ONLY way a Golden changes (ADR 0009 — deliberate,
# reviewer-driven, audit-trailed; NEVER automatic). Replaces $KIT_GOLDEN_DIR
# with $KIT_FIXTURE_DIR/actual (a full tree replace, so files deleted by the
# skill don't linger as false "unexpected file" drift), then appends
# {ts, who: reviewer, fixture} to pipeline/state/golden_audit.jsonl plus a run
# record to runs.jsonl.
do_golden(){
  require_state
  [ "${1:-}" = "--accept" ] || { echo "usage: pipeline.sh golden --accept   # adopt \$KIT_FIXTURE_DIR/actual as the new \$KIT_GOLDEN_DIR (deliberate)" >&2; exit 2; }
  local fx="${KIT_FIXTURE_DIR:-}" gd="${KIT_GOLDEN_DIR:-}" start end
  [ -n "$fx" ] && [ -n "$gd" ] || { echo "FAIL: golden --accept needs KIT_FIXTURE_DIR and KIT_GOLDEN_DIR (the skill sets both — see skills/_pipeline.md)" >&2; exit 2; }
  [ -d "$fx/actual" ] || { echo "FAIL: $fx/actual missing — the skill must render the fixture first (render_template.sh), then re-run" >&2; exit 2; }
  fx="$(cd "$fx" && pwd)"
  mkdir -p "$gd"; gd="$(cd "$gd" && pwd)"
  # Safety, BEFORE the rm -rf below: the golden dir must be a real, dedicated
  # directory — never /, HOME, the kit root, the fixture itself, or a
  # container/containee of the fixture (prefix checks use trailing slashes so
  # /a/barc and /a/bar don't false-positive).
  case "$gd" in /|"$HOME"|"$ROOT"|"$fx"|"$fx/actual") echo "FAIL: unsafe KIT_GOLDEN_DIR: $gd" >&2; exit 2;; esac
  case "$fx/" in "$gd/"*) echo "FAIL: KIT_GOLDEN_DIR ($gd) must not contain KIT_FIXTURE_DIR ($fx)" >&2; exit 2;; esac
  case "$gd/" in "$fx/"*) echo "FAIL: KIT_GOLDEN_DIR ($gd) must not live inside KIT_FIXTURE_DIR ($fx)" >&2; exit 2;; esac
  start=$(ms_now)
  rm -rf "$gd"; mkdir -p "$gd"
  cp -R "$fx/actual/." "$gd/"
  end=$(ms_now)
  python3 - "$STATE" "$$" "$fx" "$gd" <<'PY' || true
import json,os,sys,time,datetime
state,pid,fx,gd=sys.argv[1:5]
rec={"run_id":"%d-%s"%(int(time.time()*1000),pid),
     "ts":datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
     "who":"reviewer","fixture":fx,"golden":gd}
with open(os.path.join(os.path.dirname(state),"golden_audit.jsonl"),"a") as f: f.write(json.dumps(rec)+"\n")
PY
  record_run "$(jget phase | tr -d '"')" golden accepted "$((end-start))"
  hist "golden --accept — $fx/actual -> $gd (reviewer)"
  echo ">> golden ACCEPTED: $fx/actual → $gd (audit: $(dirname "$STATE")/golden_audit.jsonl)"
}

# reset: human override for an escalated review loop. Clears ONLY review.rejections
# (phase, approval, dirty untouched) so rejects are unblocked. Pairs with the
# KIT_PIPELINE_FORCE_RESET=1 inline override on `review reject`.
do_reset(){
  require_state
  python3 -c "import json;d=json.load(open('$STATE'));d['review']['rejections']=0;json.dump(d,open('$STATE','w'),indent=2)"
  hist "reset — review rejection counter cleared to 0 (human override)"
  echo ">> review rejection counter cleared to 0 — rejects unblocked"
}

# loop: automated evaluator-optimizer driver over the gated pipeline (Anthropic's
# pattern, hardened). Runs the current phase's gate; on PASS it advances — a
# review-phase pass leaves the terminal `approve` to the reviewer unless
# --auto-approve (the deterministic gate is the independent oracle; finding: never
# let the generator grade its own homework). On FAIL it captures the failing-check
# signature, ESCALATES on oscillation (same signature twice — which also catches a
# no-op fix: a fixer that changes nothing yields an identical failure signature),
# and delegates the fix to --fix-cmd, the generator seam (pipeline.sh stays
# LLM-free; the fixer is an external command — an agent, a skill, a human helper).
# The evaluator→generator payload is structured env, not prose:
# PIPELINE_LOOP_CRITIQUE (raw gate output), PIPELINE_LOOP_SIGNATURE (the sorted
# failing-check lines — what failed / which check), PIPELINE_LOOP_PHASE/ITER/MAX
# (position in the budget). Roles stay separate — the gates + reviewer are the
# evaluator; the fix-cmd is the generator; the agent doing the work never grades it.
# Budget defaults to ESC_LIMIT so the loop's ceiling and the reviewer's rejection
# ceiling are ONE number. On non-convergence it exits 4 with the last critique +
# `git diff --stat` — never a silent stop (the OpenHands #10571 RuntimeError-on-cap
# anti-pattern). bash 3.2-safe: no arrays (seen-signatures is a newline string).
do_loop(){
  require_state
  local max="$ESC_LIMIT" auto_approve=0 dry_run=0 fix_cmd=""
  while [ $# -gt 0 ]; do case "$1" in
    --max) max="$2"; shift 2;;
    --auto-approve) auto_approve=1; shift;;
    --dry-run) dry_run=1; shift;;
    --fix-cmd) fix_cmd="$2"; shift 2;;
    *) echo "usage: pipeline.sh loop [--max N] [--fix-cmd '…'] [--auto-approve] [--dry-run]" >&2; exit 2;;
  esac; done
  local phase out rc sig seen_nl=""
  phase=$(jget phase | tr -d '"')
  local iter=0 fix_rounds=0
  while [ "$iter" -lt "$max" ]; do
    iter=$((iter+1))
    echo "=== loop round $iter/$max (phase=$phase) ==="
    out=$(do_gate "$phase" 2>&1); rc=$?
    # keep in sync with do_gate's signature regex (incl. 'drift') — parity is what
    # makes oscillation detection compare like with like (DIV-3 fix)
    sig=$(printf '%s\n' "$out" | grep -iE 'fail|✗|error|missing|blocked|drift' | sort -u | tr '\n' ';')
    [ -n "$sig" ] || sig="<gate-rc=$rc-no-fail-lines>"
    if [ "$rc" -eq 0 ]; then
      if [ "$phase" = review ]; then
        if [ "$auto_approve" = 1 ]; then
          do_review approve "loop auto-approve (gate green @iter $iter)" >/dev/null
          hist "loop CONVERGED @iter $iter (auto-approved)"; echo ">> loop CONVERGED — auto-approved @iter $iter"
          # Second-opinion trigger (the adversarial-review step): when the loop converged
          # unattended THROUGH the fixer, the deterministic gate was the only judge that
          # ran — advise an independent re-check as the guard against gate-gaming.
          [ "$fix_rounds" -gt 0 ] && echo ">> second-opinion suggested: auto-approved after $fix_rounds fix round(s) — have an independent reviewer (fresh context / human) re-check before 'done'"
          done_ok >/dev/null 2>&1 && echo ">> pipeline DONE-eligible (run 'pipeline.sh done')" || echo ">> WARN: approved but not done-eligible"
          return 0
        fi
        hist "loop: review gate GREEN @iter $iter — awaiting reviewer approve"
        echo ">> review gate GREEN @iter $iter — run 'pipeline.sh review approve' to finish (or --auto-approve)"; return 0
      fi
      # BUG-1 fix: do_advance's refusals (e.g. Human Gate 1 unapproved) hard-exit;
      # command substitution runs it in a subshell so the loop survives, and a
      # blocked advance escalates with payload (exit 4) — never a silent stop.
      local adv_out adv_rc
      adv_out=$(do_advance 2>&1); adv_rc=$?
      if [ "$adv_rc" -ne 0 ]; then
        hist "loop ESCALATE (advance blocked) @iter $iter — gate green but advance refused"
        echo ">> ESCALATE @iter $iter: gate green but advance refused — loop cannot proceed unattended." >&2
        _loop_escalate "$adv_out"; return 4
      fi
      case "$phase" in prototype) phase=design;; design) phase=scaffold;; scaffold) phase=review;; esac
      seen_nl=""; continue                   # new phase → new gate set; reset oscillation window
    fi
    # gate RED — oscillation guard (subsumes no-op: an unchanged tree → identical sig)
    if printf '%s\n' "$seen_nl" | grep -qxF -- "$sig"; then
      hist "loop ESCALATE (oscillation) @iter $iter — failure signature recurred"
      echo ">> ESCALATE @iter $iter: failure signature recurred (oscillation / no-op fix) — not converging." >&2
      _loop_escalate "$out"; return 4
    fi
    seen_nl="$seen_nl$sig"$'\n'
    if [ "$dry_run" = 1 ]; then
      echo ">> [dry-run] gate FAILED; would feed this critique to --fix-cmd:"; printf '%s\n' "$out" | sed 's/^/   /'; return 0
    fi
    if [ -z "$fix_cmd" ]; then
      echo ">> gate FAILED @iter $iter — no --fix-cmd wired (the generator seam). Critique:" >&2
      printf '%s\n' "$out" | sed 's/^/   /' >&2
      echo ">> Apply the fix & re-run 'pipeline.sh loop', or pass --fix-cmd '<generator>'." >&2
      _loop_escalate "$out"; return 4
    fi
    echo ">> invoking fix-cmd (@iter $iter)…"
    if ! PIPELINE_LOOP_CRITIQUE="$out" PIPELINE_LOOP_SIGNATURE="$sig" PIPELINE_LOOP_PHASE="$phase" PIPELINE_LOOP_ITER="$iter" PIPELINE_LOOP_MAX="$max" bash -c "$fix_cmd"; then
      echo ">> fix-cmd exited non-zero — escalating." >&2; _loop_escalate "$out"; return 4
    fi
    fix_rounds=$((fix_rounds+1))
    do_touch "loop fix round $iter (phase $phase)" >/dev/null
  done
  hist "loop ESCALATE (budget) — $iter/$max rounds without convergence"
  echo ">> ESCALATE: $iter/$max rounds exhausted without convergence — human decision required." >&2
  _loop_escalate "(budget exhausted after $iter rounds)"; return 4
}

_loop_escalate(){   # always deliver the last critique + tree diff (CodeRabbit: never empty-handed)
  echo "----- LAST CRITIQUE -----"; printf '%s\n' "$1" | sed 's/^/   /'
  echo "----- TREE DIFF (stat) -----"; git diff --stat 2>/dev/null | sed 's/^/   /' || echo "   (not a git tree / clean)"
  echo ">> Escalation is NOT a silent stop — hand the above to a human, or re-run with --fix-cmd."
}

selftest(){
  # Hermeticity: this is a self-test of pipeline.sh, not of the shell that
  # launched it. KIT_APP / KIT_PIPELINE_STATE_DIR / KIT_MONOREPO are consumed at
  # the *top* of this file — long before any case runs — where they re-point
  # STATE_DIR and `cd "$APP"`. Inheriting them silently puts the whole suite in
  # consumer mode, and cases that assert monorepo-root behaviour ("prototype gate
  # no-ops at the monorepo root") then cannot pass by construction: a green
  # pipeline.sh gets reported as broken, which is how KIT_APP came to look like a
  # defect rather than an invocation artifact. Re-exec once with the three
  # scrubbed so the suite always measures the same thing.
  #
  # `cd "$ROOT"` before the exec is load-bearing: the phantom-state guard keys on
  # cwd once KIT_APP is gone, and by this point line 86 has already left us in
  # $APP — outside the kit — so the re-exec would trip the guard and exit 2.
  if [ -n "${KIT_APP:-}" ] || [ -n "${KIT_PIPELINE_STATE_DIR:-}" ] || [ -n "${KIT_MONOREPO:-}" ]; then
    echo "note: re-running selftest with KIT_APP/KIT_PIPELINE_STATE_DIR/KIT_MONOREPO scrubbed (hermetic monorepo mode)" >&2
    cd "$ROOT" || exit 1
    exec env -u KIT_APP -u KIT_PIPELINE_STATE_DIR -u KIT_MONOREPO bash "$SELF" selftest
  fi
  local TMP; TMP="$(mktemp -d)"; STATE="$TMP/phase.json"; STATE_DIR="$TMP"; local P=0 F=0
  # hermetic stub gates (deterministic exit 0) — exercises do_gate delegation + FSM, not the real gates
  printf '#!/usr/bin/env bash\necho stub-ok; exit 0\n' > "$TMP/stub.sh"; chmod +x "$TMP/stub.sh"
  DESIGN_GATE="$TMP/stub.sh" SCAFFOLD_GATE_A="$TMP/stub.sh" SCAFFOLD_GATE_B="$TMP/stub.sh"
  REVIEW_GATE_A="$TMP/stub.sh" REVIEW_GATE_B="$TMP/stub.sh" PROTO_GATE="$TMP/stub.sh"
  chk(){ [ "$1" = "$2" ] && P=$((P+1)) || { F=$((F+1)); echo "  FAIL: expected [$2] got [$1] — $3"; }; }
  # walk helpers — full-chain honest walks. prototype needs the two-key (grill
  # D5): freeze gate green + human approval before advance lets go.
  w_design(){ do_gate prototype >/dev/null 2>&1; do_gate prototype --approve w >/dev/null 2>&1; do_advance >/dev/null; }
  w_scaffold(){ w_design; do_gate design >/dev/null 2>&1; do_advance >/dev/null; }
  w_review(){ w_scaffold; do_gate scaffold >/dev/null 2>&1; do_advance >/dev/null; }
  init_state >/dev/null;            chk "$(jget phase|tr -d '"')" prototype "init phase"
  do_gate prototype >/dev/null 2>&1; chk "$(jget prototype.status|tr -d '"')" passed "prototype gate runs+records"
  ( do_advance ) >/dev/null 2>&1;   chk "$?" 1 "advance refused before Human Gate 1 approval"
  ( do_gate prototype --approve ) >/dev/null 2>&1; chk "$?" 0 "--approve accepted once freeze is green"
  chk "$(jget prototype.humanApproved)" "true" "prototype --approve records human approval"
  do_advance >/dev/null;             chk "$(jget phase|tr -d '"')" design "advance prototype->design (two-key)"
  do_gate design >/dev/null 2>&1;    chk "$(jget design.status|tr -d '"')" passed "design gate runs+records"
  do_advance >/dev/null;             chk "$(jget phase|tr -d '"')" scaffold "advance design->scaffold"
  do_gate scaffold >/dev/null 2>&1;  chk "$(jget scaffold.status|tr -d '"')" passed "scaffold gate"
  do_advance >/dev/null;             chk "$(jget phase|tr -d '"')" review "advance scaffold->review"
  do_gate review >/dev/null 2>&1;    chk "$(jget review.status|tr -d '"')" passed "review gate"
  done_ok >/dev/null 2>&1;          chk "$?" 1 "done rejected before approval"
  do_review approve >/dev/null;      chk "$(jget review.approved)" "true" "review approve"
  done_ok >/dev/null 2>&1;          chk "$?" 0 "done accepted after approval"
  do_touch >/dev/null;               chk "$(jget dirty)" "true" "touch sets dirty"
  chk "$(jget review.approved)" "false" "touch resets approval (reviewer last word)"
  done_ok >/dev/null 2>&1;          chk "$?" 1 "done rejected after touch"
  do_review reject noise >/dev/null 2>&1; chk "$(jget review.rejections)" "1" "reject increments"
  chk "$(jget phase|tr -d '"')" design "reject loops phase back to design"
  chk "$(jget design.status|tr -d '"')" ready "reject re-opens design"
  chk "$(jget scaffold.status|tr -d '"')" blocked "reject re-blocks scaffold"
  do_gate design >/dev/null 2>&1; do_advance >/dev/null; do_gate scaffold >/dev/null 2>&1; do_advance >/dev/null
  do_gate review >/dev/null 2>&1
  do_review reject noise scaffold >/dev/null 2>&1; chk "$(jget phase|tr -d '"')" scaffold "reject can target scaffold"
  chk "$(jget scaffold.status|tr -d '"')" ready "targeted reject re-opens scaffold"
  # rejection-escalation hard stop: the 3rd reject REACHES the limit (still loops,
  # fires ESCALATE); the 4th is BLOCKED — exit 3, counter+phase unchanged — until a
  # human clears the counter via `reset` or KIT_PIPELINE_FORCE_RESET=1. do_review runs
  # in a (subshell) so its `exit 3` ends only the subshell, not the selftest.
  do_gate scaffold >/dev/null 2>&1; do_advance >/dev/null; do_gate review >/dev/null 2>&1
  do_review reject noise design >/dev/null 2>&1; chk "$(jget review.rejections)" "3" "3rd reject reaches escalation limit"
  do_gate design >/dev/null 2>&1; do_advance >/dev/null; do_gate scaffold >/dev/null 2>&1; do_advance >/dev/null; do_gate review >/dev/null 2>&1
  ( do_review reject noise design ) >/dev/null 2>&1; chk "$?" 3 "reject past limit is BLOCKED (exit 3)"
  chk "$(jget review.rejections)" "3" "blocked reject does not increment counter"
  chk "$(jget phase|tr -d '"')" review "blocked reject does not loop phase back"
  do_reset >/dev/null; chk "$(jget review.rejections)" "0" "reset clears rejection counter"
  do_review reject noise design >/dev/null 2>&1; chk "$(jget review.rejections)" "1" "reject works again after reset"
  # FORCE_RESET on an escalated pipeline clears the counter then rejects (counts as #1)
  do_gate design >/dev/null 2>&1; do_advance >/dev/null; do_gate scaffold >/dev/null 2>&1; do_advance >/dev/null; do_gate review >/dev/null 2>&1
  do_review reject noise design >/dev/null 2>&1
  do_gate design >/dev/null 2>&1; do_advance >/dev/null; do_gate scaffold >/dev/null 2>&1; do_advance >/dev/null; do_gate review >/dev/null 2>&1
  do_review reject noise design >/dev/null 2>&1
  do_gate design >/dev/null 2>&1; do_advance >/dev/null; do_gate scaffold >/dev/null 2>&1; do_advance >/dev/null; do_gate review >/dev/null 2>&1
  KIT_PIPELINE_FORCE_RESET=1 do_review reject noise design >/dev/null 2>&1
  chk "$(jget review.rejections)" "1" "KIT_PIPELINE_FORCE_RESET clears counter then rejects (#1)"
  # loop: evaluator-optimizer driver (hermetic stubs) — converge / oscillation / no-fixer.
  # Converge: a failing review gate whose fix-cmd copies a passing stub over it →
  # round 2 goes green → --auto-approve marks done. (do_done exits the process, so
  # do_loop uses done_ok — non-exiting — to confirm + returns 0.)
  local L FC F2 lout
  L="$(mktemp -d)"; STATE="$L/phase.json"
  FC="$L/g.sh"; printf '#!/usr/bin/env bash\necho "FAIL: check-A"; exit 1\n' > "$FC"; chmod +x "$FC"
  DESIGN_GATE="$TMP/stub.sh" SCAFFOLD_GATE_A="$TMP/stub.sh" SCAFFOLD_GATE_B="$TMP/stub.sh" REVIEW_GATE_A="$FC" REVIEW_GATE_B="$TMP/stub.sh"
  init_state >/dev/null; w_review
  lout=$(do_loop --max 3 --auto-approve --fix-cmd "printf '%s' \"\$PIPELINE_LOOP_SIGNATURE\" > $L/sig.txt; cp $TMP/stub.sh $FC" 2>&1); chk "$?" 0 "loop converges+auto-approves when fix-cmd flips gate green"
  chk "$(jget review.approved)" "true" "loop auto-approve marked approved"
  grep -q "check-A" "$L/sig.txt"; chk "$?" 0 "fix-cmd receives the structured failing signature (PIPELINE_LOOP_SIGNATURE)"
  printf '%s' "$lout" | grep -q "second-opinion"; chk "$?" 0 "auto-approve after fix rounds advises a second opinion"
  # Oscillation / no-op: fix-cmd `true` changes nothing → identical failure sig on
  # round 2 → escalate exit 4 (not a silent loop, not exit-3 FSM hard-block).
  L="$(mktemp -d)"; STATE="$L/phase.json"; F2="$L/g.sh"
  printf '#!/usr/bin/env bash\necho "FAIL: stuck"; exit 1\n' > "$F2"; chmod +x "$F2"
  DESIGN_GATE="$TMP/stub.sh" SCAFFOLD_GATE_A="$TMP/stub.sh" SCAFFOLD_GATE_B="$TMP/stub.sh" REVIEW_GATE_A="$F2" REVIEW_GATE_B="$TMP/stub.sh"
  init_state >/dev/null; w_review
  do_loop --max 3 --fix-cmd "true" >/dev/null 2>&1; chk "$?" 4 "loop escalates (exit 4) on oscillation/no-op fix"
  chk "$(jget review.approved)" "false" "oscillation did not approve"
  # No fixer wired → graceful exit 4 with the critique (never a silent stop).
  do_loop --max 2 >/dev/null 2>&1; chk "$?" 4 "loop with no --fix-cmd escalates gracefully (exit 4)"
  rm -rf "$L"
  # The four subprocess cases below all turn on the phantom-state guard, whose
  # entire trigger condition is "KIT_APP, KIT_PIPELINE_STATE_DIR and KIT_MONOREPO
  # are all unset" (see the guard at the top of this file). A subprocess inherits
  # the caller's environment, so if the operator exported any of the three the
  # cases stop testing pipeline.sh and start testing the shell they were launched
  # from. Two distinct failure modes, one of them silent:
  #   - loud:   the guard declines to fire, `init` succeeds, and the case that
  #             demands exit 2 goes red — a green pipeline.sh reported as broken.
  #   - SILENT: the KIT_PIPELINE_STATE_DIR override case "passes" without ever
  #             exercising the override, because the guard it is supposed to be
  #             escaping was never armed. A vacuous pass is worse than a failure.
  # Scrub all three per invocation, then set only what the case under test needs,
  # so the result is a property of this script and not of its caller.
  # consumer mode (subprocess): KIT_APP retargets state under the app + drops gate.sh
  local C; C="$(mktemp -d)"
  env -u KIT_PIPELINE_STATE_DIR -u KIT_MONOREPO KIT_APP="$C" bash "$SELF" init >/dev/null 2>&1
  chk "$([ -f "$C/pipeline/state/phase.json" ] && echo 1 || echo 0)" 1 "consumer mode writes state under KIT_APP"
  rm -rf "$C"
  # phantom-state guard (subprocess): from a cwd OUTSIDE the kit tree with no
  # KIT_APP, init must be refused (exit 2) and leave no split state in the kit;
  # an explicit KIT_PIPELINE_STATE_DIR override is the sanctioned way through.
  local O; O="$(mktemp -d)"
  ( cd "$O" && env -u KIT_APP -u KIT_PIPELINE_STATE_DIR -u KIT_MONOREPO bash "$SELF" init ) >/dev/null 2>&1; chk "$?" 2 "phantom-state guard refuses init outside the kit without KIT_APP"
  chk "$([ -f "$ROOT/pipeline/state/phase.json" ] && echo 1 || echo 0)" 0 "guard left no phantom state in the kit monorepo"
  ( cd "$O" && env -u KIT_APP -u KIT_MONOREPO KIT_PIPELINE_STATE_DIR="$O/s" bash "$SELF" init ) >/dev/null 2>&1; chk "$?" 0 "explicit KIT_PIPELINE_STATE_DIR override passes the guard"
  chk "$([ -f "$O/s/phase.json" ] && echo 1 || echo 0)" 1 "the override actually placed state at KIT_PIPELINE_STATE_DIR (not a vacuous pass)"
  rm -rf "$O"
  # non-UI slice exemption (teeth): a FAILING design gate is bypassed by
  # DESIGN_TARGET=none, but records `failed` without it — the control proves the
  # stub genuinely fails, so `passed` is attributable to the exemption, not a no-op stub.
  local NU; NU="$(mktemp -d)"; STATE="$NU/phase.json"
  printf '#!/usr/bin/env bash\necho stub-FAIL; exit 1\n' > "$NU/fail.sh"; chmod +x "$NU/fail.sh"
  DESIGN_GATE="$NU/fail.sh"
  init_state >/dev/null; DESIGN_TARGET=none do_gate design >/dev/null 2>&1
  chk "$(jget design.status|tr -d '"')" passed "DESIGN_TARGET=none passes design despite FAILING gate"
  init_state >/dev/null; do_gate design >/dev/null 2>&1
  chk "$(jget design.status|tr -d '"')" failed "failing design gate records failed (control, no none)"
  DESIGN_GATE="$TMP/stub.sh"   # restore — the failing stub dies with $NU
  rm -rf "$NU"
  # ---- prototype phase: verdict seam (D5), rework loop, non-UI bypass (Q6), native crossing (ADR-0015) ----
  local NP; NP="$(mktemp -d)"; STATE="$NP/phase.json"
  printf '#!/usr/bin/env bash\necho stub-FAIL; exit 1\n' > "$NP/fail.sh"; chmod +x "$NP/fail.sh"
  PROTO_GATE="$NP/fail.sh"
  init_state >/dev/null; PROTOTYPE_TARGET=none do_gate prototype >/dev/null 2>&1
  chk "$(jget prototype.status|tr -d '"')" passed "PROTOTYPE_TARGET=none passes prototype despite FAILING gate (Q6 bypass)"
  init_state >/dev/null; do_gate prototype >/dev/null 2>&1
  chk "$(jget prototype.status|tr -d '"')" failed "failing prototype gate records failed (control, no none)"
  # native crossing (ADR-0015): passes despite the FAILING freeze stub, records
  # the audit reason in state, and Human Gate 1 still keys advance.
  init_state >/dev/null; PROTOTYPE_TARGET=native do_gate prototype >/dev/null 2>&1
  chk "$(jget prototype.status|tr -d '"')" passed "PROTOTYPE_TARGET=native passes prototype despite FAILING gate (native crossing, ADR-0015)"
  chk "$(jget prototype.reason|tr -d '"')" "native: kit-designer-authored design (ADR-0015)" "native crossing records the audit reason in state"
  ( do_advance ) >/dev/null 2>&1;   chk "$?" 1 "native: advance refused before Human Gate 1 approval"
  ( do_gate prototype --approve "brief ok" ) >/dev/null 2>&1; chk "$?" 0 "native: --approve accepted once the crossing recorded passed"
  do_advance >/dev/null;             chk "$(jget phase|tr -d '"')" design "native: two-key advance prototype->design"
  PROTO_GATE="$TMP/stub.sh"
  init_state >/dev/null; ( do_gate prototype --approve early ) >/dev/null 2>&1; chk "$?" 1 "--approve refused before freeze gate passes"
  w_review
  ( do_gate prototype --rework "typo in tokens" ) >/dev/null 2>&1; chk "$?" 1 "--rework records and returns non-zero (not advancing)"
  chk "$(jget phase|tr -d '"')" prototype "rework pulls phase back to prototype"
  chk "$(jget prototype.status|tr -d '"')" ready "rework re-opens prototype"
  chk "$(jget prototype.humanApproved)" "false" "rework clears human approval"
  chk "$(jget prototype.rework)" "1" "rework counter increments"
  chk "$(jget design.status|tr -d '"')" blocked "rework re-blocks design"
  chk "$(jget scaffold.status|tr -d '"')" blocked "rework re-blocks scaffold"
  rm -rf "$NP"
  # prototype gate no-ops at the monorepo root (pass sentinel — app-only gate)
  local M; M="$(mktemp -d)"
  ( cd "$ROOT" && KIT_MONOREPO=1 KIT_PIPELINE_STATE_DIR="$M" bash "$SELF" init >/dev/null 2>&1 && KIT_MONOREPO=1 KIT_PIPELINE_STATE_DIR="$M" bash "$SELF" gate prototype >/dev/null 2>&1 )
  chk "$?" 0 "prototype gate no-ops (pass) at the monorepo root"
  grep -q '"status": "passed"' "$M/phase.json"; chk "$?" 0 "monorepo prototype pass recorded"
  rm -rf "$M"
  # ---- run records + the Golden Gate (reproducibility) + golden --accept ----
  # A dedicated tmp state; the real tools/region_diff.sh runs (via REPRO_GATE
  # default) against tmp fixture/golden trees. runs.jsonl lands next to STATE
  # (record_run derives the dir), so the repo's own pipeline/state is untouched.
  local G; G="$(mktemp -d)"; STATE="$G/phase.json"
  DESIGN_GATE="$TMP/stub.sh" SCAFFOLD_GATE_A="$TMP/stub.sh" SCAFFOLD_GATE_B="$TMP/stub.sh" REVIEW_GATE_A="$TMP/stub.sh" REVIEW_GATE_B="$TMP/stub.sh"
  init_state >/dev/null
  KIT_FIXTURE_DIR="$G/fixture" KIT_GOLDEN_DIR="$G/golden"; export KIT_FIXTURE_DIR KIT_GOLDEN_DIR
  mkdir -p "$G/fixture"
  # missing actual/ → exit 2 with guidance, phase status untouched
  ( do_gate reproducibility ) >/dev/null 2>&1; chk "$?" 2 "reproducibility gate exits 2 when fixture actual/ is missing"
  chk "$(jget phase | tr -d '"')" prototype "reproducibility error does not disturb the FSM phase"
  mkdir -p "$G/fixture/actual" "$G/golden"
  printf '// <frozen name="chrome">\nKitNativeTabBar();\n// </frozen>\n\ngenerative body v1 { }\n' > "$G/golden/a.dart"
  cp "$G/golden/a.dart" "$G/fixture/actual/a.dart"
  do_gate reproducibility >/dev/null 2>&1; chk "$?" 0 "reproducibility gate passes on identical trees"
  chk "$(jget reproducibility.status|tr -d '"')" passed "reproducibility result recorded in phase.json"
  [ -f "$G/runs.jsonl" ] && grep -q '"action": "gate"' "$G/runs.jsonl" && grep -q '"phase": "reproducibility"' "$G/runs.jsonl"
  chk "$?" 0 "runs.jsonl carries the gate run record"
  grep -q '"run_id"' "$G/runs.jsonl" && grep -q '"duration_ms"' "$G/runs.jsonl"
  chk "$?" 0 "run records carry run_id + duration_ms"
  # frozen drift → exit 1, recorded failed, failing_signature on the run record
  printf '// <frozen name="chrome">\nNavigationBar();\n// </frozen>\n\ngenerative body v1 { }\n' > "$G/fixture/actual/a.dart"
  do_gate reproducibility >/dev/null 2>&1; chk "$?" 1 "reproducibility gate fails on frozen drift"
  chk "$(jget reproducibility.status|tr -d '"')" failed "frozen drift recorded as failed"
  grep -q '"failing_signature"' "$G/runs.jsonl"
  chk "$?" 0 "failing run record carries failing_signature"
  # golden --accept: deliberate adoption — replaces the golden tree, audit-trails.
  # (do_golden runs in a (subshell) for the usage-error case so its `exit 2`
  # ends only the subshell — same pattern as the BLOCKED-reject check above.)
  ( do_golden ) >/dev/null 2>&1; chk "$?" 2 "golden without --accept is a usage error"
  ( KIT_GOLDEN_DIR="$G"; do_golden --accept ) >/dev/null 2>&1; chk "$?" 2 "golden --accept refuses a golden dir that CONTAINS the fixture"
  do_golden --accept >/dev/null 2>&1; chk "$?" 0 "golden --accept runs"
  do_gate reproducibility >/dev/null 2>&1; chk "$?" 0 "gate green after golden --accept (drift adopted deliberately)"
  [ -f "$G/golden_audit.jsonl" ] && grep -q '"who": "reviewer"' "$G/golden_audit.jsonl"
  chk "$?" 0 "golden audit record appended (who: reviewer)"
  grep -q '"action": "golden"' "$G/runs.jsonl"
  chk "$?" 0 "golden accept also lands in runs.jsonl"
  # advance/touch run records (current phase is prototype — two-key walk)
  do_gate prototype >/dev/null 2>&1; do_gate prototype --approve w >/dev/null 2>&1; do_advance >/dev/null 2>&1; do_touch "selftest touch" >/dev/null 2>&1
  grep -q '"action": "advance"' "$G/runs.jsonl"; chk "$?" 0 "runs.jsonl carries the advance record"
  grep -q '"action": "touch"' "$G/runs.jsonl";   chk "$?" 0 "runs.jsonl carries the touch record"
  unset KIT_FIXTURE_DIR KIT_GOLDEN_DIR
  rm -rf "$G"
  # ---- Commit Checkpoints (advisory + ledger; SUBPROCESS-ONLY — never call    #
  # do_checkpoint in-process here, so no assertion can ever commit in the repo) ----
  local K; K="$(mktemp -d)"
  git -C "$K" init -q -b main >/dev/null 2>&1; git -C "$K" config user.email t@t.t; git -C "$K" config user.name t
  echo base > "$K/a.txt"; git -C "$K" add -A; git -C "$K" commit -qm base
  local KG="KIT_APP=$K KIT_PIPELINE_STATE_DIR=$K/pipeline/state PIPELINE_PROTOTYPE_GATE=$TMP/stub.sh PIPELINE_DESIGN_GATE=$TMP/stub.sh PIPELINE_SCAFFOLD_GATE_A=$TMP/stub.sh PIPELINE_SCAFFOLD_GATE_B=$TMP/stub.sh PIPELINE_BRANDING_GATE=$TMP/stub.sh PIPELINE_REVIEW_GATE_A=$TMP/stub.sh PIPELINE_REVIEW_GATE_B=$TMP/stub.sh"
  env $KG bash "$SELF" init >/dev/null 2>&1
  env $KG bash "$SELF" gate prototype >/dev/null 2>&1
  env $KG bash "$SELF" gate prototype --approve w >/dev/null 2>&1
  env $KG bash "$SELF" advance >/dev/null 2>&1
  env $KG bash "$SELF" gate design >/dev/null 2>&1
  env $KG bash "$SELF" checkpoint >/dev/null 2>&1; chk "$?" 0 "checkpoint on clean tree exits 0 (nothing to checkpoint)"
  echo dirty > "$K/b.txt"
  env $KG bash "$SELF" checkpoint wave-boundary >/dev/null 2>&1; chk "$?" 0 "checkpoint commits dirty tree"
  git -C "$K" log --oneline -1 | grep -q "checkpoint \[design\] — wave-boundary"; chk "$?" 0 "commit message carries phase + note"
  grep -q '"gate_green": true' "$K/pipeline/state/checkpoints.jsonl"; chk "$?" 0 "ledger records gate_green=true (design gate passed)"
  grep -q "$(git -C "$K" rev-parse --short HEAD)" "$K/pipeline/state/checkpoints.jsonl"; chk "$?" 0 "ledger sha matches HEAD"
  env $KG bash "$SELF" checkpoint >/dev/null 2>&1; chk "$?" 0 "checkpoint is idempotent on clean tree"
  # mid-phase checkpoint (no gate green): commits, warns, records gate_green=false
  local K2; K2="$(mktemp -d)"
  git -C "$K2" init -q -b main >/dev/null 2>&1; git -C "$K2" config user.email t@t.t; git -C "$K2" config user.name t
  echo base > "$K2/a.txt"; git -C "$K2" add -A; git -C "$K2" commit -qm base
  local KH="KIT_APP=$K2 KIT_PIPELINE_STATE_DIR=$K2/pipeline/state"
  env $KH bash "$SELF" init >/dev/null 2>&1
  echo wip > "$K2/b.txt"
  local out
  out=$(env $KH bash "$SELF" checkpoint wip-note 2>&1); chk "$?" 0 "mid-phase checkpoint commits (no gate green)"
  printf '%s' "$out" | grep -q "gate_green=false"; chk "$?" 0 "mid-phase checkpoint warns gate_green=false"
  grep -q '"gate_green": false' "$K2/pipeline/state/checkpoints.jsonl"; chk "$?" 0 "ledger records gate_green=false"
  # outside a git work tree → exit 1
  local K3; K3="$(mktemp -d)"
  env KIT_APP="$K3" KIT_PIPELINE_STATE_DIR="$K3/pipeline/state" bash "$SELF" init >/dev/null 2>&1
  ( env KIT_APP="$K3" KIT_PIPELINE_STATE_DIR="$K3/pipeline/state" bash "$SELF" checkpoint ) >/dev/null 2>&1; chk "$?" 1 "checkpoint outside git exits 1"
  # REGRESSION — advance must exit 0 on SUCCESS with a CLEAN tree.
  # do_advance ended with a bare `[ -n "$(git status --porcelain)" ] && echo …`,
  # which made that test the function's exit status: clean tree → test false →
  # && short-circuits → advance returned 1 *on success*. do_loop branches on that
  # rc and falsely escalated "gate green but advance refused", so the unattended
  # loop only worked while work was uncommitted. The dirty-tree case below is
  # structurally blind to it (the echo runs, so the status is 0) — this is its
  # mirror, in its own tree so it can't perturb the phase sequence below.
  # pipeline/state/ is gitignored here exactly as a real consumer app does it (sample-app ignores
  # pipeline/state). Without that, every gate/advance write dirties the tree — and a
  # `checkpoint` does NOT fix it, because checkpoint commits and THEN appends to
  # pipeline/state/checkpoints.jsonl, re-dirtying the tree. A dirty tree sends advance
  # down the echo path, where it returns 0 even when broken, so the assertion
  # below would pass vacuously and test nothing. (Observed: the first draft of
  # this case did exactly that.)
  local K4; K4="$(mktemp -d)"
  git -C "$K4" init -q -b main >/dev/null 2>&1; git -C "$K4" config user.email t@t.t; git -C "$K4" config user.name t
  printf 'pipeline/state/\n' > "$K4/.gitignore"
  echo base > "$K4/a.txt"; git -C "$K4" add -A; git -C "$K4" commit -qm base
  local KC="KIT_APP=$K4 KIT_PIPELINE_STATE_DIR=$K4/pipeline/state PIPELINE_PROTOTYPE_GATE=$TMP/stub.sh PIPELINE_DESIGN_GATE=$TMP/stub.sh"
  env $KC bash "$SELF" init >/dev/null 2>&1
  env $KC bash "$SELF" gate prototype >/dev/null 2>&1
  env $KC bash "$SELF" gate prototype --approve w >/dev/null 2>&1
  git -C "$K4" status --porcelain | grep -q .; chk "$?" 1 "precondition: tree is clean before the clean-tree advance"
  out=$(env $KC bash "$SELF" advance 2>&1); chk "$?" 0 "advance exits 0 on a CLEAN tree (regression: returned 1 on success)"
  printf '%s' "$out" | grep -q "checkpoint suggested"; chk "$?" 1 "no checkpoint suggestion on a clean tree"
  # advance proposes a checkpoint on a dirty tree; done warns the same way
  echo more > "$K/c.txt"
  out=$(env $KG bash "$SELF" advance 2>&1); chk "$?" 0 "advance still succeeds"
  printf '%s' "$out" | grep -q "checkpoint suggested"; chk "$?" 0 "advance proposes a checkpoint on dirty tree"
  env $KG bash "$SELF" gate scaffold >/dev/null 2>&1
  env $KG bash "$SELF" advance >/dev/null 2>&1
  env $KG bash "$SELF" gate review >/dev/null 2>&1
  env $KG bash "$SELF" review approve >/dev/null 2>&1
  echo tail > "$K/d.txt"
  out=$(env $KG bash "$SELF" done 2>&1); chk "$?" 0 "done succeeds when approved"
  printf '%s' "$out" | grep -q "WARN: done-eligible with uncommitted work"; chk "$?" 0 "done warns on uncommitted work"
  out=$(env $KG bash "$SELF" status 2>&1)
  printf '%s' "$out" | grep -q "ckpt"; chk "$?" 0 "status shows the last checkpoint"
  rm -rf "$K" "$K2" "$K3"
  # ---- freeze tool (the real prototype gate script) — hermetic via FREEZE_RENDER=skip ----
  local FD; FD="$(mktemp -d)"
  mkdesign(){ # <appdir> — stamp a minimal valid design/ SSOT (kit vocab complete)
    local D="$1/design"
    mkdir -p "$D/surfaces"
    cat > "$D/tokens.json" <<'EOF'
{"color":{"brand":{"0":{"$type":"color","$value":"#D2522B"}},"bg":{"surface":{"$type":"color","$value":"#F5F0E8"},"surface-2":{"$type":"color","$value":"#EAE3D6"},"paper":{"$type":"color","$value":"#FBF8F2"}},"fg":{"ink":{"$type":"color","$value":"#1A1714"},"muted":{"$type":"color","$value":"#6E6760"},"faint":{"$type":"color","$value":"#A39A8E"}},"border":{"rule":{"$type":"color","$value":"#D8CFBE"}},"status":{"good":{"$type":"color","$value":"#4A7C3A"},"warn":{"$type":"color","$value":"#C68D2E"},"danger":{"$type":"color","$value":"#FF3B30"}}},"typography":{"sans":{"$type":"fontFamily","$value":"Lexend"},"mono":{"$type":"fontFamily","$value":"JetBrains Mono"}}}
EOF
    echo "# DS" > "$D/design-system.md"
    echo '{"globs":[],"selectors":[]}' > "$D/exclusions.json"
    echo "# approved" > "$D/direction-approved.md"
    echo "# brand" > "$D/brand-spec.md"
    # A shell-shaped surface name, not index.html: freeze check 4 treats
    # `index` as the playground harness page and never as a screen, so a
    # fixture named that way would have zero screens and fail the floor.
    echo '<!doctype html><title>x</title><p>hi</p>' > "$D/surfaces/train_shell_home_view.html"
    cat > "$D/structure.json" <<'EOF'
{"$schema":"kit/design-structure@1","registry":null,"tabRoots":{"train":"train.home"},
 "screens":[{"id":"train.home","tab":"train","comp":"TrainHome",
             "shell":"train_shell","surface":"train_shell_home_view"}]}
EOF
  }
  mkdir -p "$FD/noapp"
  FREEZE_RENDER=skip bash "$ROOT/tools/freeze_design.sh" "$FD/noapp" >/dev/null 2>&1; chk "$?" 1 "freeze fails when design/ is missing (D2 anchor)"
  mkdesign "$FD/app"
  FREEZE_RENDER=skip bash "$ROOT/tools/freeze_design.sh" "$FD/app" >/dev/null 2>&1; chk "$?" 0 "freeze passes a minimal valid design dir"
  python3 -c "import json;d=json.load(open('$FD/app/design/tokens.json'));del d['color']['brand'];json.dump(d,open('$FD/app/design/tokens.json','w'))"
  FREEZE_RENDER=skip bash "$ROOT/tools/freeze_design.sh" "$FD/app" >/dev/null 2>&1; chk "$?" 1 "freeze fails on missing kit token vocab"
  mkdesign "$FD/app"
  echo '<div class="tweaks-panel">x</div>' >> "$FD/app/design/surfaces/train_shell_home_view.html"
  FREEZE_RENDER=skip bash "$ROOT/tools/freeze_design.sh" "$FD/app" >/dev/null 2>&1; chk "$?" 1 "freeze fails on uncovered app-box-design chrome (tweaks-panel)"
  echo '{"globs":[],"selectors":[".tweaks-panel"]}' > "$FD/app/design/exclusions.json"
  FREEZE_RENDER=skip bash "$ROOT/tools/freeze_design.sh" "$FD/app" >/dev/null 2>&1; chk "$?" 0 "freeze passes when chrome is excluded (D6)"
  rm -rf "$FD"
  # ---- loop from prototype: blocked advance escalates, never a silent stop (BUG-1 pin) ----
  # Gate is green (stub) but Human Gate 1 is unapproved: do_advance refuses; the loop
  # must survive the refusal, emit the escalation payload, and exit 4 — not die exit 1.
  local LP; LP="$(mktemp -d)"
  printf '#!/usr/bin/env bash\necho stub-ok; exit 0\n' > "$LP/stub.sh"; chmod +x "$LP/stub.sh"
  local LG="KIT_MONOREPO=1 KIT_PIPELINE_STATE_DIR=$LP PROTO_GATE=$LP/stub.sh DESIGN_GATE=$LP/stub.sh SCAFFOLD_GATE_A=$LP/stub.sh SCAFFOLD_GATE_B=$LP/stub.sh SCAFFOLD_GATE_C=$LP/stub.sh SCAFFOLD_GATE_D=$LP/stub.sh REVIEW_GATE_A=$LP/stub.sh REVIEW_GATE_B=$LP/stub.sh"
  env $LG bash "$SELF" init >/dev/null 2>&1
  out=$(env $LG bash "$SELF" loop --max 3 2>&1); chk "$?" 4 "loop w/ unapproved Human Gate 1 exits 4 (not silent 1)"
  printf '%s' "$out" | grep -q "LAST CRITIQUE"; chk "$?" 0 "blocked-advance escalation carries LAST CRITIQUE payload"
  printf '%s' "$out" | grep -q "Human Gate 1"; chk "$?" 0 "escalation payload surfaces the Human-Gate-1 refusal"
  grep -q "loop ESCALATE (advance blocked)" "$LP/phase.json"; chk "$?" 0 "history records the blocked-advance escalation"
  rm -rf "$LP"
  echo "selftest: passed=$P failed=$F"; [ "$F" -eq 0 ] && echo "ALL GREEN" || exit 1
}

case "${1:-status}" in
  init) init_state;;
  status) do_status;;
  gate) shift; [ $# -eq 0 ] && { echo "phase required (prototype|design|scaffold|review|reproducibility)" >&2; exit 2; }; do_gate "$@";;
  golden) shift; do_golden "${1:-}";;
  advance) do_advance;;
  review) shift; do_review "${1:?approve|reject}" "${2:-}" "${3:-}";;
  touch) shift; do_touch "${1:-}";;
  checkpoint) shift; do_checkpoint "${1:-}";;
  done) do_done;;
  reset) do_reset;;
  loop) shift; do_loop "$@";;
  selftest) selftest;;
  *) echo "usage: pipeline.sh {init|status|gate <p> [--approve [n]|--rework <n>]|golden --accept|advance|checkpoint [note]|review <v>|touch|done|reset|loop|selftest}" >&2; exit 2;;
esac
