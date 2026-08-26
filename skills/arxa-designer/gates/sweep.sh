#!/usr/bin/env bash
# Artifact gate sweep — the four craft gates x four styles x light+dark probes.
# Ported from ez-lab-tools/sweep.sh, parameterized for ANY designer artifact
# (TL-19/TL-20): the gates key on the FAMILY CLASS CONTRACT, not on a URL.
#
# usage: ./sweep.sh [style ...]
#   BASE_URL   default http://127.0.0.1:4319  (the design server)
#   SPECIMEN   default /specimens             (the artifact's specimen route)
#   OUT_DIR    default ./sweep-out
#
# Discipline (inherited, learned from two false greens):
#   - rm the --out file first, so a throw can never leave a stale pass
#   - never silence stderr; a missing output file is a FAILURE
#   - 0 assertions checked is a FAILURE (read-gate.js enforces)
# The artifact under test MUST expose the specimen route with every family
# its registry touches, open states live, classes per the family contract.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE_URL="${BASE_URL:-http://127.0.0.1:4319}"
SPECIMEN="${SPECIMEN:-/specimens}"
OUT_DIR="${OUT_DIR:-$HERE/sweep-out}"
STYLES=("$@"); [ ${#STYLES[@]} -eq 0 ] && STYLES=(liquid-glass m3-expressive shadcn custom)

mkdir -p "$OUT_DIR"
URL="${BASE_URL%/}${SPECIMEN}"

# a gate that won't parse can't be trusted to have run
for g in geometry icons audit interact; do
  node --check "$HERE/gate-$g.js" || { echo "!! gate-$g.js SYNTAX FAIL — aborting"; exit 1; }
done

rc=0
for S in "${STYLES[@]}"; do
  echo "=== $S ==="
  for g in geometry icons audit interact; do
    O="$OUT_DIR/${g}-${S}.json"
    rm -f "$O"
    arxa lens eval "$URL?style=$S" "$(cat "$HERE/gate-$g.js")" \
      1280 900 --settle=1200 --out="$O" >/dev/null
    node "$HERE/read-gate.js" "$O" "  $g" || rc=1
  done
done

echo
[ $rc -eq 0 ] && echo "ALL GATES GREEN" || echo "OUTSTANDING FAILURES — see ✗ lines above"
exit $rc
