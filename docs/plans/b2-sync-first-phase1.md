# B2 Sync-First — Phase 1 (approvals mirror) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The studio engine becomes the single writer of an `approvals` read-model mirrored into a Tauri-supervised cairn-server sidecar, which fans it out to subscribers and (phase 2) fires the silent doorbell.

**Architecture:** A channel-fed `MirrorReplicator` (the documented `ReplicatorStream` adapter-swap seam, cairn-server main.rs:8-11) receives engine approval-row events over a tiny admin-gated `POST /ingest` route; the same adapter materializes an in-memory snapshot so late subscribers see pre-mirror rows. The sidecar is supervised by the Tauri shell exactly like cairn-pushd (probe-then-spawn + respawn watchdog). Mobile's existing kit already speaks this: `ARXA_CAIRN_MODE=sync` + `approvalEntityRegistration` — only a reachable URL is missing.

**Tech Stack:** Rust (cairn-infra, cairn-server, arxa desktop src-tauri), axum, tokio mpsc; JSON wire stays human-debuggable.

**Spec:** arxa `docs/plans/doorbell-decision-2026-08-29.md` §4 (B2 decision: mirror-out writer, sidecar transport, approvals table phase 1, silent doorbell replaces visible wake at swap with collapse_key anti-double-notify).

## Global Constraints

- cairn hexagonal: dependencies point inward (infra implements application ports; server composes). Violations fail review.
- `unsafe` forbidden; clippy pedantic, `-D warnings` (the `make ci` gate for every cairn change).
- Wire protocol stays human-debuggable JSON.
- The engine is the ONLY writer — no client write-back in this phase (`NoWriteBack` under mirror replicator, same as fake).
- Approvals are phase-1-only; orgs/folders/projects/memberships join later (full mirror is the target, not this plan).
- Engine-side writer (arxa-studio) is operator-coordinated — OUT of this plan's executable scope; demonstrated via manual `/ingest` posts instead.

## Seam facts this plan argues from (verified 2026-08-30)

- `ReplicatorStream` port: cairn `crates/cairn-application/src/ports.rs:369-381`; only impls are `PgReplicator` and `FakeReplicator` (`crates/cairn-infra/src/replicator/fake.rs:110`). Fan-out driver call: `main.rs:638`.
- No HTTP ingest exists today; WS write-back requires `CAIRN_REPLICATOR=pg` (`main.rs:836-846`).
- Push: `PushNotifier::notify` fires per matched offline account + tenant-wide hints (`fanout.rs:340-417`); `RemoteNotifier` activates on `CAIRN_PUSH_REMOTE_URL`+`CAIRN_PUSH_REMOTE_KEY` (`main.rs:183-196`).
- Sidecar precedent: `arxa/desktop/src-tauri/src/pushd.rs` (probe-then-spawn :91-113, binary discovery :182-206, health :285-300) + engine watchdog (`lib.rs:330-420`).
- Mobile: `ArxaKitCairnConfig` (`kit/cairn/lib/config/arxa_kit_cairn_config.dart:39-66`, `localOnly` default = `CairnDatabase.local`); `approvalEntityRegistration` already exists (`mobile_flutter/lib/data/approvals/approval.dart:139-154`).

---

### Task 1: `MirrorReplicator` — channel-fed replicator + in-memory snapshot

**Files:**
- Create: `crates/cairn-infra/src/replicator/mirror.rs`
- Modify: `crates/cairn-infra/src/replicator/mod.rs` (module wiring)
- Test: `crates/cairn-infra/src/replicator/mirror.rs` (`#[cfg(test)]`)

**Interfaces:**
- Consumes: `ReplicationEvent` (cairn-domain), `ReplicatorStream` (ports.rs:369).
- Produces: `MirrorHandle::channel() -> (MirrorHandle, mpsc::Receiver<ReplicationEvent>)`; `MirrorHandle::snapshot_rows(table) -> Vec<ReplicationEvent-like row>`; `MirrorReplicator` implementing `ReplicatorStream` + the snapshot port consumed at subscribe time.

**Steps:**
- [ ] Write failing tests: (a) events fed into the channel yield from `next_event()` in order; (b) receiver close → `next_event()` returns `None`; (c) upserts recorded in the buffer are returned by the snapshot query; (d) deletes remove buffered rows.
- [ ] Run `cargo test -p cairn-infra mirror` — red.
- [ ] Implement: tokio mpsc receiver behind `std::sync::Mutex` (the fan-out driver polls synchronously — check how FakeReplicator bridges async, fake.rs:110-140, and match it); an ordered `Vec<(Lsn, RowOp)>` buffer per table for snapshot materialization.
- [ ] Green, then `make ci`.

**Commit:** `feat(infra): MirrorReplicator — channel-fed stream + in-memory snapshot buffer`

### Task 2: `POST /ingest` — admin-gated mirror write path

**Files:**
- Create: `crates/cairn-server/src/ingest.rs`
- Modify: `crates/cairn-server/src/main.rs` (route mount beside :981-1030)
- Test: `crates/cairn-server/src/ingest.rs` (axum tower tests)

**Interfaces:**
- Consumes: admin auth pattern from `admin_auth.rs` (`CAIRN_ADMIN_TOKEN`), `MirrorHandle` from Task 1.
- Produces: `POST /ingest` body `{"events": [{"table", "op": "upsert"|"delete", "pk", "payload", "source_seq"}]}` → `200 {"accepted": N, "lsns": [...]}` (server-stamped, monotonic; one allocator shared with snapshot bands); each event LSN-stamped by the server (monotonic counter, starts at 1 per boot).

**Steps:**
- [ ] Failing route tests: 401 without/with wrong token; 200 + events observable in the `MirrorHandle` on happy path; malformed body → 400.
- [ ] Implement handler + server-side LSN counter (`AtomicU64`).
- [ ] Green, `make ci`.

**Commit:** `feat(server): POST /ingest — admin-gated mirror write path`

### Task 3: composition root — `CAIRN_REPLICATOR=mirror`

**Files:**
- Modify: `crates/cairn-server/src/main.rs` (match arm at the :625-723 replicator selection; snapshot-source selection; write-back stays `NoWriteBack`; push config allowed)

**Interfaces:**
- Produces: env `CAIRN_REPLICATOR=mirror` boots the channel replicator + mounts `/ingest`; `CAIRN_PUSH_TABLES`/`CAIRN_PUSH_REMOTE_*` compose unchanged (the phase-2 silent doorbell rides this without further server work).

**Steps:**
- [ ] Wire the match arm; guard: mirror rejects `CAIRN_PG_URL` (mirror the :941-954 guard inverted).
- [ ] Snapshot under mirror serves from the Task-1 buffer (late subscribers see pre-mirror rows).
- [ ] Boot smoke test (existing config-test patterns in main.rs); `make ci`.

**Commit:** `feat(server): CAIRN_REPLICATOR=mirror — sidecar composition`

### Task 4: ADR

**Files:** Create `docs/adr/NNNN-mirror-ingest-sidecar.md` (next free number at execution time).

**Steps:**
- [ ] ADR: decision (channel replicator + /ingest over local-PG and WS write-back; why: no desktop Postgres, single-writer mirror-out, adapter-swap seam was pre-advertised), consequences (in-memory snapshot is phase-1 sized; LSN resets on sidecar restart = client re-subscribe via epoch; approvals-ephemeral justification), alternatives rejected with reasons from the seam map.
- [ ] Code cites the ADR (main.rs match arm + ingest.rs header).

**Commit:** `docs(adr): NNNN mirror ingest for the desktop sidecar topology`

### Task 5: Tauri sidecar supervision (arxa desktop)

**Files:**
- Create: `desktop/src-tauri/src/cairn_server.rs`
- Modify: `desktop/src-tauri/src/lib.rs` (init + kill on exit, mirroring pushd.rs wiring at :325/:429)
- Test: `desktop/src-tauri/src/cairn_server.rs` unit tests

**Interfaces:**
- Consumes: pushd.rs patterns — env keystore `<app-local-data-dir>/cairn-server.env` (0600), probe-then-spawn, binary discovery order (`CAIRN_CAIRN_SERVER_BIN` → `~/.cargo/bin/cairn-server` → `which`), engine-watchdog respawn (lib.rs:389-416).
- Produces: a supervised `cairn-server` on `127.0.0.1:8190` with `CAIRN_SYNC_AUTH=none` (loopback-only posture), `CAIRN_REPLICATOR=mirror`, push env forwarded to the pushd rail.

**Steps:**
- [ ] Failing tests: env-file shape + chmod; binary discovery order (temp dirs); externally-owned daemon wins (health pass → no spawn).
- [ ] Implement module; wire init/exit.
- [ ] `cargo check` + clippy clean; manual rig boot.

**Commit:** `feat(desktop): cairn-server sidecar — probe-then-spawn supervision`

### Task 6: rig demonstration (verification, no new product code)

**Steps:**
- [ ] Script (rig-only, /tmp): boot sidecar + pushd; `POST /ingest` two approval rows; subscribe as a WS client; assert both rows arrive as snapshot + a third posted after subscribe arrives live; assert the push rail fires via pushd receipts (silent payload, phase-2 shape).
- [x] FIRST LEG DONE (2026-08-30, real binary): cairn-server with CAIRN_REPLICATOR=mirror + CAIRN_ADMIN_TOKEN boots /healthz live; POST /ingest (upsert a1, upsert a2, delete a2) -> 200 accepted:3 lsns:[1,2,3] monotonic; wrong bearer -> 401; invalid table -> 400 events[0] message; instance WITHOUT the token -> 404 not-found (fail-closed, PUT /rules shape). Remaining leg: a live WS subscriber asserting snapshot + live delivery.

**Phase 1b (hand-off, NOT this plan's execution):** engine mirror-out writer (arxa-studio plugins/approvals → POST /ingest on every fold); mobile `ARXA_CAIRN_MODE=sync` pointed at the sidecar through an engine reverse-proxy route over the existing tunnel (offline reads come from local SQLite either way); visible→silent doorbell swap with collapse_key.

## Phase-1 design decisions pinned here (argued, not re-litigated)

1. **Ingest = new tiny route + channel replicator** — NOT WS write-back (needs PG), NOT desktop Postgres (ops-heavy), NOT client write-back (engine is sole writer).
2. **In-memory snapshot buffer** — approvals are ephemeral and phase-1-tiny; a durable snapshot store is YAGNI until the full-mirror phases.
3. **LSN resets on sidecar restart** — clients re-subscribe via the wire's epoch semantics; durable LSN sequencing is deferred with the full mirror.
4. **Sync rides the existing tunnel in 1b; the silent doorbell does not** — APNs wake → sync when reachable → render from SQLite is the atlet pattern and needs no new pairing.
