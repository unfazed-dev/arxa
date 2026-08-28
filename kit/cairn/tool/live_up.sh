#!/usr/bin/env bash
# Bring up the arxa_kit_cairn "local live" harness (plan D4):
#   1. preflight — self-skip (exit 0, SKIP line) when docker / cargo /
#      openssl or the cairn checkout are absent, so `arxa gate tests` and CI
#      stay green everywhere (atlet's self-skip convention).
#   2. docker Postgres up (idempotent — reuses an already-running container).
#   3. create the live-test tables (idempotent — CREATE TABLE IF NOT EXISTS).
#   4. `cairn init` — real CLI, creates/reconciles the publication, writes
#      cairn.toml + .env under .cairn-live/ (idempotent re-run per its doc).
#   5. append the dev JWT secret + the CRDT column declarations to .env
#      (the server reads CAIRN_COUNTER_COLUMNS / CAIRN_OR_SET_COLUMNS from its
#      environment — cairn-infra write_back.rs). These lines are what the
#      kit's CairnSchemaEmitter.emitServerCrdtEnv generates for a real app;
#      here they are pinned to the live-test tables by hand.
#   6. `cairn dev` — real CLI, backgrounded; waits for /healthz.
#   7. write .cairn-live/live.env (ws URL + two ready-to-use dev JWTs) — the
#      sync-mode integration test reads this file and never shells out.
#
# Safe to re-run: each step no-ops or reconciles rather than erroring.
# First run compiles cairn-cli + cairn-server from scratch (minutes).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./live_env.sh
source ./live_env.sh

echo "== 1/7: preflight =="
missing=""
for tool in docker cargo openssl curl; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  echo "  SKIP  live harness needs:$missing — install it and re-run (not an error)"
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "  SKIP  docker daemon is not running — start it and re-run (not an error)"
  exit 0
fi
if [ ! -f "$CAIRN_REPO_ROOT/Cargo.toml" ]; then
  echo "  SKIP  cairn checkout not found at $CAIRN_REPO_ROOT"
  echo "        (set CAIRN_REPO=/path/to/cairn and re-run — not an error)"
  exit 0
fi
echo "  ✓ docker, cargo, openssl, curl, and $CAIRN_REPO_ROOT"

echo "== 2/7: docker Postgres =="
docker compose -f "$CAIRN_REPO_ROOT/docker/docker-compose.yml" up -d postgres
for i in $(seq 1 60); do
  if docker exec cairn-postgres pg_isready -U cairn -d cairn >/dev/null 2>&1; then
    echo "  postgres ready after ${i}s"
    break
  fi
  sleep 1
done
docker exec cairn-postgres pg_isready -U cairn -d cairn >/dev/null 2>&1 \
  || { echo "postgres did not become ready in 60s"; exit 1; }

echo "== 3/7: live-test tables =="
# REPLICA IDENTITY FULL: without it live DELETEs carry only PK columns and
# tenant-scoped delete fan-out is silently dropped (the server's own boot
# check names this fix verbatim). Dedicated CRDT tables carry only the pk +
# the jsonb payload column — no tenant column (see live_env.sh).
# The pk columns are `uuid`, not `text`: cairn's write-back binds any
# UUID-parsable pk as SqlValue::Uuid (write_back.rs from_scalar), and the
# kit's canonical ids ARE v5 UUIDs — a text column fails the bind with
# "error serializing parameter 0".
docker exec -i cairn-postgres psql -U cairn -d cairn -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS kit_live_counters (
  id uuid primary key,
  value jsonb
);
CREATE TABLE IF NOT EXISTS kit_live_orsets (
  id uuid primary key,
  tags jsonb
);
ALTER TABLE kit_live_counters REPLICA IDENTITY FULL;
ALTER TABLE kit_live_orsets REPLICA IDENTITY FULL;
SQL
echo "  ✓ kit_live_counters + kit_live_orsets present"

mkdir -p "$CAIRN_STATE_DIR"

# Resolve the cairn-cli binary: a fresh-enough debug build wins (cargo run
# re-verifies the whole workspace on every call — minutes on a cold cache);
# build only when the binary is absent.
CAIRN_BIN="$CAIRN_REPO_ROOT/target/debug/cairn"
if [ ! -x "$CAIRN_BIN" ]; then
  echo "  building cairn-cli (first run — minutes)..."
  cargo build --manifest-path "$CAIRN_REPO_ROOT/Cargo.toml" -p cairn-cli
fi

echo "== 4/7: cairn init =="
# cairn-cli's `init`/`dev`/`doctor` resolve cairn.toml/.env against the
# PROCESS cwd (crates/cairn-cli/src/main.rs), so this runs from .cairn-live/.
(cd "$CAIRN_STATE_DIR" && "$CAIRN_BIN" init \
  --db-url "$CAIRN_PG_URL" \
  --tables "$CAIRN_TABLES" \
  --write-tables "$CAIRN_TABLES" \
  --tenant-column "$CAIRN_TENANT_COLUMN" \
  --publication "$CAIRN_PUBLICATION" \
  --slot "$CAIRN_SLOT" \
  --bind "$CAIRN_BIND")
echo "== 5/7: dev JWT secret + CRDT column declarations =="
if ! grep -q '^CAIRN_SUPABASE_JWT_SECRET=' "$CAIRN_STATE_DIR/.env" 2>/dev/null; then
  echo "CAIRN_SUPABASE_JWT_SECRET=$CAIRN_DEV_JWT_SECRET" >> "$CAIRN_STATE_DIR/.env"
fi
# Reconcile (not append): a re-run with changed tables must REPLACE the line.
for kv in "CAIRN_COUNTER_COLUMNS=$CAIRN_COUNTER_COLUMNS" "CAIRN_OR_SET_COLUMNS=$CAIRN_OR_SET_COLUMNS"; do
  key="${kv%%=*}"
  if grep -q "^$key=" "$CAIRN_STATE_DIR/.env" 2>/dev/null; then
    sed -i.bak "s#^$key=.*#$kv#" "$CAIRN_STATE_DIR/.env"
    rm -f "$CAIRN_STATE_DIR/.env.bak"
  else
    echo "$kv" >> "$CAIRN_STATE_DIR/.env"
  fi
done
echo "  ✓ .env: jwt secret + counter[$CAIRN_COUNTER_COLUMNS] or-set[$CAIRN_OR_SET_COLUMNS]"

echo "== 6/7: cairn dev =="
# Since cairn 78fb2c4, `cairn dev` forwards CAIRN_COUNTER_COLUMNS /
# CAIRN_OR_SET_COLUMNS from .env to the cairn-server child itself
# (push_crdt_columns_env in dev.rs) — the step-5 reconcile loop above is the
# single source of truth; no export trick needed here anymore.
if [ -f "$CAIRN_DEV_PID_FILE" ] && kill -0 "$(cat "$CAIRN_DEV_PID_FILE")" 2>/dev/null; then
  echo "  already running (pid $(cat "$CAIRN_DEV_PID_FILE"))"
else
  (cd "$CAIRN_STATE_DIR" && nohup "$CAIRN_BIN" dev \
    > "$CAIRN_DEV_LOG" 2>&1 < /dev/null &
    echo $! > "$CAIRN_DEV_PID_FILE")
  echo "  started (pid $(cat "$CAIRN_DEV_PID_FILE")); waiting for $CAIRN_HEALTH_URL ..."
  ready=""
  for i in $(seq 1 180); do
    if curl -sf -o /dev/null "$CAIRN_HEALTH_URL"; then
      ready=1
      echo "  healthy after ${i}s"
      break
    fi
    sleep 1
  done
  if [ -z "$ready" ]; then
    echo "cairn-server did not become healthy in 180s — see $CAIRN_DEV_LOG"
    exit 1
  fi
fi

echo "== 7/7: live.env for the integration test =="
token_a="$(./mint_jwt.sh user-a)"
token_b="$(./mint_jwt.sh user-b)"
{
  echo "# Written by tool/live_up.sh — read by test/kit/cairn_live_sync_test.dart."
  echo "CAIRN_LIVE_WS_URL=$CAIRN_WS_URL"
  echo "CAIRN_LIVE_HEALTH_URL=$CAIRN_HEALTH_URL"
  echo "CAIRN_LIVE_TOKEN_A=$token_a"
  echo "CAIRN_LIVE_TOKEN_B=$token_b"
} > "$CAIRN_LIVE_ENV_FILE"
echo "  ✓ $CAIRN_LIVE_ENV_FILE"

echo
echo "ws URL:  $CAIRN_WS_URL"
echo "user-a token: $token_a"
echo "user-b token: $token_b"
echo
echo "Run the proof:  flutter test test/kit/cairn_live_sync_test.dart"
echo "Tear down:      tool/live_down.sh   (add --pg to also stop postgres)"
