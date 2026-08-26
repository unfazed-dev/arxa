#!/bin/sh
# verdict.sh — the command a harness plugin spawns for an allow/deny verdict.
#
# A one-line indirection so a harness config file names a stable path while the
# policy behind it can move. Resolves the checkout from this script's own real
# path, so it works in any clone (never hard-code a path into a harness config).
#
# stdin: one JSON object (see harness/README.md). exit 0 = allow, 2 = deny.
self="$0"
while [ -L "$self" ]; do
  link=$(readlink "$self")
  case "$link" in
    /*) self="$link" ;;
    *)  self="$(dirname "$self")/$link" ;;
  esac
done
REPO=$(CDPATH= cd -- "$(dirname -- "$self")/.." && pwd -P)
exec node "$REPO/hooks/arxa-guard.js" "$@"
