#!/usr/bin/env bash
# licence_assert.sh — the §17 LICENCE ASSERTION, run as the FIRST check of the
# deploy gate (P1: "Paid: clean outputs + deployable — deploy gate enforces the
# licence"; consolidation decision 11: the paywall sits at first deploy —
# design, prototype, build, gates and preview are all free; you pay when you
# ship). Deploy is the only phase that writes to the outside world.
#
# The source of truth is appboxd's licence_tool (built separately; P2:
# Ed25519-signed licence file, verified fully offline):
#
#   cd appboxd && dart run bin/licence_tool.dart status
#     stdout: {"status":"paid"|"free"|"none", "tier":..., "expires":...}
#     exit 0 for paid, 1 otherwise
#
# FAIL CLOSED, always: no paid verdict -> exit 1 with a purchase message.
# Tool missing, dart missing, or unparseable output -> exit 1 naming the
# reason. A paywall that fails open is the vacuous-PASS trap (dogfood
# honest-bar: green over broken is the failure class to guard against).
#
# DEV/DOGFOOD ESCAPE: APPBOX_DEV_LICENCE=1 bypasses the assertion with a loud
# stderr warning. It exists so this repo's own pipeline can dogfood without a
# real licence. Never ship with it set.
#
# MEMORY DOCTRINE (M1): every run appends one JSON line to the memory event
# log — {ts, kind:"gate_run", actor:"deploy-gate", payload:{verdict,
# licence_status}} — verdict is this assertion's verdict (green/red); on red
# the gate halts here so it is also the gate verdict. Best-effort: a logging
# failure warns on stderr and NEVER blocks the gate. Path defaults to
# pipeline/state/memory/events.jsonl; APPBOX_MEMORY_EVENTS overrides (tests).
#
# Test seams: APPBOX_APPBOXD_DIR overrides the appboxd directory (fixture
# licence_tool stubs); APPBOX_MEMORY_EVENTS overrides the event log path.
#
# Usage: licence_assert.sh   (0 licensed / 1 NOT LICENSED — prints why and how
#                             to activate)
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
APPBOXD="${APPBOX_APPBOXD_DIR:-$repo_root/appboxd}"
EVENTS="${APPBOX_MEMORY_EVENTS:-$repo_root/pipeline/state/memory/events.jsonl}"

# emit_event <verdict> <licence_status> — best-effort JSONL append; warns,
# never fails. Values are fixed enums set below, so plain printf is safe.
emit_event() {
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$EVENTS")" 2>/dev/null || {
    echo "deploy-gate: WARN memory dir not creatable — gate_run event not logged" >&2; return 0; }
  printf '{"ts":"%s","kind":"gate_run","actor":"deploy-gate","payload":{"verdict":"%s","licence_status":"%s"}}\n' \
    "$ts" "$1" "$2" >> "$EVENTS" 2>/dev/null || {
    echo "deploy-gate: WARN memory event append failed ($EVENTS) — continuing" >&2; }
  return 0
}

red() { # $1 licence_status  $2 reason — fail closed, naming the reason
  echo "PRECONDITION NOT MET: licence — $2" >&2
  cat >&2 <<'EOF'
Deploy writes to the outside world and requires a valid paid licence
(licence-only, flat, never per-seat — P1/P2). Everything before deploy is
free; you pay when you ship. Activate your offline-signed licence with
appboxd's licence_tool, then re-run the deploy gate.
EOF
  emit_event "red" "$1"
  exit 1
}

# --- dev/dogfood escape (first: must work even before licence_tool exists) ---
if [ "${APPBOX_DEV_LICENCE:-}" = "1" ]; then
  echo "*********************************************************************" >&2
  echo "*** WARNING: APPBOX_DEV_LICENCE=1 — licence assertion BYPASSED.     ***" >&2
  echo "*** Dev/dogfood only. Never ship a build with this set.             ***" >&2
  echo "*********************************************************************" >&2
  emit_event "green" "dev-bypass"
  exit 0
fi

# --- the assertion: shell out to appboxd's licence_tool ----------------------
[ -f "$APPBOXD/bin/licence_tool.dart" ] || \
  red "tool-missing" "licence_tool not found at $APPBOXD/bin/licence_tool.dart (appboxd licence module not built) — cannot verify a licence, failing closed."
command -v dart >/dev/null 2>&1 || \
  red "tool-missing" "dart not on PATH — cannot run licence_tool, failing closed."

out="$(cd "$APPBOXD" && dart run bin/licence_tool.dart status 2>/dev/null)"
rc=$?

# Parse the JSON contract; anything but a clean parse fails closed.
status="$(printf '%s' "$out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("status",""))
except Exception: print("")' 2>/dev/null)"
tier="$(printf '%s' "$out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tier") or "")
except Exception: print("")' 2>/dev/null)"
expires="$(printf '%s' "$out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("expires") or "")
except Exception: print("")' 2>/dev/null)"

case "$status" in
  paid|free|none) ;;
  *) red "tool-unparseable" "licence_tool output missing or unparseable (exit $rc, no {\"status\":...} JSON on stdout) — failing closed." ;;
esac

if [ "$rc" -eq 0 ] && [ "$status" = "paid" ]; then
  echo "licence: paid${tier:+ (tier: $tier)}${expires:+, expires: $expires} — deploy permitted."
  emit_event "green" "paid"
  exit 0
fi

[ "$rc" -eq 0 ] && [ "$status" != "paid" ] && \
  red "tool-unparseable" "licence_tool exited 0 with status \"$status\" — contract violation (exit 0 means paid), failing closed."

red "$status" "licence status is \"$status\" — no valid paid licence."
