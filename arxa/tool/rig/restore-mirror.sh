#!/usr/bin/env bash
# Restore the studio mirror rig after a reboot or crash — durable variant of
# /tmp/arxa-d68/restore-mirror.sh: reads EVERYTHING from the app keystore
# (~/Library/Application Support/solutions.arxadigital.arxa/cairn-server.env)
# instead of /tmp token files, so it survives reboots.
#
# Brings up: cairn-server (mirror replicator, bearer sync auth, silent push
# tables, RemoteNotifier delegation to the local cairn-pushd) on 127.0.0.1:8190.
# cairn-pushd itself is supervised by the Tauri shell (or start it manually —
# see the rig README beside this script).
set -euo pipefail

KS="$HOME/Library/Application Support/solutions.arxadigital.arxa/cairn-server.env"
LOG=/tmp/cairn-mirror.log
[ -f "$KS" ] || { echo "keystore missing: $KS"; exit 1; }

# Export the keystore (KEY=VALUE lines). Tokens are hex/base64url-safe, so
# shell sourcing is unambiguous; a malformed line fails loudly on its own.
set -a
# shellcheck disable=SC1090
source "$KS"
set +a
export CAIRN_BIND=127.0.0.1:8190

pkill -f 'cargo/bin/cairn-server' 2>/dev/null || true
sleep 1
nohup "$HOME/.cargo/bin/cairn-server" >"$LOG" 2>&1 &
sleep 2
pgrep -fl 'cargo/bin/cairn-server' | head -1
python3 -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8190/healthz',timeout=3).read().decode())"
grep -E 'tables=|sync auth|replicator' "$LOG" | tail -3