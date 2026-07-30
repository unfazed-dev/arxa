#!/usr/bin/env bash
# memory.sh — the MEMORY gate: hygiene assertions over the curated memory
# layer (memory/ at the repo root). Memory rots unless a gate consumes it —
# this is the gate (docs/plans/appbox-memory-and-payment.md, M1).
#
# Unlike the artifact gates, memory/ lives at the REPO root, not the app root:
# the curated layer documents the pipeline itself, not one generated app.
#
# Checks (all must pass):
#   1. index    — memory/MEMORY.md exists and is <= 100 lines (the adherence
#                 ceiling; consolidate, don't grow)
#   2. facts    — every memory/facts/*.json parses as a JSON array of
#                 {fact, source, ts} objects
#   3. lessons  — every memory/stages/*.LESSONS.md is <= 200 lines
#                 (memory_curate.dart enforces the cap on writes; this catches
#                 hand edits)
#   4. abspath  — no line under memory/ contains a forbidden absolute-path
#                 prefix (config/forbidden_abs_prefixes.txt, R3)
#
# Usage: memory.sh [--self-test] [repo-root]     (0 pass / 1 FAIL / 2 env)
set -uo pipefail

GATE_COMMON="$(cd "$(dirname "$0")/../_common" && pwd)"
# shellcheck source=../_common/sarif.sh
source "$GATE_COMMON/sarif.sh"
# gates run WITHOUT set -e (a failed check is a recorded status, not an abort).
set +e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SELF_TEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELF_TEST=1; shift ;;
    --*) echo "FAIL: unknown flag: $1" >&2; exit 2 ;;
    *) REPO_ROOT="$(cd "$1" 2>/dev/null && pwd)" || { echo "FAIL: repo root not found: $1" >&2; exit 2; }; shift ;;
  esac
done

run_gate(){
  local root="$1" mem="$1/memory" F=0
  local fail_ ok_
  fail_(){ echo "FAIL: $1" >&2; F=$((F+1)); sarif_result "memory" "error" "memory" "$1"; }
  ok_(){ echo "  ✓ $1"; }

  # ---- 1. index ----
  if [ ! -f "$mem/MEMORY.md" ]; then
    fail_ "index: memory/MEMORY.md missing — the curated-memory index is the entry point"
  else
    local n; n="$(wc -l < "$mem/MEMORY.md" | tr -d ' ')"
    if [ "$n" -le 100 ]; then ok_ "index: MEMORY.md $n line(s) (cap 100)"
    else fail_ "index: MEMORY.md is $n lines (cap 100) — consolidate, don't grow"; fi
  fi

  # ---- 2. facts parse as [{fact, source, ts}] ----
  local facts_count=0
  if [ -d "$mem/facts" ]; then
    local f
    for f in "$mem"/facts/*.json; do
      [ -e "$f" ] || continue
      facts_count=$((facts_count+1))
      python3 - "$f" <<'PY' || fail_ "facts: $(basename "$f") does not parse as an array of {fact, source, ts}"
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception as e: print(f"  parse error: {e}",file=sys.stderr); sys.exit(1)
ok = isinstance(d,list) and all(
    isinstance(e,dict) and all(isinstance(e.get(k),str) for k in ("fact","source","ts"))
    for e in d)
sys.exit(0 if ok else 1)
PY
    done
  fi
  if [ "$facts_count" -eq 0 ]; then
    fail_ "facts: no memory/facts/*.json — durable facts must be recorded, not held in heads"
  else
    ok_ "facts: $facts_count topic file(s) parse"
  fi

  # ---- 3. lessons caps ----
  local lessons_count=0
  if [ -d "$mem/stages" ]; then
    local l
    for l in "$mem"/stages/*.LESSONS.md; do
      [ -e "$l" ] || continue
      lessons_count=$((lessons_count+1))
      local n; n="$(wc -l < "$l" | tr -d ' ')"
      if [ "$n" -le 200 ]; then ok_ "lessons: $(basename "$l") $n line(s) (cap 200)"
      else fail_ "lessons: $(basename "$l") is $n lines (cap 200) — drop the oldest lessons"; fi
    done
  fi
  [ "$lessons_count" -eq 0 ] && fail_ "lessons: no memory/stages/*.LESSONS.md — one lesson log per pipeline stage"

  # ---- 4. no forbidden absolute-path prefixes under memory/ (R3) ----
  local prefixes="$root/config/forbidden_abs_prefixes.txt"
  if [ -f "$prefixes" ]; then
    local cleaned; cleaned="$(mktemp)"
    grep -v -e '^\s*#' -e '^\s*$' "$prefixes" > "$cleaned"
    local hits; hits="$(grep -rnF -f "$cleaned" "$mem" 2>/dev/null || true)"
    rm -f "$cleaned"
    if [ -n "$hits" ]; then
      while IFS= read -r h; do fail_ "abspath: $h (forbidden prefix, R3)"; done <<< "$hits"
    else
      ok_ "abspath: no forbidden absolute-path prefixes under memory/"
    fi
  else
    ok_ "abspath: no config/forbidden_abs_prefixes.txt — check skipped"
  fi

  [ "$F" -gt 0 ] && { echo "memory: FAIL ($F check(s))" >&2; return 1; }
  echo "memory: PASS — memory/ is gate-clean (index <=100, facts parse, lessons <=200, no absolute paths)."
  return 0
}

# ---- embedded self-test (R5): happy path + one negative per check ----------
self_test(){
  local pass=0 failc=0
  local chk need
  chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
  need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

  local T; T="$(mktemp -d)"; trap 'rm -rf "${T:-}"' EXIT
  mkdir -p "$T/memory/facts" "$T/memory/stages" "$T/config"
  printf '# forbidden\n/Volumes/\n/Users/\n' > "$T/config/forbidden_abs_prefixes.txt"
  mkvalid(){
    printf '# memory index\n' > "$T/memory/MEMORY.md"
    printf '[{"fact":"f","source":"s","ts":"2026-07-30"}]\n' > "$T/memory/facts/a.json"
    printf '# stage — lessons\n\n## Lessons\n- gate x failed because y; do z\n' > "$T/memory/stages/intake.LESSONS.md"
  }

  # HAPPY
  mkvalid
  local o; o="$(run_gate "$T" 2>&1)"; chk "$?" 0 "happy: valid memory/ passes"
  need "$o" "memory: PASS" "happy prints PASS"

  # NEGATIVE: index over 100 lines
  mkvalid; for i in $(seq 1 101); do echo "line $i"; done > "$T/memory/MEMORY.md"
  o="$(run_gate "$T" 2>&1)"; chk "$?" 1 "negative: index over cap fails"
  need "$o" "cap 100" "names the index cap"

  # NEGATIVE: malformed facts json
  mkvalid; printf 'not json\n' > "$T/memory/facts/b.json"
  o="$(run_gate "$T" 2>&1)"; chk "$?" 1 "negative: malformed facts fails"
  need "$o" "b.json does not parse" "names the malformed file"

  # NEGATIVE: right shape, wrong keys
  mkvalid; printf '[{"lesson":"no fact/source/ts keys"}]\n' > "$T/memory/facts/b.json"
  o="$(run_gate "$T" 2>&1)"; chk "$?" 1 "negative: wrong fact shape fails"
  need "$o" "b.json does not parse" "names the shape violation"

  # NEGATIVE: lessons over 200 lines
  mkvalid; { echo '# stage — lessons'; echo; echo '## Lessons'; for i in $(seq 1 199); do echo "- lesson $i"; done; } > "$T/memory/stages/intake.LESSONS.md"
  o="$(run_gate "$T" 2>&1)"; chk "$?" 1 "negative: lessons over cap fails"
  need "$o" "cap 200" "names the lessons cap"

  # NEGATIVE: forbidden absolute path
  mkvalid; printf -- '- see /Volumes/developer_ssd/x for details\n' >> "$T/memory/stages/intake.LESSONS.md"
  o="$(run_gate "$T" 2>&1)"; chk "$?" 1 "negative: absolute path fails"
  need "$o" "forbidden prefix" "names the absolute path"

  echo "memory selftest: $pass passed, $failc failed"
  [ "$failc" -eq 0 ]
}

if [ "$SELF_TEST" = 1 ]; then
  self_test
  exit $?
fi

run_gate "$REPO_ROOT"
exit $?
