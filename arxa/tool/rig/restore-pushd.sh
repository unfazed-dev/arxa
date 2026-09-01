#!/usr/bin/env bash
# Restore cairn-pushd from its durable keystore (pushd.env) — the same
# discipline as restore-mirror.sh. Aligning the RUNNING daemon to the file
# matters: the mirror's RemoteNotifier derives its delegation key from this
# same file, so a daemon started with different (e.g. /tmp-era) keys 401s
# every send + receipts poll.
#
# Token re-registration: phones re-register on their next sync session after
# a pushd restart (pushd.rs PUSH stream) — no manual step.
set -euo pipefail

APPD="$HOME/Library/Application Support/solutions.arxadigital.arxa"
KS="$APPD/pushd.env"
LOG=/tmp/cairn-pushd.log
[ -f "$KS" ] || { echo "keystore missing: $KS"; exit 1; }

while IFS='=' read -r k v; do
  case "$k" in ''|'#'*) continue ;; esac
  [ -n "$v" ] && export "$k=$v"
done < "$KS"

pkill -f 'cargo/bin/cairn-pushd' 2>/dev/null || true
sleep 1
nohup "$HOME/.cargo/bin/cairn-pushd" >"$LOG" 2>&1 &
sleep 2
pgrep -fl 'cargo/bin/cairn-pushd' | head -1
python3 -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8090/v1/healthz',timeout=3).read().decode())"
tail -3 "$LOG" | cut -c1-140