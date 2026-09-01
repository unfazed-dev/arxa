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

# Export the keystore KEY=VALUE lines WITHOUT sourcing: values may contain
# shell metacharacters (CAIRN_PUSH_TABLES carries an unquoted ';'), which
# `source` would execute. Split on the FIRST '=' and export the pair whole.
while IFS='=' read -r k v; do
  case "$k" in ''|'#'*) continue ;; esac
  [ -n "$v" ] && export "$k=$v"
done < "$KS"
export CAIRN_BIND=127.0.0.1:8190

# Push delegation (RemoteNotifier -> cairn-pushd) is the rig posture: the
# keystore does not carry it, so default the URL and derive the KEY from the
# pushd keystore's tenant:key list (first entry's secret). Without this the
# server boots the embedded PushRouter with NO rail credentials — doorbells
# would silently fail.
export CAIRN_PUSH_REMOTE_URL="${CAIRN_PUSH_REMOTE_URL:-http://127.0.0.1:8090}"
if [ -z "${CAIRN_PUSH_REMOTE_KEY:-}" ]; then
  PD="$HOME/Library/Application Support/solutions.arxadigital.arxa/pushd.env"
  if [ -f "$PD" ]; then
    KEYS=$(grep '^CAIRN_PUSHD_API_KEYS=' "$PD" | cut -d= -f2-)
    FIRST=${KEYS%%,*}
    export CAIRN_PUSH_REMOTE_KEY=${FIRST#*:}
  fi
fi
[ -n "${CAIRN_PUSH_REMOTE_KEY:-}" ] || { echo 'no CAIRN_PUSH_REMOTE_KEY (pushd.env missing?) — doorbells will not fire'; }

pkill -f 'cargo/bin/cairn-server' 2>/dev/null || true
sleep 1
nohup "$HOME/.cargo/bin/cairn-server" >"$LOG" 2>&1 &
sleep 2
pgrep -fl 'cargo/bin/cairn-server' | head -1
python3 -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8190/healthz',timeout=3).read().decode())"
grep -E 'tables=|sync auth|replicator' "$LOG" | tail -3