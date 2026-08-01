#!/usr/bin/env bash
# phase5_kit_copy.sh — copy stacked_kit packages into appbox, rename imports.
#
# Copies 24 library packages from the stacked_kit sibling repo into
# appbox/packages/, then rewrites all stacked_kit_* identifiers to
# appbox_kit_* across .dart and .yaml files.
#
# Usage: bash tools/phase5_kit_copy.sh
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../../stacked_kit" && pwd)"
DST="$(cd "$(dirname "$0")/.." && pwd)/packages"

# Packages to copy (all library packages, excluding showcase_app).
PACKAGES=(analytics auth bluetooth branding compliance core data deploy \
  documents forms genui_bridge haptics i18n maps media motion notifications \
  payments permissions security state support ui_library wifi)

echo "=== Phase 5: appbox kit copy ==="
echo "Source: $SRC"
echo "Target: $DST"
echo "Packages: ${#PACKAGES[@]}"
echo ""

# Step 1: Copy packages (exclude build artifacts).
mkdir -p "$DST"
for pkg in "${PACKAGES[@]}"; do
  if [ ! -d "$SRC/$pkg" ]; then
    echo "  SKIP $pkg (not found in source)"
    continue
  fi
  echo -n "  copy $pkg... "
  rsync -a --exclude='build/' --exclude='.dart_tool/' --exclude='.packages' \
    --exclude='.DS_Store' \
    "$SRC/$pkg/" "$DST/$pkg/"
  echo "done"
done

echo ""
echo "Step 2: Rewrite stacked_kit_ → appbox_kit_ in .dart and .yaml files..."

# Global replacement of the stacked_kit_ prefix across all copied files.
# This catches: package names in imports, pubspec name: fields, dependency
# keys, path-dep references, and comments.
COUNT=0
while IFS= read -r -d '' file; do
  if grep -q 'stacked_kit_' "$file" 2>/dev/null; then
    sed -i '' 's/stacked_kit_/appbox_kit_/g' "$file"
    COUNT=$((COUNT + 1))
  fi
done < <(find "$DST" -type f \( -name '*.dart' -o -name '*.yaml' \) -print0)

echo "  Rewrote $COUNT file(s)"
echo ""

# Step 3: Verify no stale stacked_kit_ references remain.
STALE=$(grep -r 'stacked_kit_' "$DST" --include='*.dart' --include='*.yaml' -l 2>/dev/null || true)
if [ -n "$STALE" ]; then
  echo "  WARNING: stale stacked_kit_ references found:"
  echo "$STALE"
else
  echo "  Clean — no stale stacked_kit_ references."
fi

echo ""
echo "=== Phase 5 copy complete ==="
echo "  Dart files: $(find "$DST" -name '*.dart' | wc -l | tr -d ' ')"
echo "  Pubspecs:   $(find "$DST" -name pubspec.yaml | wc -l | tr -d ' ')"
