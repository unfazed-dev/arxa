---
description: "Pixel diff two PNGs; emits a similarity score."
allowed-tools: Bash(python3 *)
argument-hint: "args for scripts/pixdiff.py"
---

!`python3 ${CLAUDE_SKILL_DIR}/scripts/pixdiff.py $ARGUMENTS`

### Canvas-only diff (skip the chrome)

```bash
/pr-pixdiff A.png B.png --region 400,200,1120,820
```

Crops both inputs to a 1120×820 region starting at (400, 200) before differencing. The output JSON echoes the region under `"region": {…}`. Use when the surrounding toolbar/breadcrumb/sidebar would dilute a per-tile mean-RGB score below the threshold.
