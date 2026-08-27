#!/usr/bin/env bash
# Shared constants for the arxa_kit_cairn "local live" harness. Sourced by the
# other tool/live_*.sh scripts — not meant to be run directly.
#
# "Local live" stands in for a deployed cairn sync server: real cairn-server +
# real docker Postgres + real HS256 JWTs signed with the dev secret below. Same
# code paths a production deploy exercises (auth -> tenant-scoped reads ->
# tenant-enforced write-back), just HS256 with a dev secret (auth.rs routes on
# the JWT's `alg` header, so this is a legitimate substitution, not a shortcut
# around the auth layer). Modeled on cairn's deleted todo fixture (git f8d67be).

set -euo pipefail

# The cairn repo root: $CAIRN_REPO wins, else the sibling checkout layout
# (arxa at <dev>/totem_labs/arxa, cairn at <dev>/cairn). A machine without a
# cairn checkout self-skips in live_up.sh.
ARXA_KIT_CAIRN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAIRN_REPO_ROOT="${CAIRN_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." 2>/dev/null && pwd)/cairn}"

# Regenerated state lives under kit/cairn/.cairn-live/ (gitignored).
CAIRN_STATE_DIR="$ARXA_KIT_CAIRN_DIR/.cairn-live"

# Dev-only shared secret — never used against a real deployment.
CAIRN_DEV_JWT_SECRET="arxa-kit-cairn-local-live-dev-secret-do-not-use-in-production"

CAIRN_PG_URL="postgresql://cairn:cairn@localhost:5433/cairn"
CAIRN_PUBLICATION="cairn_pub_arxa_kit"
CAIRN_SLOT="cairn_slot_arxa_kit"
CAIRN_TENANT_COLUMN="user_id"

# The tables the live sync test drives — dedicated single-tier CRDT tables,
# matching the engine's truth: a tagged table's WHOLE row payload is the CRDT
# state (cairn-client sqlite.rs:120), and a table is at most one tier.
CAIRN_TABLES="kit_live_counters,kit_live_orsets"
CAIRN_COUNTER_COLUMNS="kit_live_counters:value"
CAIRN_OR_SET_COLUMNS="kit_live_orsets:tags"

# 8820 — clear of cairn's zero-setup default (8800), the SDK's own integration
# test (8801), and the old todo fixture (8810).
CAIRN_BIND="127.0.0.1:8820"
CAIRN_WS_PATH="/sync"
CAIRN_WS_URL="ws://$CAIRN_BIND$CAIRN_WS_PATH"
CAIRN_HEALTH_URL="http://$CAIRN_BIND/healthz"

CAIRN_DEV_LOG="$CAIRN_STATE_DIR/cairn-dev.log"
CAIRN_DEV_PID_FILE="$CAIRN_STATE_DIR/cairn-dev.pid"

# Written by live_up.sh, read by test/kit/cairn_live_sync_test.dart — the
# test never shells out for tokens.
CAIRN_LIVE_ENV_FILE="$CAIRN_STATE_DIR/live.env"
