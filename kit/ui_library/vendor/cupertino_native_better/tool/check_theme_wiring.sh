#!/bin/bash
# Deterministic wiring check for the iOS 26 liquid-glass theme-flip cure.
# Fails (exit 1) if any native view that handles brightness is missing part
# of the stack, or a banned pattern reappears. The mechanics and the
# clip-by-clip evidence live in the app-box repo at
# docs/plans/native-glass-theme-lag-measured.md; the checklist for NEW view
# types is in this package's AGENTS.md.
set -u
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
VIEWS="$TOOL_DIR/../ios/cupertino_native_better/Sources/cupertino_native_better/Views"

fail=0

# 1. Banned patterns — both pin the whole window and break ThemeMode.system.
#    (Comment lines are allowed: the cure's doc comments name the patterns.)
if grep -rhE 'window\.overrideUserInterfaceStyle|\.preferredColorScheme\(' "$VIEWS" \
   | grep -vE '^\s*//|^\s*\*' | grep .; then
  echo "FAIL: banned appearance pattern (window-level override / .preferredColorScheme)"
  fail=1
fi

# 2. Every Swift file that handles brightness must carry the full cure:
#    scoped overrideUserInterfaceStyle + CNAppearanceSettleReplay (property
#    AND poke = at least 2 hits). GlassButtonSwiftUI is a pure SwiftUI
#    component driven by its parent view and has no channel of its own.
for f in "$VIEWS"/*.swift; do
  if grep -qE '"setBrightness"|func updateConfig' "$f"; then
    ov=$(grep -c 'overrideUserInterfaceStyle' "$f")
    sr=$(grep -c 'settleReplay' "$f")
    if [ "$ov" -lt 1 ] || [ "$sr" -lt 2 ]; then
      echo "FAIL: $(basename "$f") handles brightness but is under-wired (override=$ov settleReplay=$sr)"
      fail=1
    fi
  fi
done

# 3. Every Dart component that wraps a platform view must push brightness on
#    flips (setBrightness / _syncBrightnessIfNeeded / updateConfig). Pure-Dart
#    compositions (split_button -> CNGlassButtonGroup, bottom_sheet, toast,
#    gesture/state helpers) inherit brightness from their child and are
#    exempt — they never touch a channel.
for f in "$TOOL_DIR"/../lib/components/*.dart; do
  if grep -qE 'UiKitView|AppKitView|MethodChannel|PlatformViewLink' "$f" \
     && ! grep -qE 'setBrightness|_syncBrightnessIfNeeded|updateConfig' "$f"; then
    echo "FAIL: lib/components/$(basename "$f") wraps a platform view but never pushes brightness"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then echo "OK: theme wiring complete"; fi
exit $fail
