#!/usr/bin/env bash
# gates/intake/selftest.sh — R5 suite for the intake traceability gate.
# Delegates to the gate's embedded suite (intake.sh --self-test), the single
# source of truth: happy path + negative cases (orphan answer, unanswered
# surface, brief/registry drift, duplicate ids, missing source). Keeping one
# suite prevents the standalone and embedded tests from drifting apart.
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/intake.sh"
bash "$GATE" --self-test
exit $?
