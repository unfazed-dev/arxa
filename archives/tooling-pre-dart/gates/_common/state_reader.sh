#!/usr/bin/env bash
# gates/_common/state_reader.sh — the canonical pipeline-state reader.
# Every gate sources this; no gate reimplements state parsing (R4).
#
# Usage:
#   source "$(dirname "$0")/../_common/state_reader.sh"
#   state_get phase            # prints a single field
#   state_targets              # prints the targets array, one per line
#   state_set designHash <hex> # writes a scalar field (live state only; the
#                              # tracked seed default.state.json is read-only)
#
# State path is configurable via APPBOX_STATE (default: pipeline/state/run.state.json),
# falling back to pipeline/state/default.state.json when no live run exists.
set -euo pipefail

state_file() {
  if [ -n "${APPBOX_STATE:-}" ] && [ -f "${APPBOX_STATE}" ]; then echo "${APPBOX_STATE}"; return; fi
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  if [ -f "$root/pipeline/state/run.state.json" ]; then echo "$root/pipeline/state/run.state.json"
  else echo "$root/pipeline/state/default.state.json"; fi
}

# state_get <field> — prints the value of a top-level scalar field.
state_get() {
  local field="$1"
  python3 -c '
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
field = sys.argv[2]
if field not in data:
    sys.exit(1)
val = data[field]
if isinstance(val, (list, dict)):
    print(json.dumps(val))
else:
    print(val)
' "$(state_file)" "$field"
}

# state_set <field> <value> — writes a top-level scalar field into the LIVE
# state file. The tracked seed (default.state.json) is read-only: when no live
# run state exists (APPBOX_STATE unset, no run.state.json) this is a no-op
# returning 1, so callers note-and-skip instead of dirtying the seed.
state_set() {
  local field="$1" value="$2" f
  f="$(state_file)"
  case "$f" in
    */default.state.json) return 1 ;;
  esac
  python3 -c '
import json, sys
path, field, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    data = json.load(fh)
data[field] = value
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
' "$f" "$field" "$value"
}

# state_targets — prints the targets array, one per line.
state_targets() {
  python3 -c '
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for t in data.get("targets", []):
    print(t)
' "$(state_file)"
}
