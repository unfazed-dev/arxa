#!/usr/bin/env bash
# sweep_rename.sh — H7 full rename pass (engine brand rename).
#
# The old-name tokens are COMPOSED from fragments below so this script can
# never contain — and therefore never self-corrupt by sweeping — its own
# pattern list. (The previous version of this script died exactly that way.)
#
# Run repeatedly until grep-clean; `--loop` iterates until clean or 5 passes.
# Skips: .git/ build/ .build/ .dart_tool/ node_modules/ archives/
#        and docs/plans/h7-full-rename-pass.md (documents the mapping).
#
# Usage: bash tools/sweep_rename.sh [--check|--loop] [target_root]
set -uo pipefail

ROOT="${2:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE="${1:-}"

# ---- token fragments (keeps this file grep-clean) ----
A="app"; B="box"; BD="${B}d"
lo="${A}${B}"          # lowercase old name
cap="A${A:1}B${B:1}"   # CapWords old name
ti="A${A:1}${B}"       # Titlecase old name
up="$(printf '%s' "${lo}" | tr '[:lower:]' '[:upper:]')"
hy="${A}-${B}"         # hyphenated old name
un="${A}_${B}"         # underscored old name
lod="${lo}d"           # daemon/package old name

# ---- ordered mapping: longest / most-specific first ----
OLD=(
  "package:${lod}"   "${lod}.dart"  "${lod}/"   "name: ${lod}"
  "${lod}"
  "${lo}_kit"        "${cap}Kit"
  "${cap}"           "${ti}"        "${A}B${B:1}"
  "${up}"            "${hy}"        "${un}"
  "${lo}"
)
NEW=(
  "package:arxa"     "arxad.dart"   "arxa/"     "name: arxa"
  "arxa"
  "arxa_kit"         "ArxaKit"
  "Arxa"             "Arxa"         "arxa"
  "ARXA"             "arxa"         "arxa"
  "arxa"
)

SKIP_RE='/(\.git|build|\.build|\.dart_tool|node_modules|archives)/'
SELF="tools/sweep_rename.sh"
PLANDOC="docs/plans/h7-full-rename-pass.md"

TOTAL_FILE="$(mktemp)"
one_pass() {
  local check="$1" total=0 i old new files count
  for i in "${!OLD[@]}"; do
    old="${OLD[$i]}"; new="${NEW[$i]}"
    files=$(grep -rlIF "$old" "$ROOT" 2>/dev/null \
      | grep -Ev "$SKIP_RE" | grep -vF "$SELF" | grep -vF "$PLANDOC" || true)
    [ -z "$files" ] && continue
    count=$(echo "$files" | xargs grep -oF "$old" 2>/dev/null | wc -l | tr -d ' ')
    printf '  %-22s -> %-14s %s occurrence(s)\n' "$old" "$new" "$count"
    total=$((total + count))
    if [ "$check" -eq 0 ]; then
      echo "$files" | while IFS= read -r f; do
        sed -i '' "s|${old}|${new}|g" "$f" 2>/dev/null || \
          sed -i "s|${old}|${new}|g" "$f"
      done
    fi
  done
  echo "$total" > "$TOTAL_FILE"
  echo "  pass total: $total occurrence(s)"
}

case "$MODE" in
  --check)
    echo "== check pass (no writes) =="
    one_pass 1
    ;;
  --loop)
    for n in 1 2 3 4 5; do
      echo "== sweep pass $n =="
      one_pass 0
      t="$(cat "$TOTAL_FILE")"
      if [ "$t" = "0" ]; then echo "grep-clean after $((n-1)) writing pass(es)"; exit 0; fi
    done
    echo "WARNING: not clean after 5 passes"; exit 1
    ;;
  *)
    echo "== single sweep pass =="
    one_pass 0
    ;;
esac
