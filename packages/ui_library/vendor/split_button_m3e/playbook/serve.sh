#!/usr/bin/env sh
# Serve this package's playbook in the hosted Plan UI via a local bridge.
# Self-contained — no arguments. Run from anywhere:
#   sh packages/<pkg>/playbook/serve.sh
# or:
#   cd packages/<pkg>/playbook && ./serve.sh
#
# One-time per machine (puts `agent-native` on PATH):
#   npm install -g @agent-native/core
# If the global bin is missing, this falls back to npx (slower first run).
#
# Stop the bridge with Ctrl-C. macOS: Chrome/Chromium preferred over Safari
# (Safari can block the hosted HTTPS page from fetching the HTTP localhost bridge).
set -e
dir="$(cd "$(dirname "$0")" && pwd)"
if command -v agent-native >/dev/null 2>&1; then
  exec agent-native plan local serve --dir "$dir" --kind plan --open
else
  echo "agent-native not on PATH — using npx. Run 'npm install -g @agent-native/core' to skip this." >&2
  exec npx -y @agent-native/core@latest plan local serve --dir "$dir" --kind plan --open
fi
