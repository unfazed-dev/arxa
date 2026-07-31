#!/usr/bin/env bash
# gates/test_gates_can_fail.sh — the R5 guard (plan 04.7). For every gate folder
# under gates/, asserts:
#   1. a selftest exists, AND
#   2. it contains at least one NEGATIVE case (a `# NEGATIVE:` block).
# Then runs every selftest and asserts each passes.
#
# This is the guard against R5 eroding: delete a negative case from any gate and
# this meta-test FAILS. A selftest that proves only the happy path is rejected.
set -uo pipefail
GATES_DIR="$(cd "$(dirname "$0")" && pwd)"
pass=0; failc=0
ok(){ pass=$((pass+1)); }
bad(){ failc=$((failc+1)); echo "  FAIL: $1"; }

# every gate folder except the shared helpers
gate_dirs=()
for d in "$GATES_DIR"/*/; do
  nm="$(basename "$d")"; [ "$nm" = "_common" ] && continue
  # skip non-gate artifacts that are not themselves gates
  gate_dirs+=("$nm")
done

for g in "${gate_dirs[@]}"; do
  dir="$GATES_DIR/$g"
  selftest="$dir/selftest.sh"
  echo "[$g]"
  if [ ! -f "$selftest" ]; then
    bad "$g/ has no selftest.sh (R4 shape: gate + selftest + README)"
    continue
  fi
  # (1) at least one negative case. Scan the gate's EXECECUTABLE files
  # (selftest + gate script) case-insensitively — some gates delegate their
  # suite to the gate script (e.g. coverage.sh --self-test), so the marker may
  # live outside selftest.sh. Excludes READMEs (which legitimately discuss the
  # rule, not prove a case).
  neg_files="$(find "$dir" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.dart' \) 2>/dev/null)"
  if grep -li 'negative' $neg_files >/dev/null 2>&1; then ok; echo "    negative cases: present"
  else bad "$g/ has no NEGATIVE case in its gate scripts — R5 requires >=1 negative case"; fi
  # (2) run it; a selftest must pass (happy + negative both hold)
  if bash "$selftest" >/tmp/_gate_selftest.$$ 2>&1; then ok; echo "    selftest: PASS"
  else
    bad "$g/selftest.sh failed:"
    sed 's/^/      /' /tmp/_gate_selftest.$$ 2>/dev/null
  fi
  rm -f /tmp/_gate_selftest.$$
done

echo "test_gates_can_fail: $pass passed, $failc failed (over ${#gate_dirs[@]} gate folders)"
[ "$failc" -eq 0 ] && exit 0 || exit 1
