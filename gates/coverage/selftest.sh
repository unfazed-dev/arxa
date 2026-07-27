#!/usr/bin/env bash
# gates/coverage/selftest.sh — R5 suite for the coverage gate.
# Delegates to the gate's embedded suite (coverage.sh --self-test), which is the
# single source of truth: happy path + negative cases (4.4, plus the plan-06
# proofs — 6.5 derived form-factor counts, 6.6 no empty .mobile/.tablet,
# 6.8 ceremony absence naming the file, 6.3 unknown target). Keeping one suite
# prevents the standalone and embedded tests from drifting apart.
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/coverage.sh"
bash "$GATE" --self-test
exit $?
