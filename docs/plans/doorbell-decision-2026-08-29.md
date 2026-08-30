# Doorbell decision — what calls pushd's `POST /v1/send`

- **Date:** 2026-08-29 · **Status:** B1 mechanism SHIPPED same-day — the
  caller exists as `plugins/push-doorbell` in arxa-studio (`5973a7f`:
  gated by literal `ARXA_DOORBELL_PUSH=true`, never throws, 7-check
  selftest riding `scripts/ci.mjs`). The approval *event* is BUILT (2026-08-29):
  arxa-studio `ef8102a` — `plugins/approvals` (projection over the
  apiProxy mux stream, `/__arxa/approvals` list + decide routes,
  doorbell call site; 12th CI suite green) and arxa `e3f32e57` — the
  mobile data slice (cairn-shaped entity + tunnel client + repository;
  approvals_shell live; analyze clean, 38 tests). CLOSING CONDITION
  (D68, the ADR-0041 D5 pattern with teeth): the owner demonstrates the
  full loop on the physical phone — boot the studio (first live boot
  also proves the profile row + launcher copies), pair, arm
  `ARXA_DOORBELL_PUSH=true`, raise a pending question in a session,
  assert buzz → approvals_shell lists it → answer on the phone → the
  agent unblocks. Dark-gated off-default until then.

  SIMULATOR LEG COMPLETE (2026-08-29, iPhone 16 Pro sim, commits arxa
  `d38de882` + arxa-studio `6c75add`): the whole loop ran green on-sim —
  real pairing via a headless pairhost harness (desktop/src-tauri/examples/
  pairhost.rs: the real pairing.rs core, consume+expiry ticket re-mint),
  live tunnel, approvals card from a REAL user-questions ask (gated test
  seam `ARXA_APPROVALS_TEST_SEAM`, no LLM — the zai key was
  429-insufficient-balance), phone Approve resolving the ask engine-side,
  racing Deny refused 409 (first-claimant), 25 refreshes/108ms, 60
  parallel engine GETs all-200/41ms, and the doorbell POSTing a stub pushd
  with the exact cairn-push contract (content-free D65 copy,
  collapse_key=approval:<id>). The physical-phone leg is CLOSED TOO —
  2026-08-29, same day: see the PHONE LEG COMPLETE record at the bottom.
- **Context:** the push rail is built and green end-to-end *except the trigger*:
  tokens are minted on-device (M7, tauri-plugin-mobile-push), registered over
  the pairing tunnel and re-registered on pushd restart (`pushd.rs`,
  `pairing.rs` PUSH stream; `pairing.json` is durable), and the daemon's send
  path is conformance-tested. `pushd.rs:23` still names the caller "a future
  notifications surface". This memo frames who that caller is.

## Verified state (both repos read 2026-08-29)

- **`/v1/send` contract** (`cairn-push/src/api.rs`): token-addressed,
  tenant-key authed; payload is `Silent{table, lsn}` (data doorbell —
  wake-and-sync) or `Visible{title, body}` (final text — templates are
  caller-side by design, ADR-0038 §2); `collapse_key` coalesces resends;
  per-tenant rate limit (429 with `Retry-After`); 202 + `push_id`, with a
  `/v1/receipts` correlation channel.
- **cairn-server already has a doorbell**: `PushNotifier::notify` fires in the
  fan-out hot loop on matched *offline* subscriptions
  (`cairn-infra/src/push/remote.rs:9`) — the embedded `PushRouter`, or
  `RemoteNotifier` delegating to a remote cairn-pushd when
  `CAIRN_PUSH_REMOTE_URL`/`CAIRN_PUSH_REMOTE_KEY` are set.
- **Studio desktop topology**: no cairn-server on the desktop (zero hits in
  `desktop/src-tauri`); pushd is the only cairn process, supervised by the
  tauri shell. The phone reaches the desktop over the iroh pairing tunnel
  (kit/studio_transport loopback HTTP proxy). Studio mobile boots kit/cairn
  (`ArxaKitCairnConfig.fromEnvironment`, `localOnly` default) and already
  scaffolds `approvals_shell` — "placeholder until the approvals entity
  registers with cairn" (`approvals_list_viewmodel.dart:6`).
- **atlet's proven pattern** (real devices): *silent* doorbell from the server
  (smoke asserts `cairn_push_sent_total`) → device wakes → background isolate
  cold-opens the same SQLite → `waitForFirstSync()` → render. No notification
  text transits APNs/FCM in the proven path.

## The decision — one per topology

### A. kit/cairn consumer apps (cairn-server in path): no new code

The data-doorbell already works: matched offline subscription → server
notifier → pushd → device wake → sync → render from local SQLite.
**Recommendation: document, don't build.** A one-paragraph "push pattern"
note in kit/cairn's README (silent wake + read-after-sync; content never
touches the rail) is the entire deliverable. Visible notifications stay a
caller-templated `/v1/send` concern for the app's own backend when it
actually needs marketing-grade text (ADR-0038 §2).

### B. arxa studio (pairing topology; no server fan-out exists here)

1. **Minimal engine caller (recommended).** The engine POSTs loopback
   `/v1/send` with a `Visible` payload for exactly **one** event class —
   *approval-requested* — `collapse_key` = the approval id (resends coalesce),
   bearer = tenant key from `pushd.env`. Small surface, immediate product
   value (agent approvals are the phone's raison d'être — the mobile shell is
   already scaffolded for it), and the daemon enforces rate discipline. Later
   event classes (task-complete/failed) join only after approvals prove the
   UX.
2. **Sync-first (heavier).** Approvals ride cairn sync: desktop hosts or
   embeds a cairn-server, mobile syncs an `approvals` table, the server
   fan-out fires the silent doorbell. Architecturally cleaner (content never
   transits the rail; matches the D8 privacy posture) but couples the
   doorbell to a studio data-path decision that hasn't been made.
3. **Defer.** Registration rail stays exercised by smoke only; approvals stay
   foreground-only. Rot risk on a rail that is otherwise done and green.

**Recommendation: B1 now; B2 when the studio data-path decision lands.** They
compose — once approvals sync, the silent doorbell replaces the visible wake
for sync-covered events, and `collapse_key` keeps the transition from
double-notifying.

## Open items for the owner

- ~~Notification copy ownership~~ — RESOLVED (grill D65): engine-side
  caller, fixed generic English, content-free; the summary rides the
  tunnel, never the rail.
- Whether the desktop ever hosts/embeds cairn-server (the B2 enabler) — a
  separate architectural decision, explicitly not this one. Grill D61
  keeps the payload cairn-shaped so this stays a transport swap.
- ~~The kit README paragraph (A)~~ — RESOLVED 2026-08-29: "The push
  pattern" paragraph now lives in kit/cairn's README Push section
  (silent wake → read-after-sync → render from local sqlite; content
  never touches the rail; collapse_key keeps a later sync-only
  transition from double-notifying).

## PHONE LEG COMPLETE (2026-08-29) — D68's closing condition MET

The full loop ran green on the owner's physical iPhone 15 (iOS 26.6,
wireless-tethered, dev-signed team 43GNRCGQXQ), with the pushd rail pointed
at REAL APNs — no stub anywhere in the delivery path:

- **Rail:** cairn-pushd (release build) with the operator's APNs key
  (AuthKey_A5PQD8FHNS.p8, key-id A5PQD8FHNS, team 43GNRCGQXQ, bundle
  solutions.arxadigital.arxa.mobile, CAIRN_APNS_SANDBOX=1 for the
  development-signed build — creds live in pushd.env beside the store,
  per the B4 operator-owned rule; never the repo).
- **Phone half (new code):** aps-environment=development entitlement
  (Runner.entitlements), a raw-APNs native bridge in AppDelegate
  (bidirectional arxa/apns channel: permission, token mint, foreground
  presentation, tap events — no Firebase in the path), an app-owned
  ApnsNotificationsBackend behind the kit's notifications port
  (platform-selected by AppNotificationsBackend so stacked regeneration
  cannot revert it), and buzz-tap deep-linking to the approvals shell.
- **Harness fix found by the field run:** pairhost never attached the
  pushd handle, so PUSH registrations landed in pairing.json but NOT in
  the daemon's registry — the doorbell send 404'd (token unknown to
  pushd). pairhost now reads pushd.env from its store dir and calls
  attach_pushd, exactly as the Tauri shell does.
- **The loop (PHASE=phone in the integration test, self-contained — it
  raises its own pending through the tunnel):** pair over LAN →
  permission authorized → APNs device token minted on-hardware and
  registered through the tunnel → seam raise against a live idle agent →
  **doorbell → cairn-pushd → api.sandbox.push.apple.com → BUZZ** —
  title 'Approval needed', body 'Open Arxa Studio on your phone to
  review.' asserted in-app off the native willPresent event →
  approvals card → Approve tapped on the phone → the ask resolved
  engine-side: AGENT UNBLOCKED [{answers:[{id:q1, selected:[Approve]}]}].
  Final line: 00:25 +4: All tests passed!
- **Delivery evidence (pushd /v1/receipts):** three consecutive
  approval-requested sends outcome:"delivered" at provider_ts 10:10:53Z
  and 10:14:58Z, with duplicate rings for the same approval coalesced
  by collapse_key — D66's coalescing proven against the live provider,
  not a mock.
- Owner interactions during the run (honest ledger): one Xcode Apple-ID
  sign-in (no accounts were configured on the Mac) and one Allow tap on
  the permission dialog. Everything else was automated.
- **Still owner-flavored, deliberately:** the phone was on Wi-Fi; the
  cellular-pairing variant (phone off-Wi-Fi, relay-traversing dial) is a
  coverage nicety, not a rail unknown — iroh NAT traversal is the same
  code path. The dark gate ARXA_DOORBELL_PUSH=true STAYS off-default by
  design (arming is an operator choice, ADR-0041 D5).

## FOLLOW-UPS 2026-08-29 (evening) — 1+2+3 landed (3 was a rig bug, not a kit bug), 4 decided

### 1. Cold-start tap drain + task-tap routing — LANDED (arxa main)
- `a86ba6c4`: ApnsBridge buffers `pendingTap` (read-and-clear channel
  method), stamps `requestId`; Dart drains after handler registration and
  dedupes by requestId (covers the drain/live race on cold launch).
- `1aee8bdb`: `collapseKey` plumbed (threadIdentifier →
  `aps['collapse-id']` fallback); pure `routeForTap()`: `task*` → startup
  route, else approvals. ponytail: task taps land on '/'
  (PairingScanViewRoute) — no task surface exists yet.
- 44/44 unit tests, analyzer clean. OWED: killed-app cold-start tap on a
  physical device.

### 2. Task-complete/failed doorbell class — LANDED (arxa-studio `6083d93`)
- `plugins/approvals` `foldJobsFrame()` consumes `session/jobs` frames on
  the SAME mux the approvals path already used (JobView statuses;
  completed → finished, failed+killed → failed; first-sight per id per
  process). Same dark gate, POST, bearer. Content-free copy: 'Task
  finished' / 'Task failed' + 'Open Arxa Studio to see the result.';
  `collapse_key` task:<id>; category task. Selftests green (10 + 4 blocks).
- Observed quirk during the rig run: a re-raise of an ANSWERED session's
  ask (same approval id) at a relay-transition moment was correctly
  coalesced by the first-sight set — no buzz, no send. Collapse discipline
  held.

### 3. Cellular field variant — GREEN (2026-08-29 late evening). Root cause
### was the RIG's relay-less tickets; pairhost fixed; kit exonerated
- Harness (arxa main, `20c7589e`): `PHASE=phone` +
  `--dart-define=CELLULAR=true` inserts a 5-min flip window after pairing,
  then a patient reconnect gate: probe every 5s;
  `TransportService.resume()` re-issued at most every ~50s — resume()
  supersedes the in-flight dial (fresh epoch), so tight resumes starve it.
- (Superseded diagnosis: the first loop blamed the kit transport's redial.
  The isolation had a hole — "pairhost relay healthy" was checked from the
  Mac, ON the LAN. See below.)
- ROOT CAUSE: the D68 rig's pairhost minted RELAY-LESS tickets.
  `examples/pairhost.rs` binds `presets::Minimal` +
  `RelayMode::Disabled` (deliberate for sim adjacency) and advertised ONLY
  `TransportAddr::Ip(<LAN IP>)`. A private LAN IP is unroutable from a
  carrier network, so over cellular EVERY dial — however patient — must
  time out; the 180+ failures were the ticket, not the kit. The production
  desktop pairing core uses `presets::N0` (relays on, pairing.rs:343) and
  was never affected.
- FIX (this commit): `ARXA_PAIRHOST_RELAY=1` opts pairhost into the n0
  relays — it waits for the relay handshake and mints tickets carrying
  `TransportAddr::Relay` alongside the LAN IP. Flag unset = unchanged
  relay-less behavior for sims. kit/studio_transport needed NO changes:
  given a relayed ticket the transport auto-redialed over cellular by
  itself, no resume() required.
- GREEN RUN: pair over Wi-Fi → flip Wi-Fi off → gate prints "tunnel
  re-established after 0 probes" (the transport re-dialed through
  usw1-1.relay.n0.iroh.link during the window on its own) → APNs token
  registered over the cellular tunnel → raise → doorbell delivered ~3s
  (pushd receipts seq 26-28, coalesced) → buzz → card → "Approve" → agent
  unblocked: `05:28 +4: All tests passed!`
- Run discipline: run #1 after the fix stalled post-raise while the
  console was DETACHED (logs lost; a detached integration-test app exiting
  only proves the test FINISHED, not how). Rerun #2 attached over USB
  passed end-to-end. Lesson: on USB stay attached through the flip — USB
  survives the interface change; detach only for wireless-debug runs.

### 3b. Notification persistence — FIXED (2026-08-29 night): foreground
### pushes lacked .list; verified green on cellular
- REPORT: "the notification is not staying in my lock screen notification
  area like it did when on wifi".
- ROOT CAUSE: not cellular at all — a presentation-path issue masked by app
  state. AppDelegate willPresent (app FOREGROUND) completed with
  [.banner, .badge, .sound]; .list is the option that puts a notification
  in Notification Center / the lock-screen list. Foreground pushes flashed
  and vanished. Background/closed delivery (system-presented — the earlier
  Wi-Fi observations) always persists, which framed the bug as
  "wifi vs cellular" when it was "foreground vs background".
- FIX: completionHandler([.banner, .list, .badge, .sound]) — one line.
- VERIFIED on cellular (owner-observed): raise via engine seam while the
  phone is mobile-data-only, app foreground → banner arrives → STAYS in
  Notification Center after sliding away. (pushd receipt seq 54,
  approval-requested, delivered.)
- OWED (separate bug this hunt surfaced): intermittent zombie link after a
  mid-session Wi-Fi→cellular handoff. Evidence: during a late flip, the
  relay session dropped (pairhost: "uplink: connection lost") while the
  phone's conn.closed() never fired — the transport's closed-only healing
  can't see it, and every tunnel request fails fast from then on
  ("Connection closed before full header"). iroh keepalives are already on
  (endpoint/quic.rs sets keep_alive_interval + max_idle_timeout), so the
  heal belongs app-side: on a transport-level refresh failure,
  ApprovalsRepository should issue TransportService.resume() and retry
  once (pull-based v1 already documents refresh triggers; production heals
  on app-foreground only today).

### 4. B2 sync-first decision — DECIDED (recorded here; arxa-studio
D-numbers untouched to avoid colliding with the parallel org-model-v2 track)
- Purpose: BOTH — silent doorbell AND an offline browse projection.
- Scope: full mirror is the TARGET (orgs/folders/projects/memberships,
  then sessions, then the rest); the approvals table is phase 1.
- Writer: MIRROR-OUT. The studio engine is the single writer; cairn is a
  read-model replica ("mobile's projection of the tree", D46/M7-M8; D32
  BYO wire contract). Producers stay engine-side.
- Transport: SIDECAR cairn-server supervised by the Tauri shell (the
  pushd precedent), engine mirrors out over localhost. Embed in-process
  only if perf later demands it.
- Surfaces: the dsh WEBVIEW stays the phone's online browse surface (the
  full studio); cairn serves offline browse + the silent doorbell
  (wake-and-sync, render from local SQLite — the atlet pattern). Visible
  wake remains for approvals until B2 lands; the silent doorbell replaces
  it for sync-covered events; collapse_key keeps the swap from
  double-notifying.
- Wording trap to reconcile: M4 says "not a web wrapper" while the
  delivery contract mandates the webview session surface — reword M4 to
  "webview for online surfaces, native for pairing/push/offline".

## FOLLOW-UPS 2026-08-30 (overnight) — zombie heal LANDED, cold-start lesson, B2 plan

### 3b-follow-up. Zombie-link self-heal — LANDED (arxa main `f537e755`)
- The memo-3b OWED fix: `ApprovalsRepository.refresh()` on a
  transport-level failure while PAIRED now heals once —
  `TransportService.resume()` → bounded wait (20s) for a fresh
  `connected` status → retry the pull exactly once; rethrows the
  original error when unpaired (nothing to heal), when the status
  stream closes without reconnecting, or when the wait times out; a
  retry that still fails propagates its own error.
- Enabling half (same commit): `ApprovalsApiClient._json` now wraps
  `IOException`/`TimeoutException` as `ApprovalsOfflineException(cause)`
  — the zombie's raw `HttpException("Connection closed before full
  header")` previously escaped even the viewmodel's
  `on ApprovalsOfflineException` catch, so the inline offline copy
  never showed. One exception vocabulary end to end (D62).
- TDD: 7 new repository tests (heal succeeds / gives up after one
  retry / rethrows on a never-returning tunnel / no heal when unpaired
  / no heal on a 5xx) + 2 api-client tests (real socket-refused →
  offline type). 51/51 green, analyzer clean.

### Cold-start tap on device — IN PROGRESS; harness lesson recorded
- The killed-app tap test REQUIRES a release (AOT) build: a debug (JIT)
  Flutter iOS build cannot cold-launch standalone — after killing the
  app, tapping its icon/notification hangs on the splash forever
  (no VM to serve the kernel). First attempt used `flutter run
  --debug` and hit exactly that; the tap DID arrive while the app was
  dead (receipts seq 55-63, one send + 8 coalesced, delivered) but the
  app could not open. Release build installed; run to conclude.
- Every `flutter run` reinstall wipes the on-phone pairing — budget a
  fresh QR scan per install (pairhost with the same store + fresh
  ticket; `segno` renders the QR).

### Parked items — M4 reworded; task-tap stays parked
- M4 reworded in arxa-studio `docs/plans/mobile-grill-decisions.md`
  (commit `a5882a0`, NOT pushed — the operator's master had 11 unpushed
  commits; push rides their next push). "Webview for online surfaces,
  native for pairing/push/offline" now matches the delivery contract.
- Task-tap deep-link: assessment re-confirmed — `routeForTap` sends
  task taps to the startup route; correct until a task surface exists.

### B2 sync-first phase 1 — PLANNED, first seam in
- Plan: `docs/plans/b2-sync-first-phase1.md` (seam map argued from
  cairn main.rs/ports.rs/fanout.rs/pushd.rs line numbers). Ingest
  decision: channel-fed `MirrorReplicator` + admin-gated `POST /ingest`
  — NOT WS write-back (needs PG), NOT desktop Postgres (ops-heavy).
- First seam LANDED in cairn: `MirrorHandle`/`MirrorReplicator`
  (channel-fed `ReplicatorStream` + in-memory snapshot buffer with
  fail-closed tenant scoping) + the `crate::ident` lift the snapshot
  module's own note asked for. 7 tests green; full gate concluding.

### Task 5 LANDED + rig-rebuild ledger (2026-08-30 morning)
- `desktop/src-tauri/src/cairn_server.rs` (arxa `3897dde0`): the B2 mirror
  sidecar, supervised exactly like pushd — probe-then-spawn on
  127.0.0.1:8190, `cairn-server.env` keystore (0600; owned keys BIND /
  SYNC_AUTH=none / REPLICATOR=mirror / ADMIN_TOKEN ≥32), discovery
  CAIRN_CAIRN_SERVER_BIN → ~/.cargo/bin → PATH, kill-only-own-child on
  exit, pushd.env read for the CAIRN_PUSH_REMOTE_* rail forward (phase 1b
  silent doorbell; plain secret is correct for registered-token sends).
  3/3 tests, clippy clean; plan Task 5 ticked (`5be849d3`). Remaining
  phase-1 leg: Task 6's live WS subscriber.
- Overnight reboot killed the whole rig (harness jobs, /tmp/arxa-d68,
  arxa target/). Rebuild recipe that worked, with the four traps that
  cost the morning:
  (1) the studio launcher HARD-STOPS when DSH_HOME leaks in from a parent
  dsh session — relaunch `env -u DSH_HOME` (its own isolation guard, by
  design);
  (2) arxa's Rust manifest is desktop/src-tauri/Cargo.toml, NOT the repo
  root (arxa is a Flutter repo — `cargo build` at root finds nothing);
  (3) background processes started from an agent shell die with it unless
  `nohup … & disown`-ed, and a FIFO stdin needs its `sleep infinity >
  fifo` holder started in the SAME call or the reader blocks forever on
  open (silent — no log line, no process);
  (4) pyenv 3.13 segno 1.6.6 has no `__main__` — `python3 -m segno`
  fails; use the library API (`segno.make(t).save(path, scale=8)`).
- Push-side facts re-verified live on rebuild: pushd envs are
  CAIRN_PUSHD_BIND/DB/API_KEYS + CAIRN_APNS_KEY_P8 (path ok)/KEY_ID/
  TEAM_ID/BUNDLE_ID/SANDBOX=1; the engine doorbell reads pushd.env +
  pairing.json from ARXA_APP_DATA_DIR (overrides ARXA_PUSHD_URL/KEY);
  the approvals test seam answers GET /__arxa/approvals/__test_raised
  and the raise shape is {sessionId, questions:[{id,question,header,
  options:[{label,description}]}]} with Origin http://127.0.0.1:7899.
