#!/usr/bin/env bash
# gates/memory/selftest.sh — R5 suite for the memory hygiene gate.
# Delegates to the gate's embedded suite (memory.sh --self-test), the single
# source of truth: happy path + one negative per check (index cap, malformed
# facts, wrong fact shape, lessons cap, forbidden absolute path).
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/memory.sh"
bash "$GATE" --self-test
exit $?
