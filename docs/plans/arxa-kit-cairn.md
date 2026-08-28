# arxa_kit_cairn — a kit backend for cairn, shaped like the supabase one

Goal: arxa and every Flutter app it produces consume cairn ONLY through the kit — one
package that owns the cairn_flutter import, the native-assets build, config/env, schema
declaration, auth/token plumbing, and push token lifecycle. App code never says
`import 'package:cairn_flutter/…'`.

## Status (2026-08-27)

Revised after a grilling/verification session (both repos read directly; four
exploration agents + an atlet digest; web research on native-binary distribution).
Decisions D1–D5 recorded below are binding. Several facts in the previous revision
were falsified against the repos and are corrected here. **Zero code written this
session — awaiting owner review before execution.**

## Decisions (2026-08-27 grilling session — binding)

**D1 — git pin.** Push cairn's 8 unpushed local commits (main → `fa1c5840`), then pin
the FULL SHA `fa1c5840a6abfcfefb27ed3df5b819b944e298cd` (path `sdk/cairn_flutter`).
GitHub main currently sits at `8d72c94e` (the previous pin) and predates the
`0.2.0-dev.1` bump that was cut explicitly "so upcoming arxa clients can pin an
unambiguous head". Flip pin → `v0.2.0` tag as a one-line bump when cairn cuts it
(tag truth: no git tag has ever carried cairn_flutter; `v0.1.0` predates `sdk/`).

**D2 — localOnly needs upstream work first.** No local-only entry point exists in
cairn_flutter today (`CairnConfig.url` is required — cairn_config.dart:39,50-60;
`open()` syncs). Add `CairnDatabase.local({sqliteDir, schema})` UPSTREAM in cairn
before kit phase 3. Bounded: the engine is local-first (`pauseSync()` keeps watches
pumping with a durable outbox — cairn_database.dart:754-767; `forTest` already
constructs around an injected engine :53). Kit maps `localOnly → local()`. Free→paid
upgrade = same SQLite file + a URL; zero data migration. (Feasibility is inferred
from those two facts, not yet proven by an implementation — first task of the PR.)

**D3 — Rust toolchain, two-track.** NOW: the kit documents Rust + cargo-ndk + NDK
(API 24) as an interim prerequisite (CI installs it); the plan drops the previous
"consumers need no Rust toolchain" claim — false today at every ref (`hook/prebuilt.json`
artifact URLs are ALL empty placeholders; cargo fallback is the active path on every
platform). UPSTREAM (tracked, non-blocking for kit phases): cairn populates
prebuilt.json via CI → GitHub Releases with sha256 — candidate plumbing: pub
`native_prebuilt` ^0.3.1 (manifest/download/verify/cache/source-fallback for hooks
packages). Kit flips to zero-toolchain at the pin bump after that lands. Grounding:
Flutter 3.44 stabilized native-asset bundling incl. prebuilt binaries; flutter_rust_bridge
itself ships a precompiled-binary CI workflow; frb issue #2572 tracks this exact need.
A consumer package cannot override a dependency's build hook — zero-toolchain can
only ever come from cairn's pipeline. (Kit never vendors/builds cairn binaries — dead
approach, stays dead.)

**D4 — live-proof harness is kit-owned.** `kit/cairn/tool/live_up.sh` + `live_down.sh`,
modeled on the deleted fixture's recovered script (git `f8d67be` — docker PG 16
(port 5433, wal_level=logical) + CREATE TABLE + `cairn init` + HS256 JWT + `cairn dev`
with healthz wait) and atlet's self-skip pattern (exit 0 SKIP when docker/cargo
absent → `arxa gate tests` stays green everywhere). The previous plan cited
`fixtures/flutter/todo/tool/cairn_live_up.sh` — that fixture was DELETED from cairn
(`f0f3986`, 2026-07-31; Makefile targets now dangle).

**D5 — session scope.** This revision only; execution (incl. the cairn push, 0a)
starts next session after owner review.

## Facts as verified (2026-08-27 — supersedes all prior facts sections)

### cairn_flutter at fa1c5840 (sdk/cairn_flutter)

- Version `0.2.0-dev.1` (pubspec:12; 0.1.0 was never published — CHANGELOG tag-truth).
  No `publish_to`. Deps: `flutter_rust_bridge` + `flutter_rust_bridge_hooks` exactly
`2.13.0-beta.5` (:36-37), `supabase_flutter ^2.8.0` (:52), `code_assets ^1.2.1`,
`hooks ^2.0.2`. Dart `^3.12.0`; pairing verified on Flutter 3.44.9 / Dart 3.12
(README:326 — pub get resolves, analyze clean, 72 tests green through the real hook).
- Entry points (lib/src/cairn_database.dart):
  - `connect({required url, token?, schema?, required sqlitePath, orSetTables?,
    counterTables?})` :127 — sync; schema via `GET {base}/schema` when null.
  - `open({required CairnConfig config, schema?, required sqliteDir, …})` :170 —
    **config-driven sync, NOT local-only** (corrects the previous revision): `url`
    required ws(s):// (cairn_config.dart:39); optional `supabase` block bootstraps
    Supabase + session token (StateError without a live session :188-193). Supabase
    global probed by catching AssertionError (:210-217) — the kit must never
    double-init Supabase.
  - `supabase({required cairnUrl, schema?, required sqlitePath, …})` :252 — caller
    must have `Supabase.initialize`d + signed in. JWT rotation via `Cairn.setToken`
    without reconnect: confirmed (:294-312; `setToken(null)` on signedOut). Web
    differs: setToken = reconnect (engine_web).
  - **No local-only entry exists** → D2.
- CRDT verbs (real names — the previous "adjustCounter" does not exist):
`counterIncrement/counterDecrement({table, pk, delta})`, `orSetAdd/orSetRemove({table,
pk, element})` on `Cairn` (:385-450) and `Collection<T>` (:1237-1264); both gated on
`orSetTables`/`counterTables` declared at open; undeclared verbs throw
`*TableNotTagged` (:1221-1236). The fail-loudly path is CLIENT-side (crates/cairn-client
client.rs:1829-1831) and requires triple consistency: client config + storage tags +
server env `CAIRN_OR_SET_COLUMNS`/`CAIRN_COUNTER_COLUMNS` (cairn-server main.rs:129/136).
- Push (ADR-0037): `registerPushToken(platform ∈ {fcm,apns,webpush}, token)` :812 →
`POST /push-tokens` (204 or `CairnPushTokenException`); `deregisterPushToken(token)`
  :838 → `DELETE /push-tokens/{token}`; one 401→refresh→retry (:863-871); registered
  tokens in-memory only across process restarts (server prune covers). Sign-out hook
  auto-deregisters at construction (:44, :904-912); `registerSignOutHook` :709; hooks
  run after wipe, must be idempotent; `db.signOut()` BEFORE `supabase.auth.signOut()`.
- Native build: `hook/build.dart` + `hook/prebuilt.json` — 7 keys (macos-universal,
  3× android, 3× ios), sha256-verified download — but all artifact URLs empty → D3.
  Android routes through cargo-ndk + NDK, API 24, throws a helpful error if missing.
- Attachments (ADR-0034): `attachments({adapter, blobStore})` extension;
`queueUpload/queueDownload/remove/pump/start`; ports `AttachmentStorageAdapter` +
`BlobStore` (+ `LocalFileBlobStore`, `SupabaseStorageAdapter({bucket, pathPrefix})`);
  requires `attachments` in subscribed tables AND server `CAIRN_WRITE_TABLES`; blob
  wipe auto-registers as a sign-out hook.
- Predicates/schema: `Where` eq/neq/lt/lte/gt/gte/inList/isNull/notNull + and/or/not
  (identifier-regex + literal-escaping = injection boundary), `Order.asc/desc`;
`CairnSchema/CairnTable/CairColumn` — the declared schema IS the migration story
  (re-applied each connect, DROP+CREATE view). Raw-SQL note: schema-qualified names
  collapse (`myschema.tasks` → view `myschema_tasks`); structured paths normalize —
  the adapter stays on structured paths.
- Semantics the adapter must respect: `writeBatch` = local-atomic outbox entry, NOT a
  server transaction (per-field LWW apply); `execute()` aliases getAll — read-only by
  convention only; `waitForFirstSync()` :923 is the UI gate; status pump is lazy;
`close()` is idempotent and keeps the SQLite file; streams deliberately swallow
  errors — sync failures surface as connection-state flaps, not exceptions.
- Web engine (ADR-0036): mature — `WebCairnEngine` over the shared cairn-ffi-wasm
  Worker (opfs-sahpool), CRDT + writeBatch included, `webStorageDegraded` signal,
  Playwright e2e; `syncStream` parameterized streams are native-only v1.

### cairn repo / server

- Public: origin = github.com/unfazed-dev/cairn (ls-remote verified; main = 8d72c94e
  today). Apache-2.0 end-to-end. Rust workspace (12 crates) + 9 SDKs; `apps/atlet`
  is the reference consumer. 8 finished commits sit unpushed locally → D1/0a.
- WS at `/sync` (`CAIRN_WS_PATH`); `CAIRN_SYNC_AUTH none|supabase-jwt` (HS256 secret
  and/or JWKS); identity = `Principal{account_id, tenant_id}` stamped server-side from
  the JWT — never client-attested (ADR-0018).
- fixtures/flutter/todo deleted (`f0f3986`, 2026-07-31); harness recoverable from git
`f8d67be` → D4.
- cairn-side plan `docs/plans/cairn-integration-tauri-flutter-push.md` (b982671, part
  of the unpushed 8): constraints — Supabase decoupling ("the Supabase database
  belongs to arxa digital solutions… free users have no database; every cairn feature
  must work identically with local-only storage"), cairn fixes stay in cairn, studio
  consumes tagged versions. This kit is Track C's consumer side, elevated into arxa.
  Its C1 ("pin 0.1.0, track the v0.1.0 tag") is stale — superseded by D1 + tag-truth.
- DX redesign reality: query builder REJECTED upstream (cairn-unified-api-contract.md:94);
`.diffs()` has zero occurrences in the repo — phase 6's exposed surface is smaller
  than the warehouse appendix assumed; the seam holds regardless.

### kit/data + kit system (arxa)

- `enum ArxaKitDataBackend { seed, supabase, appwrite }`
  (kit/data/lib/config/arxa_kit_data_config.dart:11); `ArxaKitDataConfig.validate()`
  throws StateError naming the missing piece (:98-115);
`ArxaKitData.initialize({config, entities, fixtureAssets?, assetReader?})`
  (arxa_kit_data.dart:126) registers `ArxaKitIdService` + `ArxaKitSchemaRegistry`
  singletons (:145-146) then per-backend storage/repositories/auth into
`arxaKitLocator` = `StackedLocator.instance` (kit/core — NOT get_it).
- `ArxaKitRepository<T>` port: getById/getAll/watchById/watchAll/upsert/upsertMany/
  patch(original, patched)/delete + top-level `arxaKitJsonPatch`
  (repositories/arxa_kit_repository.dart:14-49). `ArxaKitEntityRegistration{schema,
  fromJson, toJson, apply}` for reification.
- **IdService + SchemaRegistry are kit/data types** (lib/ids/…:14, lib/schema/…:6) —
  the plugin seam passes exactly these, resolved from `arxaKitLocator`.
- Emitters are pure-Dart classes (SupabaseSql / SupabaseSeed / AppwriteJson) under
  kit/data/lib/emitters/, invoked via `dart run example/generate.dart`; outputs
  stamped do-not-edit (kit/data/AGENTS.md). Emitter contract tests exist
  (test/kit/emitters/). Natural insertion point for a cairn emitter living in the
  NEW kit (emitters are pure Dart over schema types — no import of kit internals
  beyond the public schema API).
- Seed contract tests: single file (test/kit/repositories/seed/
  arxa_kit_seed_repository_test.dart), all named `kit.data.seed-repos — …`, inline
  model/schema/codec + makeRepo() (:24-76). Extraction to a shared runner =
  parameterize those helpers behind a repo-factory param. No supabase/appwrite
  contract suites exist today.
- kit/notifications EXISTS with the push seam already shaped:
`ArxaKitNotificationsService.tokenStream` (:29) + `foregroundMessages`; an FCM
  push backend is present.
- showcase_app boots kit/data via `AppData.initialize` (lib/app/app_data.dart:36-51)
  with an INJECTABLE `config` (seed default) — the cairn smoke's injection point;
  the notes feature fully exists (showcase_notes_shell/**). `ARXA_CAIRN_MODE`: zero
  hits in the repo today.

### atlet (proven reference — the pattern to port; owner directive: push included)

- Push lifecycle (lib/push/push_pilot.dart): `ATLET_PUSH_PILOT` dart-define gate
  (literal "true" only — `=1` is silently false); conditional Firebase init (mobile
  only, never web/desktop); PushPilot attaches AFTER EVERY engine start (the SDK
  deregisters session tokens on signOut): requestPermission → getToken →
`registerPushToken('fcm', token)` (:178); `onTokenRefresh` → re-register (:144);
`CairnPushTokenException` non-fatal, retried next attach. Background isolate
(`cairnDoorbellBackgroundHandler`, vm:entry-point): persisted session-creds file →
  cold-open the SAME sqlite → subscribe + `waitForFirstSync()` → `close()` (NOT
  signOut — local store must survive). Known ceiling: persisted token can be stale
(~1h Supabase lifetime) → harmless 401 no-op wake. Web: VAPID public key via
  dart-define paired to the server's private key + service worker + 'webpush'
  platform token (JSON {endpoint, keys{p256dh, auth}} with the re-key fix).
  macOS: firebase_messaging has NO macOS implementation — desktop is sync-only
  (WS doorbell). Real-rail proof: tool/push_smoke.sh — Android emulator automated
  (dual assertion: server `cairn_push_sent_total` + device marker), physical iPhone
  manual, self-skipping on missing operator inputs.
- Adapter nuances the warehouse doc missed (cairn_adapter.dart): tenant-table writes
  carry EXPLICIT `user_id` (server PgWriteBack runs on a direct PG connection where
`auth.uid()` is NULL, :405-415); watch streams re-wrapped `replayLatest` (late
  subscribers get the last snapshot); per-row `write(op:'upsert')` is the shape proven
  on real devices — the kit adapter supports BOTH shapes (warehouse writeBatch/
  column-diff AND atlet per-row); adapter signOut completes before any engine swap.
- Conformance shape: frozen SyncAdapter contract v1.1 + fake-based CI suite + live
  operator checklist (scorecard) — the kit's proof mirrors this layering.
- Deps to mirror for push parity: firebase_core ^4.13.0, firebase_messaging ^16.5.0,
  web ^1.1.0, path_provider; plus the native wiring (conditional google-services
  plugin, iOS entitlements/UIBackgroundModes/action categories, service worker).

## Decision: separate package `kit/cairn` (`arxa_kit_cairn`) — unchanged, verified still right

Why not more adapters inside kit/data (as before):
1. **Native payload.** cairn_flutter ships a native library through a beta-versioned
   build hook. Folded into kit/data, every arxa app — including supabase-only ones —
   compiles and carries it. supabase/appwrite are pure-Dart; the precedent never had
   this cost.
2. **Churn isolation.** cairn is pre-1.0 and moving; kit/data is the stable heart of
   every app.
3. **Licensing/positioning.** Cairn is an arxa digital solutions product distributed
   separately; a dedicated package keeps that boundary auditable.

Consequence unchanged: kit/data cannot name cairn types (no optional deps in Dart),
so kit/data gains one small seam and arxa_kit_cairn plugs into it.

## Phase 0 — upstream prerequisites (parallel; 0a blocks phase 2, 0b blocks phase 3)

- **0a [D1]**: push cairn's 8 local commits → GitHub main = fa1c5840. The 4 dirty
  files in cairn's tree stay uncommitted local work. Cairn push is an owner-approved
  action (D1) executed at session start.
- **0b [D2]**: cairn PR `CairnDatabase.local({sqliteDir, schema})` + tests; land on
  main; included in the NEXT pin bump after fa1c5840 (or before, if it lands first —
  pin whichever SHA then-current includes it).
- **0c [D3]** (tracked, non-blocking): cairn populates prebuilt.json via CI → GitHub
  Releases; consider adopting `native_prebuilt`. Gates only the zero-toolchain flip.

## Phase 1 — plugin seam in kit/data (small, backward-compatible, cairn-independent)

- New abstract interface in kit/data (verified against ground truth — signature
  unchanged from previous revision; IdService/SchemaRegistry are kit/data types):
  ```dart
  abstract interface class ArxaKitBackendPlugin {
    String get name;                       // 'cairn'
    Future<void> initialize(              // registers repos/auth/storage into locator
      ArxaKitDataConfig config,
      List<ArxaKitEntityRegistration<dynamic>> entities,
      ArxaKitIdService idService,
      ArxaKitSchemaRegistry registry,
    );
    Future<void> dispose();
  }
  ```
- `ArxaKitDataBackend` gains `.plugin`; `ArxaKitDataConfig` gains
`ArxaKitBackendPlugin? plugin`; `validate()` enforces it exactly like supabase
  credentials (StateError naming the missing piece, mirroring :98-115).
- `ArxaKitData.initialize` switch gains `case ArxaKitDataBackend.plugin: await
  config.plugin!.initialize(…)` after the IdService/SchemaRegistry registrations
  (:145-158 today). Built-ins untouched.
- Behavior-TDD red-first; test names cite `kit.data.backend-plugin — …`.

## Phase 2 — `kit/cairn` package scaffold (blocked on 0a)

- `kit/cairn/pubspec.yaml` — `arxa_kit_cairn`; deps: `arxa_kit_core`,
`arxa_kit_data` (seam + schema types), `cairn_flutter` git-pinned:
  ```yaml
  cairn_flutter:
    git:
      url: https://github.com/unfazed-dev/cairn.git
      ref: fa1c5840a6abfcfefb27ed3df5b819b944e298cd   # D1 — full SHA, bump deliberately
      path: sdk/cairn_flutter
  ```
  Dart `^3.12.0` (cairn_flutter's floor; pairing verified on Flutter 3.44.9).
- README documents the INTERIM Rust prerequisite (Rust toolchain; Android:
  cargo-ndk + NDK API 24) per D3, with the zero-toolchain flip promised at 0c.
- Exports: a single `arxa_kit_cairn.dart` barrel; nothing from cairn_flutter
  re-exported except through kit types.
- Bump discipline: each pin bump records what changed in `hook/`, the FRB pin, and
  prebuilt availability (risk 1).

## Phase 3 — config + env (blocked on 0b for localOnly)

  ```dart
  enum ArxaKitCairnMode { localOnly, sync, supabaseBridge }

  class ArxaKitCairnConfig {
    final ArxaKitCairnMode mode;
    final String? syncUrl;           // ws(s)://…/sync — required for sync/supabaseBridge
    final String? sqliteDirOverride; // default: path_provider app-support dir
    final bool push;                 // opt into push token registration
    final Set<String>? orSetTables;  // CRDT tiers — must triple-match server env
    final Set<String>? counterTables;
    const ArxaKitCairnConfig({...});

    /// dart-define surface — the only env contract apps ever see:
    ///   ARXA_CAIRN_MODE = local | sync | supabase   (default: local)
    ///   ARXA_CAIRN_URL  = wss://…/sync              (required unless local)
    ///   ARXA_CAIRN_PUSH = true|false                (default: false; literal "true")
    factory ArxaKitCairnConfig.fromEnvironment() => ...;

    void validate();   // StateError with the exact missing define, mirroring kit/data
  }
  ```
- `localOnly → CairnDatabase.local()` [D2]: zero env, zero server, identical app
  code — free-user parity (decision now also recorded in cairn's b982671 constraint 1).
- Tokens are NEVER env: `supabaseBridge` pulls session JWTs from kit/data's
`ArxaKitAuthService` (kit/data owns auth; the plugin only subscribes to rotation →
`Cairn.setToken`; respect the Supabase double-init probe); `sync` takes a token
  provider callback (host-supplied, agency deployments).

## Phase 4 — the backend plugin + adapters (parallelizable; CRUD before push/storage)

- `ArxaKitCairnBackend implements ArxaKitBackendPlugin`: opens the right
`CairnDatabase` per mode; owns lifecycle + `dispose`; `db.signOut()` before
`supabase.auth.signOut()`; hooks idempotent.
- `CairnKitRepository<E>` for every `ArxaKitEntityRegistration`:
  - warehouse mapping (docs/cairn/warehouse-inventory-arxa-cairn-example.md):
    getById→fetchById, watchAll→watchMapped (push-invalidation), patch→column-diff
    LWW, upsertMany→writeBatch (local-atomic outbox);
  - AND the atlet-proven per-row `write(op:'upsert')` shape — both supported;
  - explicit `user_id` stamping hook for tenant tables (PgWriteBack auth.uid() NULL);
  - watch streams re-wrapped `replayLatest`; `waitForFirstSync()` surfaced as the
    UI gate; stays on structured predicates (never raw SQL → no view-name collapse,
    no outbox foot-guns).
- CRDT without hard casts: `abstract interface class ArxaKitCrdtCapable` exposing
  adjustCounter→`counterIncrement/counterDecrement`, orSetAdd/orSetRemove (real
  cairn names inside the adapter); services feature-detect (`repo is
  ArxaKitCrdtCapable`); tables must be declared in config AND match the server env
  (triple consistency — the emitter emits the server snippet, below).
- Schema: `CairnSchemaEmitter.tableFor(schema)` → `CairnTable` + a generated
  server-side declaration snippet (`CAIRN_COUNTER_COLUMNS`/`CAIRN_OR_SET_COLUMNS`
`table:column` entries) so client and server cannot drift silently. Counter/or-set
  tiers come from new optional flags on the kit column descriptor
(`crdt: counter|orSet`), ignored by other emitters. Pure Dart, invoked like the
  existing emitters; outputs stamped do-not-edit.
- `ArxaKitCairnStorageService` over cairn attachments (two-plane; requires the
`attachments` table + `CAIRN_WRITE_TABLES` — emitter documents both).
- Push behind the kit/notifications seam (`tokenStream`), per the atlet checklist:
  opt-in define gate (literal "true"), attach after EVERY engine start,
`onTokenRefresh` re-register, non-fatal `CairnPushTokenException` retries,
  background-isolate handler (persisted session file, cold-open same sqlite,
  close()-not-signOut), VAPID web leg (key paired to server private key + service
  worker), macOS documented sync-only. `registerPushToken`/`currentAccessToken`
  surfaced on the kit facade. firebase_core ^4.13.0 / firebase_messaging ^16.5.0
  mirrored in the kit's example app.
- Test names cite `kit.cairn.<capability> — …` (canon: skills/arxa-tester/
  behavior-tdd-rules.md; static-state discipline with resetForTesting).

## Phase 5 — proof

- **Contract tests**: extract kit/data's seed repository behavior suite into a shared
  runner (`arxa_kit_data/lib/arxa_kit_testing.dart`, repo-factory param); run the
  same suite against `CairnKitRepository(localOnly)`. Cairn-specific additions:
  patch-survives-concurrent-edit, counter-merge, or-set add-wins.
- **Showcase smoke**: showcase_app boots with
`--dart-define=ARXA_CAIRN_MODE=local` (config injected at app_data.dart:40's
  parameter); notes feature round-trips CRUD; nothing above the seam changed.
- **Live proof [D4]**: kit-owned `tool/live_up.sh` (docker PG 16 + `cairn init`/`dev`
  + minted JWT) → one sync-mode integration test; SKIPs cleanly without docker/cargo.
- **Push smoke (real rail, operator-gated)**: mirror atlet's self-skipping script —
  Android emulator automated, physical iPhone manual, dual server-metric +
  device-marker assertions.

## Phase 6 — DX-redesign alignment (deferred, tracked — smaller than previously assumed)

Query builder: rejected upstream. `.diffs()`: does not exist. If/when cairn's DX
surface moves (computed, named streams), only `CairnKitRepository` internals and
facade guidance change — the plugin seam, config, and app code hold still.

## Open questions / risks

1. **FRB beta pin** — hook versions travel with the pinned SHA; each bump checks
   `hook/build.dart`/`prebuilt.json` and the FRB pin; prebuilt availability per rev
   is what makes consumers Rust-free once 0c lands [D3].
2. **Public-repo exposure** — every arxa app build clones the public cairn repo; CI
   needs no auth but builds depend on GitHub availability (accepted stopgap until
   pub.dev publish collapses the git block to a version constraint).
3. **Web** — engine is mature (`WebCairnEngine`); kit apps targeting web still need
   a decision (in scope for emitter/config, out of scope for first proof). Nuances:
   web setToken = reconnect; `syncStream` native-only v1; OPFS degradation signal.
4. **Tauri parity** (arxa studio itself) — cairn_tauri is a separate track in
   cairn's b982671; this kit is Flutter-only by design.
5. **Auth in pure-cairn mode** — cairn identity is a bearer JWT; until cairn has its
   own arxa-grade auth story: `sync` assumes host-supplied tokens (agency),
`supabaseBridge` is the arxa-default, `localOnly` needs none. Atlet's bg-isolate
   stale-token ceiling (~1h) carries forward as a known limitation.
6. **Unpushed-work discipline [D1]** — the pin is only valid after 0a lands; until
   then nothing may reference fa1c5840. Cairn's 4 dirty files remain uncommitted.
7. **Outbox foot-guns** — `execute()` is read-only by convention; `writeBatch` is
   not a server transaction; the adapter avoids raw SQL entirely.

## Execution order

1. **0a** push cairn (owner-approved, first action of the execution session).
2. **Phase 1** seam in kit/data (cairn-independent, tiny, blocks everything).
3. **Phase 2** scaffold + git pin; **0b** upstream `local()` PR in parallel.
4. **Phase 3** config after 0b; **Phase 4** CRUD adapter + emitter (parallelizable);
   push + storage after CRUD proof.
5. **Phase 5** contract tests → showcase smoke → live proof [D4] → push smoke.
6. **Phase 6** deferred; **0c** tracked upstream.
