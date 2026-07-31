#!/usr/bin/env bash
# tools/vendor/check_freshness.selftest.sh — R5 proof the freshness oracle fails.
# 1. fresh immediately after copy (real VENDOR.lock)   => exit 0
# 2. STALE when a row's SHA is edited by one character  => exit 1 + names the item
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CF="$HERE/check_freshness.sh"
LOCK="$HERE/VENDOR.lock"
[ -f "$LOCK" ] || { echo "selftest: missing $LOCK"; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

pass=0; failc=0
ok()  { echo "  PASS: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; failc=$((failc + 1)); }

# 1 — fresh immediately after copy
if bash "$CF" "$LOCK" >/tmp/cf1 2>&1; then ok "fresh immediately after copy"
else bad "should be fresh right after copy"; cat /tmp/cf1; fi

# 2 — STALE on a one-character SHA edit
cp "$LOCK" "$TMP/VENDOR.lock"
# mutate the first SHA: flip its last hex char
python3 -c '
import re, sys
p = sys.argv[1]
s = open(p).read()
m = re.search(r"\|([0-9a-f]{40})\|", s)
if not m: sys.exit("no sha found")
sha = m.group(1); row = m.group(0)
new = sha[:-1] + ("0" if sha[-1] != "0" else "1")
s = s.replace(row, row.replace(sha, new), 1)
open(p, "w").write(s)
' "$TMP/VENDOR.lock"
if bash "$CF" "$TMP/VENDOR.lock" >/tmp/cf2 2>&1; then bad "drift not detected (should be STALE)"
elif grep -q "STALE" /tmp/cf2; then ok "STALE detected on one-character SHA edit"
else bad "failed but no STALE line"; cat /tmp/cf2; fi

echo "---"
echo "selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ]
