#!/usr/bin/env bash
# gates/native_deps/selftest.sh — R5 suite for the native-deps gate.
#
# Delegates to the gate's embedded suite (native_deps.sh --self-test), which is
# the single source of truth: happy path plus the NEGATIVE cases —
#   * an unmigrated plugin WITH a CocoaPods fallback warns and never reds
#     (brief non-negotiable #1, "red must mean broken"),
#   * an unmigrated plugin with NO fallback FAILS, which is the branch that
#     proves this gate can go red at all,
#   * the two detection strategies disagreeing is surfaced, not guessed away,
#   * an unknown target fails rather than being skipped,
#   * SwiftPM switched off is stated, never a silent clean bill of health.
#
# Keeping one suite prevents the standalone and embedded tests from drifting.
exec bash "$(cd "$(dirname "$0")" && pwd)/native_deps.sh" --self-test
