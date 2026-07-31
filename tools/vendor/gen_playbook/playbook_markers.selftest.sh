#!/usr/bin/env bash
# playbook_markers.selftest.sh — the TODO(prose) discipline (plan 03.7).
# gen_playbook.py emits a <!-- TODO(prose): ... --> marker for every narrative
# section it could not fill from source. A shipped playbook must have ZERO: a
# marker is an unfilled section, i.e. an incomplete doc that reads as complete.
# This is the appbox-* skill counterpart of test_memory.sh's per-kit assertion
# ("rich README => zero TODO(prose) markers in generated playbooks").
#
# R5: includes a negative case — plant a marker and prove the check goes red.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
SKILLS="$ROOT/skills"

pass=0; failc=0
ok()  { echo "  PASS: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; failc=$((failc + 1)); }

PLAYBOOKS=(
  "$SKILLS/appbox-builder/BUILDER_playbook.mdx"
  "$SKILLS/appbox-deployer/DEPLOYER_playbook.mdx"
  "$SKILLS/appbox-reviewer/REVIEWER_playbook.mdx"
  "$SKILLS/appbox-tester/TESTER_playbook.mdx"
  "$SKILLS/appbox-lint/LINT_playbook.mdx"
)

# 1 — happy path: every shipped playbook has zero TODO(prose) markers.
all_zero=1
for p in "${PLAYBOOKS[@]}"; do
  [ -f "$p" ] || { bad "missing playbook: $p"; all_zero=0; continue; }
  n=$(grep -c 'TODO(prose)' "$p" || true)
  if [ "$n" -eq 0 ]; then ok "$(basename "$p"): 0 TODO(prose) markers"
  else bad "$(basename "$p"): $n TODO(prose) marker(s) — fill the section"; all_zero=0; fi
done

# 2 — negative case (R5): a planted marker MUST be detected.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '<Callout id="h">\n### Section\n\n<!-- TODO(prose): planted gap -->\n</Callout>\n' > "$TMP"
n=$(grep -c 'TODO(prose)' "$TMP" || true)
if [ "$n" -ge 1 ]; then ok "negative: planted marker detected ($n)"
else bad "negative: planted marker NOT detected — the check is vacuous"; all_zero=0; fi

echo "---"
echo "selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ]
