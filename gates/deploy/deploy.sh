#!/usr/bin/env bash
# deploy.sh — the DEPLOY gate (plan 11): asserts the three deployment
# prerequisites are confirmed in pipeline state before a target is shipped —
# the build target, the version, and the releasing account. Plan 11 owns the
# full release mechanics; this gate only owns the confirmation contract, so the
# pipeline cannot ship a build whose target/version/account is unset.
#
# Reads pipeline state through gates/_common/state_reader.sh (APPBOX_STATE
# selects the state file; defaults to pipeline/state/run.state.json then
# default.state.json). Findings route through gates/_common/sarif.sh (4.2).
#
# Usage: deploy.sh   (0 pass / 1 FAIL / 2 env)
set -uo pipefail

GATE_COMMON="$(cd "$(dirname "$0")/../_common" && pwd)"
# shellcheck source=../_common/state_reader.sh
source "$GATE_COMMON/state_reader.sh"
# shellcheck source=../_common/sarif.sh
source "$GATE_COMMON/sarif.sh"
# state_reader.sh enables `set -e`; this gate reports failures via exit codes,
# not by aborting, so restore the non-errexit discipline this gate was written for.
set +e

STATE="$(state_file)"
[ -f "$STATE" ] || { echo "FAIL: deploy: no pipeline state at $STATE — a gate that cannot find its input never passes quietly" >&2; sarif_result "deploy" "error" "$STATE" "no pipeline state"; exit 1; }

F=0
fail(){ echo "FAIL: $1" >&2; F=$((F+1)); sarif_result "deploy" "error" "$STATE" "$1"; }
ok(){ echo "  ✓ $1"; }

# target + version + account, read from state in one pass. approvalTokens.deploy
# carries the human confirmations (plan 11 shape); targets is the top-level list.
pyout="$(python3 - "$STATE" 2>&1 <<'PY'
import json,sys
state=json.load(open(sys.argv[1]))
def bad(m): print(f"FAIL: deploy: {m}"); return 1
targets=state.get("targets") or []
toks=state.get("approvalTokens") or {}
deploy=toks.get("deploy") or {} if isinstance(toks,dict) else {}
f=0
if not isinstance(targets,list) or not targets:
    bad("no build target in state.targets — set the target before deploying"); f+=1
else:
    print(f"  ✓ target: {', '.join(targets)}")
if not deploy.get("version"):
    bad("deploy.version is not confirmed in approvalTokens.deploy — set the release version"); f+=1
else:
    print(f"  ✓ version: {deploy.get('version')}")
if not deploy.get("account"):
    bad("deploy.account is not confirmed in approvalTokens.deploy — set the releasing account"); f+=1
else:
    print(f"  ✓ account: {deploy.get('account')}")
sys.exit(1 if f else 0)
PY
)"
rc=$?
printf '%s\n' "$pyout"
fails="$(printf '%s\n' "$pyout" | grep '^FAIL:' || true)"
[ -n "$fails" ] && printf '%s\n' "$fails" | while IFS= read -r fl; do sarif_result "deploy" "error" "$STATE" "$fl"; done
[ "$rc" -ne 0 ] && F=$((F+1))

[ "$F" -gt 0 ] && { echo "deploy: FAIL ($F check(s))" >&2; exit 1; }
echo "deploy: PASS — target, version and account confirmed."
exit 0
