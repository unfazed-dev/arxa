#!/usr/bin/env bash
# gates/_common/assert_design_fresh.sh — the §6 checker. Architecture §6 binds
# approval to a hash: once freeze records state.designHash, a design-consuming
# gate must fail if the design has moved since. Run EARLY in a gate, before its
# own assertions:
#
#   if ! fresh="$(bash "$GATE_COMMON/assert_design_fresh.sh" "$DESIGN" 2>&1)"; then
#     printf '%s\n' "$fresh"; exit 1
#   fi
#   [ -n "$fresh" ] && printf '%s\n' "$fresh"
#
# Verdicts:
#   designHash empty            -> PASS with a note (legacy state — fail-open ONLY
#                                  here; a hash that was never written cannot be
#                                  checked). A WRITTEN hash never fails open.
#   designHash set, dir absent  -> PASS with a note; the gate's own input checks
#                                  (4.4) fail on the missing design far better.
#   designHash set, dir present -> recompute and compare. Mismatch: exit 1, red,
#                                  naming designHash and §6.
#
# Usage: assert_design_fresh.sh <design-dir>   (0 fresh/legacy / 1 moved / 2 env)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=state_reader.sh
source "$HERE/state_reader.sh"
# state_reader.sh enables `set -e`; this script treats a failed check as a
# verdict, not an abort. Re-assert.
set -uo pipefail
set +e

DESIGN="${1:-}"
[ -n "$DESIGN" ] || { echo "FAIL: assert_design_fresh.sh: no design dir given" >&2; exit 2; }

STORED="$(state_get designHash 2>/dev/null)"
if [ -z "$STORED" ]; then
  echo "  · designHash: empty in pipeline state — legacy/unbound design, freshness not enforced (§6 binds only a written hash)"
  exit 0
fi
if [ ! -d "$DESIGN" ]; then
  echo "  · designHash: design dir absent at $DESIGN — freshness N/A here; the gate's own input checks (4.4) apply"
  exit 0
fi

CURRENT="$(bash "$HERE/design_hash.sh" "$DESIGN")" || exit 2
if [ "$CURRENT" = "$STORED" ]; then
  echo "  ✓ designHash: design matches the frozen hash (${STORED:0:12}…) (§6)"
  exit 0
fi
echo "FAIL: designHash: the design moved after freeze — state has ${STORED:0:12}…, the tree hashes to ${CURRENT:0:12}… (§6 hash-bound approval). Re-freeze the design, or restore it." >&2
exit 1
