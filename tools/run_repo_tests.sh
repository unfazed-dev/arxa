#!/usr/bin/env bash
# tools/run_repo_tests.sh — the repo's test entry point (plan 02.7).
# A convention violation cannot merge. Gate suites register here as they land
# (plan 04 wires gates/run_all.sh in below).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
rc=0

echo "== lint conventions =="
bash tools/lint_conventions.sh || rc=1

echo "== lint selftest (R5) =="
bash tools/lint_conventions.selftest.sh || rc=1

# Gate suites register below as they land (plan 04+):
# bash gates/run_all.sh || rc=1

exit "$rc"
