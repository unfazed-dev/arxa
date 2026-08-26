#!/usr/bin/env bash
# check_naming.sh — mechanical gate for the designer naming laws.
# See DESIGN-ARCHITECTURE.md "Naming laws (locked)" and
# docs/plans/no-single-letter-identifiers-law.md / design-filename-law.md.
#
# Usage: check_naming.sh <dir> [<dir>...]   (defaults to .)
# Scans generated js/jsx/ts/tsx for invented single-letter identifier
# bindings and for banned filenames. Prints file:line per violation,
# exits 1 if any violation is found, 0 when clean.
set -u

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(.)

violations=0

report() { # $1 = label; stdin = matches. Feed via `report label < <(cmd)` —
  # never on the right of a pipe, where a subshell would discard the count.
  local label="$1" out
  out=$(cat)
  if [ -n "$out" ]; then
    echo "── ${label}"
    echo "$out"
    violations=$((violations + $(printf '%s\n' "$out" | wc -l | tr -d ' ')))
  fi
}

prune() { # shared exclusions for find
  find "${targets[@]}" \
    \( -name node_modules -o -name .git -o -name dist -o -name build \
       -o -name vendor -o -name .arxa-cache \) -prune -o "$@" 2>/dev/null
}

# ── Filename law ─────────────────────────────────────────────────────────────
report "filename law" < <(
  prune -type f -print \
    | awk -F/ '{ base=$NF } base ~ /^_/ || base ~ /^v[0-9]+_/ \
        { print $0 ": banned filename (leading _ or version prefix)" }'
)

# ── Single-letter identifier law ─────────────────────────────────────────────
files=$(prune -type f \( -name '*.js' -o -name '*.jsx' -o -name '*.ts' -o -name '*.tsx' \) -print)

if [ -n "$files" ]; then
  scan() { printf '%s\n' "$files" | xargs grep -nE "$1" 2>/dev/null; }

  # 1. const/let/var declarations of a single letter (incl. for-of/in)
  report "single-letter const/let/var" < <(
    scan '\b(const|let|var)[[:space:]]+[A-Za-z]([[:space:]]*[=,;:]|[[:space:]]+(of|in)\b)'
  )

  # 2. function declared with a single-letter name
  report "single-letter function name" < <(
    scan '\bfunction[[:space:]]+[A-Za-z][[:space:]]*\('
  )

  # 3. single-letter params in function declarations
  report "single-letter function param" < <(
    scan '\bfunction([[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*)?[[:space:]]*\([[:space:]]*[A-Za-z]([[:space:]]*[,):]|[[:space:]]*$)'
  )

  # 4. bare single-letter arrow param:  x => ...
  report "single-letter arrow param (bare)" < <(
    scan '(^|[^A-Za-z0-9_$.)])[A-Za-z][[:space:]]*=>'
  )

  # 5. single-letter in a parenthesized arrow param list: (x), (x, y), (x: T) =>
  report "single-letter arrow param (parenthesized)" < <(
    scan '=>' \
      | grep -E '[,(][[:space:]]*[A-Za-z][[:space:]]*[,):]' \
      | grep -vE "['\"\`][^'\"\`]*=>"
  )

  # 5b. single-letter names in const/let/var destructuring: const [k, v] = / { a } =
  report "single-letter destructured binding" < <(
    scan '\b(const|let|var)[[:space:]]*[\[{]([^]}]*[^A-Za-z0-9_$])?[A-Za-z]([^A-Za-z0-9_$][^]}]*)?[]}]'
  )

  # 6. catch (e)
  report "single-letter catch param" < <(
    scan '\bcatch[[:space:]]*\([[:space:]]*[A-Za-z][[:space:]]*\)'
  )
fi

if [ "$violations" -gt 0 ]; then
  echo "NAMING GATE: FAIL — ${violations} violation(s)"
  exit 1
fi
echo "NAMING GATE: PASS"
