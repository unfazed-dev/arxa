#!/bin/zsh
# _launch.sh <script.py> [args...] — launch an isolated headed Chrome (CDP :9334),
# run a sibling probe script against it, then kill Chrome. Host-only (CDP needs host;
# the ctx sandbox cannot reach host localhost). No bash sleep — the python polls CDP.
# Use for the no-arg scripts: aw_scan.py / aw_iso.py / aw_ref.py / aw_ref2.py.
# For per-site deep probes use aw_run.sh URL LABEL instead.
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$1"; shift
PORT=9334; PROFILE="/tmp/aw_chrome_launch"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
rm -rf "$PROFILE"
"$CHROME" --remote-debugging-port=$PORT --user-data-dir="$PROFILE" \
  --no-first-run --no-default-browser-check --window-size=1280,900 \
  --disable-backgrounding-occluded-windows "about:blank" >/dev/null 2>&1 &
CP=$!
python3 "$HERE/$SCRIPT" "$@"
RC=$?
kill -9 $CP 2>/dev/null
pkill -9 -f "remote-debugging-port=$PORT" 2>/dev/null
rm -rf "$PROFILE" 2>/dev/null
echo "---launch exit rc=$RC---"
