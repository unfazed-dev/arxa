#!/usr/bin/env bash
# gates/deploy/licence_assert.selftest.sh — R5 suite for the §17 licence
# assertion (licence_assert.sh). Happy AND negative paths; the negatives are
# the point — a paywall that cannot fail closed is the vacuous-PASS trap
# (dogfood honest-bar: green over broken).
#
# Uses a FIXTURE appboxd dir (APPBOX_APPBOXD_DIR) whose bin/licence_tool.dart
# stub plays the tool contract ({status,tier,expires} JSON on stdout, exit 0
# for paid / 1 otherwise), and a FIXTURE memory event log
# (APPBOX_MEMORY_EVENTS) — every case asserts the gate_run event was appended.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ASSERT="$HERE/licence_assert.sh"
GATE="$HERE/deploy.sh"
pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
STUBD="$T/appboxd"; mkdir -p "$STUBD/bin"
EVENTS="$T/state/memory/events.jsonl"

# mkstub <status> <exit-code> — a licence_tool.dart honouring the contract.
mkstub(){ cat > "$STUBD/bin/licence_tool.dart" <<DART
import 'dart:io';
void main(List<String> args) {
  stdout.writeln('{"status":"$1","tier":"$1-tier","expires":"2027-01-01"}');
  exit($2);
}
DART
}

# run_assert — run the assertion against the fixture with a clean environment.
run_assert(){ env -u APPBOX_DEV_LICENCE APPBOX_APPBOXD_DIR="$STUBD" APPBOX_MEMORY_EVENTS="$EVENTS" bash "$ASSERT" 2>&1; }

# last_event_has <fragment> <label> — assert the appended memory event.
last_event_has(){
  [ -f "$EVENTS" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: no memory event file — $2"; return; }
  need "$(tail -1 "$EVENTS")" "$1" "$2"
}

# ---- HAPPY: paid licence -> green -------------------------------------------
mkstub paid 0; rm -f "$EVENTS"
o="$(run_assert)"; chk "$?" 0 "paid -> green"
need "$o" "licence: paid" "paid prints the verdict"
last_event_has '"verdict":"green"' "paid appends a green event"
last_event_has '"licence_status":"paid"' "paid event carries the status"

# ---- NEGATIVE: free tier -> red with a purchase message ---------------------
mkstub free 1; rm -f "$EVENTS"
o="$(run_assert)"; chk "$?" 1 "free -> red"
need "$o" "PRECONDITION NOT MET: licence" "free names the paywall"
need "$o" '"free"' "free names the status"
need "$o" "pay when you ship" "free prints the purchase message"
last_event_has '"verdict":"red"' "free appends a red event"
last_event_has '"licence_status":"free"' "free event carries the status"

# ---- NEGATIVE: no licence at all -> red --------------------------------------
mkstub none 1; rm -f "$EVENTS"
o="$(run_assert)"; chk "$?" 1 "none -> red"
need "$o" '"none"' "none names the status"
last_event_has '"verdict":"red"' "none appends a red event"
last_event_has '"licence_status":"none"' "none event carries the status"

# ---- NEGATIVE: licence_tool missing -> red, fail CLOSED ----------------------
rm -f "$STUBD/bin/licence_tool.dart" "$EVENTS"
o="$(run_assert)"; chk "$?" 1 "tool-missing -> red"
need "$o" "licence_tool not found" "tool-missing names the reason"
need "$o" "failing closed" "tool-missing fails closed"
last_event_has '"licence_status":"tool-missing"' "tool-missing event carries the status"

# ---- NEGATIVE: unparseable tool output -> red, fail CLOSED --------------------
cat > "$STUBD/bin/licence_tool.dart" <<'DART'
void main() { print("not json at all"); }
DART
rm -f "$EVENTS"
o="$(run_assert)"; chk "$?" 1 "unparseable -> red"
need "$o" "unparseable" "unparseable names the reason"
last_event_has '"licence_status":"tool-unparseable"' "unparseable event carries the status"

# ---- DEV BYPASS: APPBOX_DEV_LICENCE=1 -> green WITH loud warning -------------
# (points at a nonexistent appboxd — the bypass must not need the tool at all)
rm -f "$EVENTS"
o="$(APPBOX_DEV_LICENCE=1 APPBOX_APPBOXD_DIR="$T/no-such-dir" APPBOX_MEMORY_EVENTS="$EVENTS" bash "$ASSERT" 2>&1)"
chk "$?" 0 "dev bypass -> green"
need "$o" "WARNING" "dev bypass warns loudly"
need "$o" "BYPASSED" "dev bypass says what happened"
last_event_has '"verdict":"green"' "dev bypass appends a green event"
last_event_has '"licence_status":"dev-bypass"' "dev bypass event carries the status"

# ---- E2E sequencing: the assertion runs FIRST in the deploy gate -------------
# OK pipeline state; the fixture licence_tool decides the §17 assertion (the
# only licence check in the gate — the legacy licence.sh/APPBOX_LICENCE_KEY
# path is retired), so these two runs hinge on the assertion alone.
OK='{"phase":"deploy","targets":["macos"],"approvalTokens":{"deploy":{"version":"1.2.3","account":"totem-labs"}}}'
printf '%s' "$OK" > "$T/state.json"

mkstub paid 0
o="$(env -u APPBOX_DEV_LICENCE APPBOX_APPBOXD_DIR="$STUBD" APPBOX_MEMORY_EVENTS="$EVENTS" \
     APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"
chk "$?" 0 "e2e: paid licence -> gate proceeds and passes"
need "$o" "deploy: PASS" "e2e paid reaches the gate's own checks"

mkstub free 1
o="$(env -u APPBOX_DEV_LICENCE APPBOX_APPBOXD_DIR="$STUBD" APPBOX_MEMORY_EVENTS="$EVENTS" \
     APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"
chk "$?" 1 "e2e: free licence -> gate halts"
need "$o" "§17 licence assertion failed" "e2e free halts on the FIRST check"
case "$o" in *"deploy: PASS"*) failc=$((failc+1)); echo "  FAIL: gate passed with a free licence";; *) pass=$((pass+1));; esac

echo "licence_assert selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
