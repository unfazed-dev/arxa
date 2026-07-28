---
description: "Route a goal-verb (tap/type/screenshot/…) to the right target-class script (read-only resolver; prints the exact command + args + fallback + notes)."
allowed-tools: Bash(python3 *)
argument-hint: "<intent> [--target ios|adb|web|macos|flutter|safari]   # e.g. tap --target ios ; --list ; (bare = full matrix)"
---

!`python3 ${CLAUDE_SKILL_DIR}/scripts/pr-decide.py $ARGUMENTS`
