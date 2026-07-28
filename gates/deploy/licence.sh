#!/usr/bin/env bash
# licence.sh — the LICENCE PRECONDITION for the deploy phase (consolidation
# decision 11, amending architecture §17): the paywall sits at FIRST DEPLOY —
# design, prototype, build, gates and preview are all free; you pay when you
# ship. Deploy is the only phase that writes to the outside world, so the
# licence is confirmed HERE, as a named precondition shown BEFORE the phase
# runs — never a red gate discovered mid-deploy.
#
# This is the CHECK, not the store: licence state is config/env only.
# A licence is confirmed when either:
#   - APPBOX_LICENCE_KEY is set to a non-empty value, or
#   - config/app-box.config.json carries "licence": { "key": "<non-empty>" }
#     (APPBOX_CONFIG overrides the config path; default is the repo config).
#
# Usage: licence.sh   (0 licensed / 1 NOT LICENSED — prints what is missing
#                      and how to activate)
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG="${APPBOX_CONFIG:-$repo_root/config/app-box.config.json}"

how_to_activate() {
  cat >&2 <<'EOF'
PRECONDITION NOT MET: licence — deploy writes to the outside world and
requires a confirmed licence (licence-only, flat, never per-seat).
Everything before deploy is free; you pay when you ship.
To activate, either:
  - set APPBOX_LICENCE_KEY=<your-licence-key>, or
  - add "licence": { "key": "<your-licence-key>" } to config/app-box.config.json
EOF
}

# 1. env
if [ -n "${APPBOX_LICENCE_KEY:-}" ]; then
  echo "licence: confirmed via APPBOX_LICENCE_KEY."
  exit 0
fi

# 2. config
if [ -f "$CONFIG" ]; then
  if python3 - "$CONFIG" <<'PY'
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
key = (cfg.get("licence") or {}).get("key")
sys.exit(0 if isinstance(key, str) and key.strip() else 1)
PY
  then
    echo "licence: confirmed via $CONFIG."
    exit 0
  fi
fi

how_to_activate
exit 1
