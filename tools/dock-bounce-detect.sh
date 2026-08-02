#!/bin/bash
# Dock-bounce detector for appbox-launched Chrome.
#
# A Dock bounce requires a Dock TILE, and a tile means LaunchServices has the
# process registered as `Foreground`. This polls that, at 20ms, for OUR Chrome
# only — resolved by the unique `--user-data-dir` prefix appbox launches with.
#
# Scoped to our pid on purpose. An earlier version tested `lsappinfo
# visibleProcessList | grep -i chrome`, which is a permanent false positive on
# any machine where the user has Chrome open — i.e. it could not be run by the
# person most likely to need it.
#
# Calibration (measured, so a silent detector is distinguishable from a working
# one): Chrome launched with no --headless holds a tile for ~49 samples (~1s).
# A user-visible bounce is >=250ms, so >=12 samples. Anything under ~10 samples
# is a registration blip or a dying process, NOT a bounce.
#
#   Usage: tools/dock-bounce-detect.sh <command...>
#   e.g.   tools/dock-bounce-detect.sh dart run appboxd/bin/appbox.dart \
#            lens shot http://127.0.0.1:4319/design /tmp/x.png 800 600
set -u
HITS=$(mktemp /tmp/dockdetect-XXXXXX); : > "$HITS"

(
  while :; do
    # Every appbox Chrome alive right now (browser processes only — renderers
    # and helpers carry --type= and never own a tile).
    pids=$(ps -eo pid=,command= \
           | grep -E 'appbox-cdp-|appbox-design-worker-' \
           | grep -v -- '--type=' | grep -v grep | awk '{print $1}')
    saw=0
    for p in $pids; do
      t=$(lsappinfo info -only ApplicationType "$p" 2>/dev/null)
      case "$t" in *Foreground*) saw=1; echo "$p" >> "$HITS.pids" ;; esac
    done
    echo "$saw" >> "$HITS"
    sleep 0.02
  done
) & POLLER=$!

"$@"; RC=$?
sleep 1
kill $POLLER 2>/dev/null; wait $POLLER 2>/dev/null

MAX=$(awk '{if($1=="1"){c++; if(c>m)m=c}else{c=0}} END{print m+0}' "$HITS")
TOT=$(grep -c '^1$' "$HITS" 2>/dev/null || echo 0)
SAMP=$(wc -l < "$HITS" | tr -d ' ')

echo
echo "=== dock-bounce-detect ==="
echo "  samples          : $SAMP (20ms apart)"
echo "  foreground total : $TOT"
echo "  longest run      : $MAX  (~$((MAX*20))ms)"
if [ "$MAX" -ge 10 ]; then
  echo "  VERDICT          : *** BOUNCES *** (>=200ms of Dock tile)"
  [ -f "$HITS.pids" ] && echo "  offending pid(s) : $(sort -u "$HITS.pids" | tr '\n' ' ')"
elif [ "$TOT" -gt 0 ]; then
  echo "  VERDICT          : blip only ($TOT samples, longest $MAX) — below the ~250ms a bounce needs"
else
  echo "  VERDICT          : clean — no appbox Chrome ever held a Dock tile"
fi
rm -f "$HITS" "$HITS.pids"
exit $RC
