#!/usr/bin/env bash
# gates/_common/report.sh — pass/fail reporter. Every gate exits 0 or 1;
# this is the shared exit + message contract.
#
# Usage:
#   source "$(dirname "$0")/../_common/report.sh"
#   pass "structure in sync"
#   fail "orphan surface", "gates/structure/structure.json references foo which is not in the registry"
pass() { echo "PASS: $1"; exit 0; }
fail() { echo "FAIL: $1 — $2" >&2; exit 1; }
