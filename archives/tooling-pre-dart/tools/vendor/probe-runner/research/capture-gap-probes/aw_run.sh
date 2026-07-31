#!/bin/zsh
# aw_run.sh URL LABEL  — launch isolated Chrome, probe one site, kill Chrome.
# Host-only (CDP). No bash sleep (python polls CDP endpoint).
URL="$1"; LABEL="$2"; PORT=9334
PROFILE="/tmp/aw_chrome_${LABEL}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
rm -rf "$PROFILE"
"$CHROME" --remote-debugging-port=$PORT --user-data-dir="$PROFILE" \
  --no-first-run --no-default-browser-check --window-size=1280,900 \
  --disable-backgrounding-occluded-windows "about:blank" >/dev/null 2>&1 &
CHROME_PID=$!
python3 "$(dirname "$0")/aw_probe.py" "$URL" "$LABEL" $PORT
RC=$?
kill -9 $CHROME_PID 2>/dev/null
pkill -9 -f "remote-debugging-port=$PORT" 2>/dev/null
rm -rf "$PROFILE" 2>/dev/null
echo "---exit rc=$RC bytes=$(wc -c < $(dirname "$0")/out/${LABEL}.json 2>/dev/null || echo 0)---"
