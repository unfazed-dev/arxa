#!/usr/bin/env bash
# tools/vendor/check_freshness.sh — the freshness oracle (plan 03.3).
# For each row in VENDOR.lock, compare the recorded path SHA against the upstream
# repo's current SHA for that path.
#   - drift      => FAIL LOUDLY (exit 1). A stale copy that reports "ok" is the
#                   exact stale-green pattern this project exists to prevent.
#   - unreachable=> exit 0 with a clear "freshness NOT verified" message.
#                   Unreachable is not the same as fresh, and the message says so.
# Usage: check_freshness.sh [LOCK]   (LOCK defaults to tools/vendor/VENDOR.lock)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LOCK="${1:-$ROOT/tools/vendor/VENDOR.lock}"
[ -f "$LOCK" ] || { echo "check_freshness: missing $LOCK" >&2; exit 2; }

drift=0; unreachable=0; fresh=0
while IFS='|' read -r name repo path sha date; do
  [ -z "$name" ] && continue
  if [ ! -d "$repo/.git" ] && ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "UNREACHABLE  $name  (repo $repo missing) — freshness NOT verified"
    unreachable=$((unreachable + 1)); continue
  fi
  cur="$(git -C "$repo" log -1 --format=%H -- "$path" 2>/dev/null)"
  if [ -z "$cur" ]; then
    echo "UNREACHABLE  $name  (path '$path' not in upstream) — freshness NOT verified"
    unreachable=$((unreachable + 1)); continue
  fi
  if [ "$cur" != "$sha" ]; then
    echo "STALE        $name  (recorded ${sha:0:12}… upstream ${cur:0:12}…) — upstream changed"
    drift=$((drift + 1))
  else
    echo "FRESH        $name"
    fresh=$((fresh + 1))
  fi
done < "$LOCK"

echo "---"
echo "fresh=$fresh stale=$drift unreachable=$unreachable"
if [ "$drift" -gt 0 ]; then
  echo "check_freshness: FAILED — $drift vendored item(s) drifted from upstream" >&2
  exit 1
fi
exit 0
