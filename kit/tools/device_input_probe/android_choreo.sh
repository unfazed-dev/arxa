#!/bin/bash
# Android choreography for device_input_probe — real touches via adb input
# (coordinates in PIXELS; the app emits px payloads via devicePixelRatio).
# Prereqs: emulator booted, app installed & launched, and soft-keyboard forced:
#   adb shell settings put secure show_ime_with_hard_keyboard 1
# Usage: ./android_choreo.sh [serial] [shotsDir]
set -u
SER=${1:-emulator-5554}
PKG=dev.appbox.device_input_probe
SHOTS=${2:-/tmp/probe_android_shots}
mkdir -p "$SHOTS"
ADB="adb -s $SER"

run_as()   { $ADB shell run-as "$PKG" "$@" 2>/dev/null; }
ime_up()   { $ADB shell dumpsys input_method 2>/dev/null | grep -q 'mInputShown=true'; }
tap()      { $ADB shell input tap "$1" "$2"; }
LASTY=0  # y of the last tap_focus that verifiably focused the field
# This emulator's input delivery is FLAKY (measured: identical taps on an
# identical layout focus once and silently no-op minutes later; the emulator
# also hard-rebooted twice mid-session). Every load-bearing gesture is
# therefore retried until its OBSERVED effect holds — the same posture as the
# iOS choreo's idb retry loop. A dropped tap must never log a vacuous pass.
tap_focus() {  # keyboard must APPEAR (phases 2 and 5). Sweeps the bar's
  # vertical span with VERIFIED retries: the app emits the whole-bar Builder
  # center, which on Android has measured a transient unslept layout (rest
  # 162dp at P1 vs 90dp settled at P2), so the first coordinate can aim at a
  # stale frame. Each attempt is verified via dumpsys — no vacuous passes —
  # and the working y is echoed to pin the real geometry.
  local x=$1 y=$2 a yy
  for yy in "$y" $((y-42)) $((y-84)) $((y+38)); do
    for a in 1 2; do
      tap "$x" "$yy"; sleep 2
      if ime_up; then LASTY=$yy; echo "focus tap ok at y=$yy (emitted $y)"; return 0; fi
    done
  done
  echo "WARN: no tap in sweep around $y showed the IME"
}
tap_dismiss() { # keyboard must DISAPPEAR (phases 4 and 9)
  local x=$1 y=$2 a=1
  for a in 1 2 3 4; do
    if [ "$1" = drag ]; then $ADB shell input swipe 540 1000 540 500 300
    else tap "$x" "$y"; fi
    sleep 2
    ime_up || return 0
  done
  echo "WARN: dismiss at $1 never hid the IME"
}
tap_deliver() { # keyboard state cannot disambiguate (retap/long-press): fire twice
  tap "$1" "$2"; sleep 1.2; tap "$1" "$2"; sleep 1.5
}
longpress(){ $ADB shell input swipe "$1" "$2" "$1" "$2" 700; }
shot()     { $ADB exec-out screencap -p > "$SHOTS/$1.png"; }
names_choose() { case "$1" in
  1) echo idle;; 2) echo focused;; 3) echo retap;; 4) echo dismissed;;
  5) echo typed;; 6) echo grown;; 7) echo shrunk;; 8) echo longpress;;
  9) echo drag;; 10) echo pair;; 11a) echo refocus2;; 11b) echo addtap;;
esac; }

start=$SECONDS
for i in 1 2 3 4 5 6 7 8 9 10 11a 11b; do
  payload=""
  while [ -z "$payload" ]; do
    [ $((SECONDS - start)) -gt 1500 ] && echo "TIMEOUT phase $i" && exit 2
    payload=$(run_as cat code_cache/phase$i.done | tr -d '\r\n')
    [ -z "$payload" ] && sleep 1
  done
  name=$(names_choose "$i")
  case "$payload" in
    tap:*)
      coords=${payload#tap:}; x=${coords%,*}; y=${coords#*,}
      case "$i" in
        # 11a dismisses FIRST: after P10 the second field holds focus and the
        # keyboard is already up, so an IME-up check alone would vacuously
        # pass on a tap that hit nothing. Dismiss, then sweep for the
        # composer's own focus.
        11a) tap_dismiss 540 800; tap_focus "$x" "$y" ;;
        2|5) tap_focus "$x" "$y" ;;
        4)   tap_dismiss "$x" "$y" ;;
        3|10) tap_deliver "$x" "$y" ;;
        11b) # add-action tap: keyboard must SURVIVE — verified, one shot is
             # enough to read state after (the log line is the assertion).
             tap "$x" "$y"; sleep 2 ;;
        *)   tap "$x" "$y"; sleep 2 ;;
      esac
      # After phase 5's re-focus tap, feed text through the real IME (P5b).
      if [ "$i" = 5 ]; then
        $ADB shell input text 'ime_typed_ok'; sleep 3
      fi
      ;;
    long:*)
      # The app emits the whole-bar Builder center; with the keyboard up that
      # lands ON the keyboard (the bar's internal riding padding is inside the
      # measured box — measured: hint y=1872 vs keyboard top ~1518; a naive
      # long-press there repeats a G into the field). Dismiss first (verified),
      # re-focus via the verified sweep (captures the real field y), THEN
      # long-press the WORKING coordinate.
      coords=${payload#long:}; x=${coords%,*}; y=${coords#*,}
      tap_dismiss 540 800
      tap_focus "$x" "$y"
      if [ "$LASTY" -gt 0 ]; then longpress "$x" "$LASTY"; sleep 2; fi
      ;;
    drag)
      tap_dismiss drag drag; sleep 2
      ;;
    *) sleep 1 ;;
  esac
  shot "p${i}_${name}"
  run_as touch code_cache/phase$i.go
  echo "phase $i ($name) [$payload] done"
done
run_as cat code_cache/composer.log > "$SHOTS/composer.log" 2>/dev/null
echo "--- composer.log ---"
cat "$SHOTS/composer.log"
