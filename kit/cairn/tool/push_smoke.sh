#!/usr/bin/env bash
# kit/cairn/tool/push_smoke.sh — Phase 5d real-rail FCM push smoke for
# arxa_kit_cairn. Mirrors cairn's atlet pilot (apps/atlet/flutter/tool/
# push_smoke.sh, ADR-0037) with the kit's operator-gated self-skip convention:
# exits 0 with a SKIP line whenever an operator-owned input is absent, so the
# script is honest on a secrets-less box and `arxa gate tests` stays green.
#
# What it proves, end to end on the REAL FCM rail:
#   showcase app (device) initializes Firebase → permission → FCM token → the
#   kit's notifications seam → ArxaKitCairnBackend (sync mode, push: true)
#   attaches the push bridge → the token lands in the server's push registry →
#   first sync → pauseSync (doorbells target OFFLINE accounts) →
#   PUSH_SMOKE_READY → this script inserts a row → cairn-server replicates it
#   → doorbell → FCM HTTP v1 send → the device's foreground onMessage prints
#   PUSH_SMOKE_RECEIVED. Server side asserted via /metrics
#   (cairn_push_sent_total must move); device side via the marker grep.
#
# Device legs: ANDROID EMULATOR is the automated path (FCM fully works there,
# including data messages to the foregrounded app). iOS is physical-device
# only — the iOS simulator cannot receive real FCM pushes.
#
# Usage (from anywhere):
#   kit/cairn/tool/push_smoke.sh                          # android leg
#   PUSH_SMOKE_DEVICE=ios PUSH_SMOKE_DEVICE_ID=<id> \
#     CAIRN_SYNC_URL=ws://<mac-LAN-IP>:8830/sync \
#     kit/cairn/tool/push_smoke.sh                        # iOS device leg
#
# Operator-owned env (NEVER committed):
#   CAIRN_FCM_CREDENTIALS_JSON  FCM service-account JSON (raw) or a file path
# Optional: CAIRN_REPO (cairn checkout path), CAIRN_SYNC_URL (device→server
#   override), PUSH_SMOKE_PORT, PUSH_SMOKE_SLOT, PUSH_SMOKE_PUB,
#   PUSH_SMOKE_TABLE, PUSH_SMOKE_USER.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_DIR="$SCRIPT_DIR/.."
APP_DIR="$KIT_DIR/../showcase_app"
# Same resolution as tool/live_env.sh: $CAIRN_REPO wins, else the sibling
# checkout layout (arxa at <dev>/totem_labs/arxa, cairn at <dev>/cairn).
CAIRN_REPO_ROOT="${CAIRN_REPO:-$(cd "$SCRIPT_DIR/../../../../.." 2>/dev/null && pwd)/cairn}"

GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'
RESET=$'\033[0m'

SLOT="${PUSH_SMOKE_SLOT:-arxa_kit_push_smoke_slot}"
PUB="${PUSH_SMOKE_PUB:-arxa_kit_push_smoke_pub}"
TABLE="${PUSH_SMOKE_TABLE:-push_smoke_pings}"
SMOKE_USER="${PUSH_SMOKE_USER:-push-smoke-user}"
# 8830 — the kit's collision-avoidance convention (live_env.sh): clear of
# cairn's zero-setup default (8800), the SDK integration test (8801), the old
# todo fixture (8810), the kit's own live harness (8820), and atlet's push
# smoke (8080).
PORT="${PUSH_SMOKE_PORT:-8830}"
SERVER_LOG=/tmp/arxa-kit-push-smoke-server.log
APP_LOG=/tmp/arxa-kit-push-smoke-app.log
PG_CONTAINER=cairn-postgres
APP_PACKAGE=com.arxakit.arxa_kit_showcase_app
SERVER_PID=""
APP_PID=""

skip() { printf "  ${YELLOW}SKIP${RESET}  %s\n" "$1"; exit 0; }

cleanup() {
  if [ -n "$APP_PID" ]; then kill "$APP_PID" 2>/dev/null; fi
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
  # Best-effort slot drop — a leaked slot only pins WAL in the throwaway PG.
  docker exec "$PG_CONTAINER" psql -U cairn -d cairn -qc \
    "SELECT pg_drop_replication_slot('$SLOT') FROM pg_replication_slots WHERE slot_name='$SLOT';" \
    >/dev/null 2>&1
}
trap cleanup EXIT

# ---- 1. operator-owned inputs (self-skip) -----------------------------------
[ -n "${CAIRN_FCM_CREDENTIALS_JSON:-}" ] || skip "CAIRN_FCM_CREDENTIALS_JSON not set (FCM service-account JSON, raw or a file path)"
command -v flutter >/dev/null 2>&1       || skip "flutter not on PATH"
command -v cargo   >/dev/null 2>&1       || skip "cargo not on PATH"
command -v openssl >/dev/null 2>&1       || skip "openssl not on PATH (mints the smoke JWT)"
command -v docker  >/dev/null 2>&1       || skip "docker not on PATH"
docker info >/dev/null 2>&1              || skip "docker daemon is not running"
[ -f "$CAIRN_REPO_ROOT/Cargo.toml" ]     || skip "cairn checkout not found at $CAIRN_REPO_ROOT (set CAIRN_REPO=/path/to/cairn)"

# FCM creds: file path or raw JSON (the server parses raw JSON).
FCM_JSON="$CAIRN_FCM_CREDENTIALS_JSON"
if [ -f "$FCM_JSON" ]; then FCM_JSON="$(cat "$FCM_JSON")"; fi
case "$FCM_JSON" in *project_id*) ;; *) skip "CAIRN_FCM_CREDENTIALS_JSON is neither a readable file nor service-account JSON";; esac

# ---- 2. device leg ----------------------------------------------------------
DEVICE_MODE="${PUSH_SMOKE_DEVICE:-android}"
case "$DEVICE_MODE" in
  android)
    [ -f "$APP_DIR/android/app/google-services.json" ] \
      || skip "kit/showcase_app/android/app/google-services.json absent (drop the Firebase config there — gitignored)"
    ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
    [ -x "$ADB" ] || skip "adb not found (set ANDROID_HOME or install Android SDK)"
    # Here-string, never a pipe: see atlet's SIGPIPE note in sdk-e2e.sh.
    if grep -q '^emulator-[0-9]*[[:space:]]*device' <<< "$("$ADB" devices 2>/dev/null || true)"; then
      DEVICE_ID="$(grep '^emulator-[0-9]*[[:space:]]*device' <<< "$("$ADB" devices 2>/dev/null)" | head -1 | cut -f1)"
    else
      skip "no booted Android emulator (flutter emulators / avdmanager, keep the screen unlocked)"
    fi
    BIND=127.0.0.1                        # 10.0.2.2 (emulator) → host loopback
    SYNC_URL="${CAIRN_SYNC_URL:-ws://10.0.2.2:$PORT/sync}"
    FLUTTER_TEST_EXTRA_ARGS=""
    # FCM data messages reach the test's onMessage only while the app is
    # FOREGROUNDED — anything else holding the screen silently starves the
    # smoke. .MainActivity is singleTop, so this is a no-restart focus
    # restore for an already-running test.
    keep_foreground() {
      case "$("$ADB" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus)" in
        *$APP_PACKAGE*) ;;
        *) "$ADB" shell am start -n "$APP_PACKAGE/.MainActivity" >/dev/null 2>&1 || true ;;
      esac
    }
    # A failed `flutter test` UNINSTALLS the app when it exits, so a grant
    # made earlier has no package to attach to on the next run — the test
    # then hangs in requestPermission()'s untapped dialog. Install the
    # previously built APK first (if any) so the POST_NOTIFICATIONS grant
    # lands; flutter test reinstalls over it, preserving both. First-ever
    # run on a clean box: no APK yet — tap Allow once, then it persists.
    prep_device() {
      local apk="$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
      [ -f "$apk" ] && "$ADB" install -t "$apk" >/dev/null 2>&1 || true
      "$ADB" shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
    }
    ;;
  ios)
    [ -f "$APP_DIR/ios/Runner/GoogleService-Info.plist" ] \
      || skip "kit/showcase_app/ios/Runner/GoogleService-Info.plist absent (gitignored)"
    [ -n "${PUSH_SMOKE_DEVICE_ID:-}" ]   || skip "ios mode needs PUSH_SMOKE_DEVICE_ID=<physical device id> (flutter devices); the simulator cannot receive real FCM"
    [ -n "${CAIRN_SYNC_URL:-}" ]         || skip "ios mode needs CAIRN_SYNC_URL=ws://<mac-LAN-IP>:$PORT/sync (a device cannot use host loopback)"
    DEVICE_ID="$PUSH_SMOKE_DEVICE_ID"
    BIND=0.0.0.0                          # reachable from the LAN
    SYNC_URL="$CAIRN_SYNC_URL"
    # Android-only helpers no-op'd: on iOS the operator keeps the screen
    # unlocked/awake and taps Allow on the first permission prompt.
    prep_device() { :; }
    keep_foreground() { :; }
    FLUTTER_TEST_EXTRA_ARGS="${PUSH_SMOKE_PUBLISH_PORT:+--publish-port $PUSH_SMOKE_PUBLISH_PORT}"
    ;;
  *) skip "PUSH_SMOKE_DEVICE must be 'android' or 'ios' (got '$DEVICE_MODE')";;
esac

# ---- 3. local docker PG (cairn repo's own e2e stack, port 5433) -------------
if ! docker exec "$PG_CONTAINER" pg_isready -U cairn -d cairn >/dev/null 2>&1; then
  printf "  starting docker PG (cairn's docker/docker-compose.yml)…\n"
  docker compose -f "$CAIRN_REPO_ROOT/docker/docker-compose.yml" up -d postgres >/dev/null 2>&1 \
    || skip "failed to start the docker PG"
fi
for _ in $(seq 1 60); do
  docker exec "$PG_CONTAINER" pg_isready -U cairn -d cairn >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$PG_CONTAINER" pg_isready -U cairn -d cairn >/dev/null 2>&1 \
  || skip "docker PG never became ready"

psql_exec() { docker exec "$PG_CONTAINER" psql -U cairn -d cairn -qAt -c "$1"; }

# Throwaway schema. `id uuid`, not text: cairn's write-back binds any
# UUID-parsable pk as SqlValue::Uuid (write_back.rs from_scalar — the 5c
# live-harness finding). REPLICA IDENTITY FULL per the server's own boot
# check. Dedicated publication + slot so the smoke never fights the kit's
# live harness or atlet for a slot.
psql_exec "DROP PUBLICATION IF EXISTS $PUB;" >/dev/null
psql_exec "DROP TABLE IF EXISTS $TABLE;" >/dev/null
psql_exec "CREATE TABLE $TABLE (
  id uuid PRIMARY KEY,
  user_id text NOT NULL,
  note text);" >/dev/null \
  || { printf "  ${RED}FAIL${RESET}  could not create $TABLE\n"; exit 1; }
psql_exec "ALTER TABLE $TABLE REPLICA IDENTITY FULL;" >/dev/null
psql_exec "CREATE PUBLICATION $PUB FOR TABLE $TABLE;" >/dev/null
psql_exec "SELECT pg_drop_replication_slot('$SLOT') FROM pg_replication_slots WHERE slot_name='$SLOT';" >/dev/null
# The token registry persists in the docker volume across runs, and every
# flutter-test install mints a FRESH FCM token (app data wiped per install) —
# stale rows otherwise accumulate and eat send quota (atlet's lesson; each is
# pruned on first UNREGISTERED, but start each run clean regardless). The
# table exists only after a push-enabled server booted once — hence || true.
psql_exec "TRUNCATE cairn_push_tokens;" >/dev/null 2>&1 || true

# ---- 4. cairn-server (real PG replicator + FCM rail + doorbell table) -------
# Started DIRECTLY (cargo run -p cairn-server), not via `cairn dev`: the CLI's
# explicit env whitelist (cairn-cli config.rs server_env) drops vars it does
# not know, and the smoke would rather state its full env than depend on
# Command-env inheritance. The subshell cd also makes the workspace resolution
# independent of the caller's cwd.
#
# The JWT secret is the kit live harness's dev secret, read out of
# tool/live_env.sh in a subshell (its `set -euo pipefail` stays in there) so
# this script and tool/mint_jwt.sh can never drift apart.
JWT_SECRET="$(source "$SCRIPT_DIR/live_env.sh" >/dev/null 2>&1; printf '%s' "${CAIRN_DEV_JWT_SECRET:-}")"
[ -n "$JWT_SECRET" ] || skip "could not read CAIRN_DEV_JWT_SECRET from tool/live_env.sh"

printf "  starting cairn-server (cargo run, log: $SERVER_LOG)…\n"
(
  cd "$CAIRN_REPO_ROOT" || exit 1
  CAIRN_BIND="$BIND:$PORT" \
  CAIRN_REPLICATOR=pg \
  CAIRN_PG_URL="postgresql://cairn:cairn@localhost:5433/cairn" \
  CAIRN_PG_PUBLICATION="$PUB" \
  CAIRN_PG_SLOT="$SLOT" \
  CAIRN_SYNC_AUTH=supabase-jwt \
  CAIRN_SUPABASE_JWT_SECRET="$JWT_SECRET" \
  `# CAIRN_TENANT_COLUMN=user_id is REQUIRED (atlet root-caused 2026-08-27):` \
  `# the doorbell's fully-offline fallback (fanout.rs — the killed-app case,` \
  `# which pauseSync models) reads the tenant from the ROW's tenant column;` \
  `# with it unset that path enqueues NOTHING and cairn_push_sent_total never` \
  `# moves. And it must never be merely UNSET: the clap default is "org_id",` \
  `# a column no smoke table has — every predicate 42703s.` \
  CAIRN_TENANT_COLUMN=user_id \
  CAIRN_WRITE_TABLES="$TABLE" \
  CAIRN_PUSH_TABLES="$TABLE" \
  CAIRN_FCM_CREDENTIALS_JSON="$FCM_JSON" \
    cargo run -q -p cairn-server >"$SERVER_LOG" 2>&1
) &
SERVER_PID=$!

for _ in $(seq 1 90); do
  # curl only here; failures are the normal "not up yet".
  if curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    printf "  ${RED}FAIL${RESET}  cairn-server exited early (log: $SERVER_LOG)\n"
    tail -5 "$SERVER_LOG"
    exit 1
  fi
  sleep 1
done
curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 \
  || { printf "  ${RED}FAIL${RESET}  cairn-server never became healthy (log: $SERVER_LOG)\n"; exit 1; }

sent_before="$(curl -s "http://127.0.0.1:$PORT/metrics" | awk '/^cairn_push_sent_total/ {print $2; exit}')"
sent_before="${sent_before:-0}"

# ---- 5. device leg: register token, go offline, listen ----------------------
# The JWT's `sub` is both account and tenant id (auth.rs tenant-from-sub) and
# must match the trigger row's user_id below — hence the single SMOKE_USER.
SMOKE_TOKEN="$("$SCRIPT_DIR/mint_jwt.sh" "$SMOKE_USER")"

printf "  running kit push smoke on %s [%s] (log: $APP_LOG)…\n" "$DEVICE_MODE" "$DEVICE_ID"
prep_device
( cd "$APP_DIR" && flutter pub get >/dev/null 2>&1 && \
  flutter test integration_test/push_smoke_test.dart -d "$DEVICE_ID" \
    $FLUTTER_TEST_EXTRA_ARGS \
    --dart-define=CAIRN_SYNC_URL="$SYNC_URL" \
    --dart-define=CAIRN_SMOKE_TOKEN="$SMOKE_TOKEN" \
    --dart-define=PUSH_SMOKE_TABLE="$TABLE" ) >"$APP_LOG" 2>&1 &
APP_PID=$!

# READY is printed only after: Firebase init → permission → token registered
# via the kit's push bridge → first sync → pauseSync (offline).
ready=""
for _ in $(seq 1 600); do
  grep -q 'PUSH_SMOKE_READY' "$APP_LOG" 2>/dev/null && { ready=1; break; }
  kill -0 "$APP_PID" 2>/dev/null || break
  keep_foreground
  sleep 1
done
if [ -z "$ready" ]; then
  printf "  ${RED}FAIL${RESET}  app never reached PUSH_SMOKE_READY (log: $APP_LOG)\n"
  tail -20 "$APP_LOG"
  wait "$APP_PID" 2>/dev/null
  exit 1
fi
printf "  device ready (user=%s) — inserting the triggering row…\n" "$SMOKE_USER"

# ---- 6. trigger: server-side row change (the push-worthy commit) ------------
psql_exec "INSERT INTO $TABLE (id, user_id, note)
  VALUES (gen_random_uuid(), '$SMOKE_USER', 'kit push smoke $(date +%s)');" >/dev/null \
  || { printf "  ${RED}FAIL${RESET}  row insert failed\n"; exit 1; }

# ---- 7. assert the rail fired (server metrics) ------------------------------
sent_after=""
for _ in $(seq 1 90); do
  sent_after="$(curl -s "http://127.0.0.1:$PORT/metrics" | awk '/^cairn_push_sent_total/ {print $2; exit}')"
  sent_after="${sent_after:-0}"
  [ "$sent_after" -gt "$sent_before" ] 2>/dev/null && break
  sleep 1
done
if [ "$sent_after" -le "$sent_before" ] 2>/dev/null; then
  printf "  ${RED}FAIL${RESET}  cairn_push_sent_total did not move ($sent_before → $sent_after)\n"
  curl -s "http://127.0.0.1:$PORT/metrics" | grep '^cairn_push_' || true
  tail -10 "$SERVER_LOG"
  exit 1
fi
printf "  server: cairn_push_sent_total %s → %s\n" "$sent_before" "$sent_after"

# ---- 8. assert the device received the doorbell ------------------------------
wait "$APP_PID"
APP_STATUS=$?
if [ $APP_STATUS -eq 0 ] && grep -q 'PUSH_SMOKE_RECEIVED' "$APP_LOG"; then
  grep -o 'PUSH_SMOKE_RECEIVED.*' "$APP_LOG" | head -1 | sed 's/^/  device: /'
  printf "  ${GREEN}PASS${RESET}  real-rail FCM doorbell: PG row → cairn-server → FCM → device\n"
  exit 0
fi
printf "  ${RED}FAIL${RESET}  device leg (exit=$APP_STATUS, log: $APP_LOG)\n"
grep -E 'PUSH_SMOKE_(READY|TIMEOUT)' "$APP_LOG" | head -5 || true
exit 1
