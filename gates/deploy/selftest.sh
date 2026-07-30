#!/usr/bin/env bash
# gates/deploy/selftest.sh — R5 suite for the deploy gate.
# Happy path AND >=1 negative case. Plants a defect and asserts the gate exits 1
# and names the missing confirmation. Uses APPBOX_STATE to point the gate at a
# tmp state file (the _common state_reader honours APPBOX_STATE).
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/deploy.sh"
pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkstate(){ printf '%s' "$1" > "$T/state.json"; }

# The §17 licence assertion (licence_assert.sh) runs FIRST and fails closed;
# this suite exercises the gate's own checks, so it dogfoods through the
# documented dev bypass (a paid licence_tool fixture lives in
# licence_assert.selftest.sh). The licence cases below clear it and drive a
# fixture licence_tool via APPBOX_APPBOXD_DIR instead.
export APPBOX_DEV_LICENCE=1
# Keep the suite's memory events out of the real pipeline state.
export APPBOX_MEMORY_EVENTS="$T/memory/events.jsonl"
# A fixture appboxd whose licence_tool.dart stub plays the tool contract
# ({status,tier,expires} JSON on stdout, exit 0 for paid / 1 otherwise).
STUBD="$T/appboxd"; mkdir -p "$STUBD/bin"
mkstub(){ cat > "$STUBD/bin/licence_tool.dart" <<DART
import 'dart:io';
void main(List<String> args) {
  stdout.writeln('{"status":"$1","tier":"$1-tier","expires":"2027-01-01"}');
  exit($2);
}
DART
}

OK='{"phase":"deploy","targets":["macos"],"approvalTokens":{"deploy":{"version":"1.2.3","account":"totem-labs"}}}'

# ---- HAPPY: target + version + account all confirmed ------------------------
mkstate "$OK"
o="$(APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"; chk "$?" 0 "happy: all three confirmed"
need "$o" "deploy: PASS" "happy prints PASS"

# ---- NEGATIVE: the releasing account is not confirmed -----------------------
# NEGATIVE: deploy.account is unset -> exit 1, naming deploy.account.
mkstate '{"phase":"deploy","targets":["macos"],"approvalTokens":{"deploy":{"version":"1.2.3"}}}'
o="$(APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"; chk "$?" 1 "negative: missing account fails"
need "$o" "deploy.account" "negative names the missing confirmation"

# ---- NEGATIVE: the release version is not confirmed --------------------------
# NEGATIVE: deploy.version is unset -> exit 1, naming deploy.version.
# (Done-when #3: prove the negative for EACH of target / version / account.)
mkstate '{"phase":"deploy","targets":["macos"],"approvalTokens":{"deploy":{"account":"totem-labs"}}}'
o="$(APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"; chk "$?" 1 "negative: missing version fails"
need "$o" "deploy.version" "negative names the missing version"

# ---- NEGATIVE: no build target set ------------------------------------------
# NEGATIVE: state.targets is empty -> exit 1, naming the target.
mkstate '{"phase":"deploy","targets":[],"approvalTokens":{"deploy":{"version":"1.2.3","account":"totem-labs"}}}'
o="$(APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"; chk "$?" 1 "negative: no target fails"
need "$o" "target" "negative names the missing target"

# ---- NEGATIVE: NO LICENCE — the precondition halts the deploy ---------------
# NEGATIVE (decision 11, amends §17): unlicensed -> exit 1 BEFORE the gate,
# naming what is missing and how to activate. A gate that cannot fail is not
# a gate; a paywall discovered mid-deploy is worse. licence_assert.sh delegates
# to appboxd's licence_tool — the fixture reports "none".
mkstate "$OK"
mkstub none 1
o="$(env -u APPBOX_DEV_LICENCE APPBOX_APPBOXD_DIR="$STUBD" APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"
chk "$?" 1 "negative: unlicensed deploy halts"
need "$o" "PRECONDITION NOT MET: licence" "negative names the licence precondition"
need "$o" "licence_tool" "negative says how to activate"
need "$o" "HALTED" "negative halts the deploy"

# ---- HAPPY: licence confirmed paid via licence_tool ---------------------------
# POSITIVE: a paid verdict from appboxd's licence_tool satisfies the
# precondition -> gate proceeds to its normal checks and passes. This drives
# the delegated path directly (no dev bypass).
mkstate "$OK"
mkstub paid 0
o="$(env -u APPBOX_DEV_LICENCE APPBOX_APPBOXD_DIR="$STUBD" APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"
chk "$?" 0 "happy: paid licence proceeds"
need "$o" "deploy: PASS" "paid deploy passes"

echo "deploy selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
