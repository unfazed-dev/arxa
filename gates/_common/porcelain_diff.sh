#!/usr/bin/env bash
# gates/_common/porcelain_diff.sh — regeneration assertion helper (R5).
#
# A generator that ADDS a file is the expected case, and `git diff --exit-code`
# cannot see untracked files. Assert regeneration with `git status --porcelain`,
# NEVER `git diff --exit-code`.
#
# Usage:
#   source "$(dirname "$0")/../_common/porcelain_diff.sh"
#   assert_tree_unchanged "structure regenerated cleanly"
#     exits 1 and names offending paths if the working tree has changes,
#     exits 0 if clean.
assert_tree_unchanged() {
  local msg="$1"
  local dirty
  dirty="$(git status --porcelain)"
  if [ -n "$dirty" ]; then
    echo "FAIL: $msg" >&2
    printf '%s\n' "$dirty" | sed 's/^/  /' >&2
    return 1
  fi
  echo "OK: $msg"
  return 0
}
