#!/usr/bin/env bash
# Watch a paired iPhone running the showcase app — builds/runs it and
# captures the session to a timestamped dir, so a device run needs no
# manual clipping or reporting:
#
#   console.log  — full `flutter run` output: Dart logs plus the `CNTrace`
#                  lines (theme-flip anchor + per-component setBrightness
#                  send/ack) for the theme-lag investigation
#                  (docs/plans/native-glass-theme-lag-measured.md §10-11).
#   frame-*.png  — timestamped screenshots, only when libimobiledevice is
#                  installed (brew install libimobiledevice); skipped with a
#                  note otherwise.
#
# Usage: tools/watch_device.sh     # auto-detects the connected iPhone
# Stop:  Ctrl-C. Output: logs/device-watch/<timestamp>/ — point at the dir,
# no report needed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/logs/device-watch/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"

udid="$(xcrun devicectl list devices 2>/dev/null | awk '$4 == "connected" { print $3; exit }')"
if [[ -z "${udid}" ]]; then
  echo "no connected iPhone — plug in, trust this Mac, retry" >&2
  exit 1
fi
# libimobiledevice uses the hardware UDID, not devicectl's CoreDevice UUID.
shot_udid="$(idevice_id -l 2>/dev/null | head -1)"
echo "device: $udid"
echo "output: $out"

frames_pid=""
if [[ -n "$shot_udid" ]] && command -v idevicescreenshot >/dev/null 2>&1; then
  # screenshotr lives on the Developer Disk Image, which mounts when the
  # debug app launches — so the loop just retries until it appears.
  (
    i=0
    while true; do
      i=$((i + 1))
      idevicescreenshot -u "$shot_udid" "$out/frame-$(date +%H%M%S)-$i.png" >/dev/null 2>&1 || true
      sleep 0.7
    done
  ) &
  frames_pid=$!
  echo "frames: $out/frame-*.png (starts once the app launches)"
else
  echo "frames: skipped — libimobiledevice not installed (brew install libimobiledevice)"
fi

trap '[[ -n "$frames_pid" ]] && kill "$frames_pid" 2>/dev/null || true' EXIT

cd "$root/kit/showcase_app"
flutter run -d "$udid" --debug 2>&1 | tee "$out/console.log"
