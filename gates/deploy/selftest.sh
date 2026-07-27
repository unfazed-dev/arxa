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

echo "deploy selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
