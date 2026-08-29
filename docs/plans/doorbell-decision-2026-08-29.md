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
  collapse_key=approval:<id>). STILL OPEN for the physical phone: the real
  APNs/FCM buzz and cellular pairing — the seam replaces the question
  SOURCE, not the rail delivery.
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
- The kit README paragraph (A) — trivial, can ride any kit commit.
  UNDECIDED rider for the approvals slice (grill D68 open items).
