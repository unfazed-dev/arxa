#!/bin/bash
# iOS choreography for device_input_probe — real touches via idb ui
# (coordinates in POINTS). Field taps aim at the AX TextField frame because
# the bar's padded center can miss the field (measured 2026-08).
# Prereqs: simulator booted with idb companion, app installed & launched.
# Usage: ./ios_choreo.sh [UDID] [BUNDLE]
set -u
UDID=${1:-A52F8736-4F84-408E-9916-07EA78D411FA}
BUNDLE=${2:-dev.arxa.deviceInputProbe}
SHOTS=/tmp/probe_ios_shots
mkdir -p "$SHOTS"

field_pos() {
  idb ui describe-all --udid "$UDID" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
f=[e for e in d if 'TextField' in str(e.get('role',''))]
print(int(f[0]['frame']['x'])+176, int(f[0]['frame']['y'])+11) if f else print(201,809)"
}
tapfunc()   { local x=$1 y=$2 dur=$3; for a in 1 2 3 4; do idb ui tap --duration "$dur" --udid "$UDID" "$x" "$y" >/dev/null 2>&1 && return 0; sleep 3; done; }
swipefunc() { idb ui swipe --duration 0.3 --udid "$UDID" 201 400 201 220 >/dev/null 2>&1; }
container() { xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null; }
names_choose() { case "$1" in
  1) echo idle;; 2) echo focused;; 3) echo retap;; 4) echo dismissed;;
  5) echo refocus;; 6) echo grown;; 7) echo shrunk;; 8) echo menu;;
  9) echo drag;; 10) echo pair;; 11a) echo refocus2;; 11b) echo addtap;;
esac; }

start=$SECONDS
C=""
for i in 1 2 3 4 5 6 7 8 9 10 11a 11b; do
  marker=""; payload=""
  while [ -z "$marker" ]; do
    [ $((SECONDS - start)) -gt 1500 ] && echo "TIMEOUT phase $i" && exit 2
    C=$(container)
    if [ -n "$C" ] && [ -f "$C/tmp/phase$i.done" ]; then marker="$C"; payload=$(cat "$C/tmp/phase$i.done"); fi
    [ -z "$marker" ] && sleep 1
  done
  name=$(names_choose "$i")
  case "$payload" in
    tap:*)
      coords=${payload#tap:}; x=${coords%,*}; y=${coords#*,}
      # Phases 2/3/5 tap the composer field: aim at the AX frame, not the
      # padded bar center. 11a refocuses the composer (AX frame again) and
      # 11b taps the bar's add action (app-emitted coordinate is exact).
      case "$i" in 2|3|5|11a) read -r fx fy <<< "$(field_pos)"; x=$fx; y=$fy ;; esac
      tapfunc "$x" "$y" 0.1; sleep 2
      ;;
    long:*)
      read -r fx fy <<< "$(field_pos)"
      tapfunc "$fx" "$fy" 0.9; sleep 2
      ;;
    drag) swipefunc; sleep 2 ;;
    *) sleep 1 ;;
  esac
  xcrun simctl io "$UDID" screenshot "$SHOTS/p${i}_${name}.png" >/dev/null 2>&1
  touch "$marker/tmp/phase$i.go"
  echo "phase $i ($name) [$payload] done"
done
echo "--- composer.log ---"
cat "$C/tmp/composer.log"
