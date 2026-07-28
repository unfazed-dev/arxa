# brainiac perf smoke

End-to-end recipe against the `perf_domain_heavy_100` example in
brainiac-visualizer. Validates capture + drive + (with the template
installed) DOM probe.

## Pre-reqs

- brainiac-visualizer compiled with `cargo run -p brainiac-visualizer
  --example perf_domain_heavy_100` already running in another shell.
- (Optional) brainiac-visualizer rebuilt with `--features debug-probe`
  if you want DOM probes (see `templates/dioxus_cargo_feature.md`).

## Steps

```bash
APP=perf_domain_heavy_100
S=.claude/skills/probe-runner/scripts

# 1. confirm the app is up
python3 $S/find_window.py "$APP"

# 2. baseline screenshot
BASE=$(python3 $S/shot.py "$APP")
echo "baseline: $BASE"

# 3. cycle the sector strategy (Cmd+Shift+S)
python3 $S/key_chord.py "$APP" "cmd+shift+s"
sleep 0.5

# 4. after-shot, then diff
AFTER=$(python3 $S/shot.py "$APP")
python3 $S/pixdiff.py "$BASE" "$AFTER" --threshold 0.01

# 5. scroll the sidebar down 500 px
python3 $S/scroll.py "$APP" 0 -500

# 6. 5-second screencast with click highlights
python3 $S/record.py "$APP" --seconds 5 --clicks

# 7. DOM probe (only with --features debug-probe enabled)
python3 $S/dom.py "$APP" --selector ".brainiac-canvas svg"
```

## Expected output

Each command emits its result file path or JSON to stdout. `pixdiff`
should report `"above_threshold": true` after the strategy cycle. The
recording lands in `${PROBE_RUNNER_OUTDIR:-/tmp/probe-runner}/`.
