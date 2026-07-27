#!/usr/bin/env bash
# tools/lint_conventions.sh — repo convention linter enforcing R2, R3, R4, R5.
# Fails (exit 1, naming the offending file) on:
#   (a) absolute project path literals outside config/            (R3)
#   (b) a gate importing a sibling gate (only gates/_common is OK) (R4)
#   (c) git diff --exit-code used for a regeneration assertion     (R5)
#   (d) a stripped upstream identity name in code or path          (R2)
# Usage: lint_conventions.sh [ROOT]   (ROOT defaults to the git toplevel)
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || { echo "lint: cannot cd to $ROOT" >&2; exit 2; }

NAMES="config/stripped_names.txt"
ABS="config/forbidden_abs_prefixes.txt"
[ -f "$NAMES" ] || { echo "lint: missing $NAMES" >&2; exit 2; }
[ -f "$ABS" ]   || { echo "lint: missing $ABS" >&2; exit 2; }

# bash 3.2-safe array population (no mapfile)
STRIPPED=()
while IFS= read -r _n; do [ -n "$_n" ] && STRIPPED+=("$_n"); done \
  < <(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$NAMES")
ABSPFX=()
while IFS= read -r _p; do [ -n "$_p" ] && ABSPFX+=("$_p"); done \
  < <(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$ABS")

violations=0
fail() { echo "LINT FAIL: $1 — $2" >&2; violations=$((violations + 1)); }

# Scan set: tracked + untracked(non-ignored), code/config only.
# Excludes docs/ (authoring layer), markdown, node_modules, licence/notice
# files, and the two lint-data config files (they define the rules).
FILES=()
while IFS= read -r _f; do [ -n "$_f" ] && FILES+=("$_f"); done < <(
  git ls-files --cached --others --exclude-standard 2>/dev/null \
  | grep -vE '^docs/' \
  | grep -vE 'node_modules/' \
  | grep -vE '\.md$' \
  | grep -vE '(^|/)LICENSE(\.|$)' \
  | grep -vE '^config/stripped_names\.txt$' \
  | grep -vE '^config/forbidden_abs_prefixes\.txt$' \
  | grep -vE '^tools/vendor/VENDOR\.lock$' \
  | grep -vE '^tools/lint_conventions\.sh$' \
  | grep -vE '^tools/lint_conventions\.selftest\.sh$' \
  | grep -vE '^\.git/' \
  | grep -vE '^\.kimi-code/' \
  || true
)

is_text() { grep -qI '' "$1" 2>/dev/null; }

# Rules (a), (c), (d) over content + (d) over path.
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  # (d) stripped name in PATH (as a whole token / path segment)
  for n in "${STRIPPED[@]}"; do
    if grep -qwF -- "$n" <<<"$f"; then
      fail "$f" "stripped upstream name '$n' in path (R2)"
    fi
  done
  is_text "$f" || continue
  outside_config=1
  case "$f" in config/*) outside_config=0 ;; esac
  while IFS= read -r line; do
    # Documentation comments may mention the rules. (a)/(c) are code-behaviour
    # rules and skip comments; the identity rule (d) still applies to comments
    # because R2 covers doc cross-links and log strings too.
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      for n in "${STRIPPED[@]}"; do
        grep -qwF -- "$n" <<<"$line" && fail "$f" "stripped upstream name '$n' in content (R2)"
      done
      continue
    fi
    # (a) absolute project path literal, outside config/
    if [ "$outside_config" -eq 1 ]; then
      for p in "${ABSPFX[@]}"; do
        case "$line" in *"$p"*) fail "$f" "absolute path literal '$p' (R3: read from config)" ;; esac
      done
    fi
    # (c) git diff --exit-code for a regeneration assertion
    case "$line" in *"git diff --exit-code"*)
      fail "$f" "git diff --exit-code cannot see untracked files; use git status --porcelain (R5)" ;; esac
    # (d) stripped name in content
    for n in "${STRIPPED[@]}"; do
      grep -qwF -- "$n" <<<"$line" && fail "$f" "stripped upstream name '$n' in content (R2)"
    done
  done < "$f"
done

# Rule (b) gate imports sibling gate — gate scripts only, _common exempt.
shopt -s nullglob
gate_dirs=()
for d in gates/*/; do
  _nm="$(basename "$d")"; [ "$_nm" = "_common" ] && continue; gate_dirs+=("$_nm")
done
for gf in gates/*/*.sh gates/*/*.py gates/*/*.dart; do
  [ -f "$gf" ] || continue
  own="$(basename "$(dirname "$gf")")"
  [ "$own" = "_common" ] && continue
  is_text "$gf" || continue
  while IFS= read -r line; do
    if [[ "$line" =~ gates/([A-Za-z_][A-Za-z0-9_-]*) ]]; then
      other="${BASH_REMATCH[1]}"
      for g in "${gate_dirs[@]}"; do
        if [ "$other" = "$g" ] && [ "$other" != "$own" ]; then
          fail "$gf" "imports sibling gate 'gates/$other' (R4: only gates/_common)"
        fi
      done
    fi
    if [[ "$line" =~ \.\./([A-Za-z_][A-Za-z0-9_-]*) ]]; then
      other="${BASH_REMATCH[1]}"
      for g in "${gate_dirs[@]}"; do
        if [ "$other" = "$g" ] && [ "$other" != "$own" ]; then
          fail "$gf" "imports sibling gate '../$other' (R4: only gates/_common)"
        fi
      done
    fi
  done < "$gf"
done

if [ "$violations" -eq 0 ]; then
  echo "LINT OK (${#FILES[@]} files scanned)"
  exit 0
fi
echo "LINT FAILED: $violations violation(s)" >&2
exit 1
