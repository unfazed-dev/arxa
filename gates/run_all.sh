#!/usr/bin/env bash
# gates/run_all.sh — the orchestrator (plan 04.6). Runs every gate in dependency
# order, aggregates each gate's SARIF findings into one document, and exits
# non-zero if any gate failed. It ORCHESTRATES: it contains no assertions of its
# own — every pass/fail verdict belongs to a gate.
#
# Dependency order: intake -> freeze -> structure -> scaffold -> coverage -> memory
#                   -> review -> native_deps -> deploy.
#   intake    every registry surface traces to a brief/answers (traceability)
#   freeze    the frozen inputs exist and surfaces render clean
#   structure the shell/surface map resolves and is in sync
#   scaffold  shell/widget/overlay boundaries hold
#   coverage  every frozen surface is scaffolded
#   memory    the curated memory layer (repo root, not the app root) is clean
#   review    the design judge over the scaffolded views
#   deploy    target + version + account confirmed
#
# Exit-code convention (the gates'): 0 pass, 1 FAIL, 2 env / not-applicable. A 2
# is reported as N/A, not a failure.
#
# SARIF: each bash gate self-populates $SARIF_RESULTS_FILE (it sources sarif.sh);
# run_all gives every gate its own temp, then concatenates the lines and flushes
# one combined document via sarif.sh. The review gate emits JSON, which run_all
# routes through sarif.sh so there is exactly one transport.
#
# Usage: run_all.sh [app-root]
#   APPBOX_STATE        pipeline state file for the deploy gate
#   GATES_SARIF_OUT     where to write the combined SARIF doc (default: <app>/.kit/state/gates.sarif)
#   KIT_DESIGN_DIR      producer design folder, RELATIVE TO THE APP ROOT (the
#                       gates that consume it reject an absolute path). If unset,
#                       run_all derives it: $APP/design if present, else the
#                       single design under $REPO_ROOT/designs/ (refused when
#                       there are several — pick one explicitly).
set -uo pipefail
GATES_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE_COMMON="$GATES_DIR/_common"
# shellcheck source=../_common/sarif.sh
source "$GATE_COMMON/sarif.sh"

APP="${1:-$PWD}"
APP="$(cd "$APP" 2>/dev/null && pwd)" || { echo "run_all: app root not found: ${1:-$PWD}" >&2; exit 2; }
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SARIF_OUT="${GATES_SARIF_OUT:-$APP/.kit/state/gates.sarif}"

# --- design dir resolution ----------------------------------------------------
# The gates take KIT_DESIGN_DIR *relative to the app root* (four of them reject
# an absolute path outright). The old default was a bare `design`, which is only
# correct when the design sits inside the app. In this repo the app is <root>/app
# and the design is <root>/designs/<name>, so the default resolved to
# app/design — a directory that does not exist — and intake, freeze, structure
# and coverage all failed on "input missing". Six red gates from one wrong
# default is exactly the kind of noise a suite stops being trusted for.
#
# So: derive it, PRINT what was derived, and refuse to guess when the answer is
# ambiguous. An explicit KIT_DESIGN_DIR always wins.
if [ -z "${KIT_DESIGN_DIR:-}" ]; then
  if [ -d "$APP/design" ]; then
    KIT_DESIGN_DIR="design"                       # design lives inside the app
  elif [ -d "$REPO_ROOT/designs" ]; then
    _designs=()
    for _d in "$REPO_ROOT"/designs/*/; do [ -d "$_d" ] && _designs+=("$(basename "$_d")"); done
    case "${#_designs[@]}" in
      1) KIT_DESIGN_DIR="$(python3 -c 'import os,sys;print(os.path.relpath(sys.argv[1],sys.argv[2]))' \
              "$REPO_ROOT/designs/${_designs[0]}" "$APP")" ;;
      0) echo "run_all: $REPO_ROOT/designs exists but is empty — set KIT_DESIGN_DIR to the producer folder" >&2; exit 2 ;;
      *) echo "run_all: $REPO_ROOT/designs holds ${#_designs[@]} designs (${_designs[*]}) — set KIT_DESIGN_DIR to pick one" >&2; exit 2 ;;
    esac
  else
    echo "run_all: no design found (looked for $APP/design and $REPO_ROOT/designs/*) — set KIT_DESIGN_DIR" >&2
    exit 2
  fi
  printf 'run_all: derived KIT_DESIGN_DIR=%s (relative to %s)\n' "$KIT_DESIGN_DIR" "$APP"
fi
export KIT_DESIGN_DIR

AGG="$(mktemp)"; trap 'rm -f "$AGG"' EXIT
fails=0; n_a=0; passed=0; declare -a RESULTS

record(){ RESULTS+=("$1"); }
appended=0
# append_sarif <tmpfile>: a gate's per-run sarif lines -> the aggregate
append_sarif(){ local t="$1"; [ -s "$t" ] && { cat "$t" >> "$AGG"; appended=1; }; rm -f "$t"; }

# run a bash gate: $1=name, $2=script, rest=args. Captures output, routes SARIF.
run_bash_gate(){
  local name="$1" script="$2"; shift 2
  local gtmp out rc; gtmp="$(mktemp)"; out="$(mktemp)"
  SARIF_RESULTS_FILE="$gtmp" bash "$script" "$@" >"$out" 2>&1
  rc=$?
  append_sarif "$gtmp"
  printf '%s\n' "--- $name -----------------------------------------------------------"
  cat "$out"
  case "$rc" in 0) passed=$((passed+1)); record "  PASS  $name";; 2) n_a=$((n_a+1)); record "  N/A   $name";; *) fails=$((fails+1)); record "  FAIL  $name";; esac
  rm -f "$out"
  return "$rc"
}

# run the review (dart) gate per view file. review judges one surface at a time,
# so run_all enumerates every *_view.dart dispatcher under the views tree and
# fails overall if any file fails. Findings route through sarif.sh (one transport).
run_review_gate(){
  local name="review" views="$APP/lib/ui/views" gtmp overall=0 f json rc
  printf '%s\n' "--- review -----------------------------------------------------------"
  if [ ! -d "$views" ]; then
    printf '  (review N/A — no %s)\n' "$views"
    n_a=$((n_a+1)); record "  N/A   review"; return 2
  fi
  local files; files="$(find "$views" -type f -name '*_view.dart' 2>/dev/null | grep -vE '_view\.(mobile|tablet|desktop)\.dart$' || true)"
  if [ -z "$files" ]; then
    printf '  (review N/A — no *_view.dart under %s)\n' "$views"
    n_a=$((n_a+1)); record "  N/A   review"; return 2
  fi
  gtmp="$(mktemp)"
  source "$GATE_COMMON/sarif.sh"        # (re)define sarif_result; truncates a throwaway temp
  SARIF_RESULTS_FILE="$gtmp"             # repoint at the gate temp — plain assignment so the
                                          # piped-while subshell inherits it (prefix-source does not)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    json="$(dart "$GATES_DIR/review/review.dart" "$f" --json 2>/dev/null || true)"
    if printf '%s' "$json" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") else 1)' 2>/dev/null; then
      rc=0; printf '  PASS  %s\n' "$f"
    else
      rc=1; overall=1; printf '  FAIL  %s\n' "$f"
      printf '%s' "$json" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for c in d.get("checks",[]):
    if not c.get("ok"):
        print(c.get("name","?")+"\t"+c.get("message",""))
' | while IFS=$'\t' read -r nm ms; do [ -n "$nm" ] && sarif_result "review" "error" "$f" "[$nm] $ms"; done
    fi
  done < <(printf '%s\n' "$files")
  append_sarif "$gtmp"
  if [ "$overall" = 0 ]; then passed=$((passed+1)); record "  PASS  review"; else fails=$((fails+1)); record "  FAIL  review"; fi
  return "$overall"
}

printf 'run_all: gates over %s\n' "$APP"

# intake first: traceability is a PRE-condition — every registry surface must
# trace to a brief/answers before anything is frozen. (10.6)
run_bash_gate   intake    "$GATES_DIR/intake/intake.sh"    "$APP"
run_bash_gate   freeze    "$GATES_DIR/freeze/freeze.sh"    "$APP"
run_bash_gate   structure "$GATES_DIR/structure/structure.sh" "$APP"
run_bash_gate   scaffold  "$GATES_DIR/scaffold/scaffold.sh"  "$APP"
run_bash_gate   coverage  "$GATES_DIR/coverage/coverage.sh"  "$APP"
# memory sits after the artifact gates and before review: it is a REPO-root
# gate (memory/ documents the pipeline itself, not one app), so it takes
# $REPO_ROOT, not $APP like the artifact gates above.
run_bash_gate   memory    "$GATES_DIR/memory/memory.sh"    "$REPO_ROOT"
VIEWS="$APP/lib/ui/views" run_review_gate
# native_deps before deploy: whether the app's plugins can still be built for
# each declared target is a PRE-condition of shipping to those targets.
run_bash_gate   native_deps "$GATES_DIR/native_deps/native_deps.sh" "$APP"
run_bash_gate   deploy    "$GATES_DIR/deploy/deploy.sh"

# ---- aggregate SARIF into one document ----------------------------------------
mkdir -p "$(dirname "$SARIF_OUT")"
# flush reads $SARIF_RESULTS_FILE. Source sarif.sh WITHOUT SARIF_RESULTS_FILE set
# (it makes+truncates its own throwaway temp), then repoint at AGG and flush —
# otherwise sarif.sh's source-time truncate would wipe the aggregate.
bash -c 'source "'"$GATE_COMMON"'/sarif.sh" >/dev/null 2>&1; SARIF_RESULTS_FILE="'"$AGG"'"; sarif_flush' > "$SARIF_OUT" 2>/dev/null || cp "$AGG" "$SARIF_OUT"

printf '\n=== summary ===\n'
printf '%s\n' "${RESULTS[@]}"
printf '  %d passed, %d failed, %d N/A   SARIF -> %s\n' "$passed" "$fails" "$n_a" "$SARIF_OUT"
[ "$fails" -eq 0 ] && { echo "run_all: PASS"; exit 0; }
echo "run_all: FAIL ($fails gate(s))" >&2
exit 1
