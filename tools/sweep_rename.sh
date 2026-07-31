#!/usr/bin/env bash
# sweep_rename.sh — rename app-box → appbox across the repo.
#
# Run repeatedly until grep-clean (no matches for the old names).
# Safe: skips .git/, build/, .dart_tool/, node_modules/, archives/.
#
# Usage: bash tools/sweep_rename.sh [--check]
#   --check  Report what would change without writing.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# Patterns to find (old → new).
# Order matters: longer patterns first so they don't get partially replaced.
declare -a PATTERNS=(
  "app-box.config.json:appbox.config.json"
  "app-box-builder:appbox-builder"
  "app-box-designer:appbox-designer"
  "app-box-deployer:appbox-deployer"
  "app-box-intake:appbox-intake"
  "app-box-lint:appbox-lint"
  "app-box-moodboarder:appbox-moodboarder"
  "app-box-reviewer:appbox-reviewer"
  "app-box-scaffolder:appbox-scaffolder"
  "app-box-story-mapper:appbox-story-mapper"
  "app-box-tester:appbox-tester"
  "app-box:appbox"
  "app_box:appbox"
  "APP_BOX:APPBOX"
  "KIT_APP:APPBOX_APP"
)

# Directories to skip.
SKIP_RE='\(\.git\|build\|\.dart_tool\|node_modules\|archives\)/'

changed=0
for entry in "${PATTERNS[@]}"; do
  old="${entry%%:*}"
  new="${entry##*:}"
  hits=$(grep -rnF --include='*.dart' --include='*.py' --include='*.sh' \
    --include='*.md' --include='*.json' --include='*.yaml' \
    --include='*.js' --include='*.mjs' --include='*.html' \
    --include='*.css' --include='*.txt' \
    "$old" "$ROOT" 2>/dev/null | grep -v "$SKIP_RE" || true)
  if [ -n "$hits" ]; then
    count=$(echo "$hits" | wc -l | tr -d ' ')
    echo "  $old → $new: $count occurrence(s)"
    if [ "$CHECK" -eq 0 ]; then
      echo "$hits" | while IFS= read -r line; do
        file="${line%%:*}"
        sed -i '' "s|${old}|${new}|g" "$file" 2>/dev/null || \
          sed -i "s|${old}|${new}|g" "$file" 2>/dev/null || true
      done
      changed=$((changed + count))
    fi
  fi
done

if [ "$changed" -gt 0 ]; then
  echo "sweep: $changed replacement(s) made"
elif [ "$CHECK" -eq 1 ]; then
  echo "sweep: --check complete (no changes made)"
else
  echo "sweep: grep-clean — no occurrences found"
fi
