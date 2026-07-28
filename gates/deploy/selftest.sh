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

# Licensed by default for all cases below; the licence-negative cases clear it.
export APPBOX_LICENCE_KEY="selftest-licence-key"
# A config WITHOUT a licence, to isolate the env-based path in negatives.
NOLIC_CONFIG="$T/nolic.config.json"; printf '%s' '{"version":"1.0.0"}' > "$NOLIC_CONFIG"

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
# a gate; a paywall discovered mid-deploy is worse.
mkstate "$OK"
o="$(env -u APPBOX_LICENCE_KEY APPBOX_CONFIG="$NOLIC_CONFIG" APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"
chk "$?" 1 "negative: unlicensed deploy halts"
need "$o" "PRECONDITION NOT MET: licence" "negative names the licence precondition"
need "$o" "APPBOX_LICENCE_KEY" "negative says how to activate"
need "$o" "HALTED" "negative halts the deploy"

# ---- HAPPY: licence confirmed via config (not env) ---------------------------
# POSITIVE: licence.key in config/app-box.config.json also satisfies the
# precondition -> gate proceeds to its normal checks and passes.
LIC_CONFIG="$T/lic.config.json"; printf '%s' '{"version":"1.0.0","licence":{"key":"flat-licence-key"}}' > "$LIC_CONFIG"
mkstate "$OK"
o="$(env -u APPBOX_LICENCE_KEY APPBOX_CONFIG="$LIC_CONFIG" APPBOX_STATE="$T/state.json" bash "$GATE" 2>&1)"
chk "$?" 0 "happy: licensed via config proceeds"
need "$o" "deploy: PASS" "config-licensed deploy passes"

echo "deploy selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
