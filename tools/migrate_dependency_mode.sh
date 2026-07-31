#!/usr/bin/env bash
# migrate_dependency_mode.sh — convert an app between vendored/hosted kit modes
# (plan 03.13). Idempotent: a no-op when already in the desired mode. Guarded on
# the desired end state, never on the starting state.
#
#   vendored → hosted : delete <app>/packages/, rewrite pubspec kit refs to ^x.y.z
#   hosted   → vendored: copy the derived kits into <app>/packages/, rewrite pubspec
#                       kit refs to path: packages/<dir>
#
# Usage: migrate_dependency_mode.sh <app-dir> --to vendored|hosted [--capabilities a,b]
# Env:   KIT_REPO — stacked_kit checkout (the copy source; required for --to vendored)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
KIT_DEPS="$ROOT/tools/kit_deps.py"

[ $# -ge 1 ] || { echo "usage: $0 <app-dir> --to vendored|hosted [--capabilities a,b]" >&2; exit 2; }
APP="$1"; shift
TO=""; CAPS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --to) TO="$2"; shift 2;;
    --capabilities) CAPS="$2"; shift 2;;
    *) shift;;
  esac
done
[ -n "$TO" ] || { echo "migrate: --to vendored|hosted required" >&2; exit 2; }
case "$TO" in vendored|hosted) :;; *) echo "migrate: unknown mode '$TO'" >&2; exit 2;; esac
[ -f "$APP/pubspec.yaml" ] || { echo "migrate: no pubspec at $APP/pubspec.yaml" >&2; exit 2; }

KD_ARGS=()
[ -n "$CAPS" ] && KD_ARGS=(--capabilities "$CAPS")

# current mode: vendored iff packages/ exists OR the pubspec carries a path:packages/ ref
CUR="hosted"
[ -d "$APP/packages" ] && CUR="vendored"
grep -q 'path: packages/' "$APP/pubspec.yaml" 2>/dev/null && CUR="vendored"

if [ "$CUR" = "$TO" ]; then
  echo "migrate: $APP already $TO (no-op)"; exit 0
fi

if [ "$TO" = "vendored" ]; then
  # hosted → vendored
  [ -n "${KIT_REPO:-}" ] || KIT_REPO="$(python3 -c "import json;print(json.load(open('$ROOT/config/appbox.config.json')).get('kit',{}).get('repo',''))")"
  [ -n "$KIT_REPO" ] && [ -d "$KIT_REPO" ] || { echo "migrate: KIT_REPO must point at the stacked_kit checkout for --to vendored" >&2; exit 2; }
  KIT_REPO="$KIT_REPO" python3 "$KIT_DEPS" copy --app "$APP" "${KD_ARGS[@]}" >/dev/null
  python3 "$KIT_DEPS" rewrite --app "$APP" --mode vendored "${KD_ARGS[@]}"
  echo "migrate: $APP hosted → vendored (kits copied into packages/, pubspec path deps)"
else
  # vendored → hosted
  rm -rf "$APP/packages"
  python3 "$KIT_DEPS" rewrite --app "$APP" --mode hosted "${KD_ARGS[@]}"
  echo "migrate: $APP vendored → hosted (packages/ removed, pubspec version constraints)"
fi
