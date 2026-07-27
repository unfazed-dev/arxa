#!/usr/bin/env bash
# tools/lint_conventions.selftest.sh — R5 proof that the linter can fail.
# For each rule, plants the defect in an isolated temp git repo and asserts the
# linter exits 1 AND names the offending file. A selftest that proves only the
# happy path is rejected (R5). Exits non-zero if any case does not behave.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint_conventions.sh"
REALROOT="$(cd "$HERE/.." && pwd)"

pass=0; failc=0
ok()  { echo "  PASS: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; failc=$((failc + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

setup_clean() {
  rm -rf "$TMP"; mkdir -p "$TMP/config" "$TMP/gates/foo" "$TMP/gates/_common"
  git init -q "$TMP"
  cp "$REALROOT/config/stripped_names.txt" "$TMP/config/" 2>/dev/null || \
    printf 'flutter-crew\nkimi-design\np2\n' > "$TMP/config/stripped_names.txt"
  cp "$REALROOT/config/forbidden_abs_prefixes.txt" "$TMP/config/" 2>/dev/null || \
    printf '/Volumes/\n/Users/\n' > "$TMP/config/forbidden_abs_prefixes.txt"
  printf '#!/usr/bin/env bash\n# clean gate\nsource "$(dirname "$0")/../_common/state_reader.sh"\n' \
    > "$TMP/gates/foo/foo.sh"
}

# 0 — clean tree passes
setup_clean
if bash "$LINT" "$TMP" >/tmp/box_lint0 2>&1; then ok "clean tree passes"
else bad "clean tree should pass"; cat /tmp/box_lint0; fi

# (a) absolute path literal outside config/
setup_clean
printf '#!/usr/bin/env bash\ncp /Volumes/evil/source x\n' > "$TMP/gates/foo/a.sh"
if bash "$LINT" "$TMP" >/tmp/box_lintA 2>&1; then bad "(a) absolute path not detected"
elif grep -q "a.sh" /tmp/box_lintA && grep -qi "absolute" /tmp/box_lintA; then ok "(a) absolute path flagged & named"
else bad "(a) flagged but not named"; cat /tmp/box_lintA; fi

# (b) gate imports sibling gate
setup_clean
mkdir -p "$TMP/gates/bar"
printf '#!/usr/bin/env bash\nsource "$(dirname "$0")/../bar/run.sh"\n' > "$TMP/gates/foo/foo.sh"
if bash "$LINT" "$TMP" >/tmp/box_lintB 2>&1; then bad "(b) sibling import not detected"
elif grep -q "foo.sh" /tmp/box_lintB && grep -qi "sibling" /tmp/box_lintB; then ok "(b) sibling import flagged & named"
else bad "(b) flagged but not named"; cat /tmp/box_lintB; fi

# (c) git diff --exit-code
setup_clean
printf '#!/usr/bin/env bash\ngit diff --exit-code\n' > "$TMP/gates/foo/c.sh"
if bash "$LINT" "$TMP" >/tmp/box_lintC 2>&1; then bad "(c) git diff --exit-code not detected"
elif grep -q "c.sh" /tmp/box_lintC; then ok "(c) git diff --exit-code flagged & named"
else bad "(c) flagged but not named"; cat /tmp/box_lintC; fi

# (d) stripped name in content
setup_clean
printf '#!/usr/bin/env bash\n# ported from flutter-crew\n' > "$TMP/gates/foo/d.sh"
if bash "$LINT" "$TMP" >/tmp/box_lintD 2>&1; then bad "(d) stripped name not detected"
elif grep -q "d.sh" /tmp/box_lintD && grep -qi "flutter-crew" /tmp/box_lintD; then ok "(d) stripped name flagged & named"
else bad "(d) flagged but not named"; cat /tmp/box_lintD; fi

# (d) stripped name in PATH
setup_clean
printf '#!/usr/bin/env bash\n# clean\n' > "$TMP/kimi-design-thing.sh"
if bash "$LINT" "$TMP" >/tmp/box_lintDP 2>&1; then bad "(d) stripped name in path not detected"
elif grep -q "kimi-design-thing.sh" /tmp/box_lintDP; then ok "(d) stripped name in path flagged"
else bad "(d-path) flagged but not named"; cat /tmp/box_lintDP; fi

echo "---"
echo "selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ]
