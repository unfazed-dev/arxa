#!/usr/bin/env bash
# gates/_common/sarif.sh — SARIF emitter. One machine contract for the GUI,
# the companion and a CI log (R4 / plan 04.2). Human-readable output stays in
# each gate; SARIF is the transport.
#
# Usage:
#   source "$(dirname "$0")/../_common/sarif.sh"
#   sarif_result <rule-id> <level:error|warning|note> <file> <message>
#   sarif_flush > results.sarif
SARIF_RESULTS_FILE="${SARIF_RESULTS_FILE:-$(mktemp)}"
: > "$SARIF_RESULTS_FILE"

_sarif_escape() {
  # minimal JSON string escaping
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' <<<"$1"
}

sarif_result() {
  local rule_id="$1" level="$2" file="$3" message="$4"
  local f m
  f="$(_sarif_escape "$file")"
  m="$(_sarif_escape "$message")"
  printf '{"ruleId":"%s","level":"%s","locations":[{"physicalLocation":{"artifactLocation":{"uri":"%s"}}}],"message":{"text":"%s"}}\n' \
    "$rule_id" "$level" "$f" "$m" >> "$SARIF_RESULTS_FILE"
}

sarif_flush() {
  local rules=""
  python3 -c '
import json, sys
results = []
with open(sys.argv[1]) as fh:
    for line in fh:
        line = line.strip()
        if line:
            results.append(json.loads(line))
doc = {
    "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
    "version": "2.1.0",
    "runs": [{"tool": {"driver": {"name": "appbox-gates", "informationUri": "https://example.invalid"}}, "results": results}],
}
print(json.dumps(doc, indent=2))
' "$SARIF_RESULTS_FILE"
}
