# arxa_kit_cairn — a kit backend for cairn, shaped like the supabase one

Goal: arxa and every Flutter app it produces consume cairn ONLY through the kit — one
package that owns the cairn_flutter import, the native-assets build, config/env, schema
declaration, auth/token plumbing, and push token lifecycle. App code never says
`import 'package:cairn_flutter/…'`.

## Facts this plan is built on (read from the repos, not memory)

**How supabase is kitted today** (`kit/data`, package `arxa_kit_data` 0.1.0):
- Supabase is not a separate package — adapters live inside kit/data
  (`repositories/supabase/`, `auth/supabase/`, `storage/supabase/`).
- Selection: `ArxaKitDataBackend` enum (`seed | supabase | appwrite`) on
  `ArxaKitDataConfig`, credentials via `ArxaKitSupabaseConfig{url, publishableKey}`,
  `validate()` throws `StateError` when the selected backend lacks credentials.
- Wiring: `ArxaKitData.initialize` → `_initializeSupabase` registers
  `ArxaKitRepository<E>` lazy singletons per `ArxaKitEntityRegistration` +
  `ArxaKitAuthService` + `ArxaKitStorageService` into `arxaKitLocator`.
- kit/data hard-deps `supabase_flutter: ^2.16.0` AND `appwrite: ^25.2.0` — every app
  carries both SDKs today.

**What cairn_flutter needs to work** (`/Volumes/developer_ssd/Developer/cairn/sdk/cairn_flutter`, 0.1.0, `publish_to` none):
- `flutter_rust_bridge: 2.13.0-beta.5` (+ `flutter_rust_bridge_hooks`), native-assets
  `hook/build.dart` + `prebuilt.json` (prebuilt lib, cargo fallback) — consumers need no
  Rust toolchain, but they DO inherit a beta-pinned FRB hook.
- Three entry points in `lib/src/cairn_database.dart`:
  - `CairnDatabase.open({sqliteDir, …})` — local-only, no server (free users).
  - `CairnDatabase.connect({url, sqlitePath, …})` — sync to a cairn server.
  - `CairnDatabase.supabase({cairnUrl, sqlitePath, …})` — Supabase-auth bridge:
    rotated Supabase JWTs are forwarded via `Cairn.setToken` without reconnect.
- Sign-out hooks (push token deregistration is one), attachments, `predicate.dart`
  (structured predicates already exist in-tree), `schema.dart`.
- It already deps `supabase_flutter: ^2.8.0` — resolves fine against kit's `^2.16.0`.
- Server-side contract: counter/or-set columns must match `CAIRN_COUNTER_COLUMNS` /
  `CAIRN_OR_SET_COLUMNS` or writes fail loudly (audit finding, still open).

## Decision: separate package `kit/cairn` (`arxa_kit_cairn`), NOT more adapters inside kit/data

Why deviate from the supabase precedent:
1. **Native payload.** cairn_flutter ships a native library through a beta-versioned
   build hook. Folded into kit/data, every arxa app — including supabase-only ones —
   compiles and carries it. supabase/appwrite are pure-Dart, so the precedent never had
   this cost.
2. **Churn isolation.** cairn is pre-1.0 and moving (DX redesign incoming); kit/data is
   the stable heart of every app.
3. **Licensing/positioning.** cairn is an arxa digital solutions product distributed
   separately from the kit; a dedicated package keeps that boundary auditable.

Consequence: kit/data cannot name cairn types (Dart has no optional deps), so kit/data
gains one small seam and arxa_kit_cairn plugs into it.

## Phase 1 — plugin seam in kit/data (small, backward-compatible)

- New: `abstract interface class ArxaKitBackendPlugin` in kit/data:
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
- `ArxaKitDataBackend` gains `.plugin`; `ArxaKitDataConfig` gains `ArxaKitBackendPlugin?
  plugin` and `validate()` enforces it exactly like supabase credentials.
- `ArxaKitData.initialize` switch gains `case ArxaKitDataBackend.plugin: await
  config.plugin!.initialize(…)`. Built-ins untouched.

## Phase 2 — `kit/cairn` package scaffold

- `kit/cairn/pubspec.yaml` — `arxa_kit_cairn`, deps: `arxa_kit_core`, `arxa_kit_data`
  (for the seam + schema types), `cairn_flutter`.
- **Dependency strategy for cairn_flutter**: the cairn repo is now PUBLIC at
  https://github.com/unfazed-dev/cairn (verified fetchable via `git ls-remote`,
  2026-08-26) — use a git dependency pinned to a commit, emulating a pub.dev package
  until cairn ships real distribution packages:
  ```yaml
  cairn_flutter:
    git:
      url: https://github.com/unfazed-dev/cairn.git
      ref: 8d72c94e14174725f1b0c91b2f0bfe70f91bc077   # pin a SHA, bump deliberately
      path: sdk/cairn_flutter
  ```
  - Pin the full SHA, not a branch — HEAD today is `8d72c94` (2026-08-24). The
    `v0.1.0` tag (`d64e9a4c…`) predates the recent push/DX work; do not use it.
  - Bumps are one-line PRs; each bump note records what changed in `hook/` and the
    FRB pin (see risk 1).
  - When cairn publishes to pub.dev, the git block collapses to a version constraint —
    nothing else in the kit changes.
  - No vendoring: the previous vendor-dir approach is dead; a git pin gives the same
    reproducibility without a sync script.
- Exports: a single `arxa_kit_cairn.dart` barrel. Nothing from `cairn_flutter` is
  re-exported except through kit types.

## Phase 3 — config + env (the "everything needed for cairn to work" surface)

```dart
enum ArxaKitCairnMode { localOnly, sync, supabaseBridge }

class ArxaKitCairnConfig {
  final ArxaKitCairnMode mode;
  final String? syncUrl;        // ws(s)://…/sync — required for sync/supabaseBridge
  final String? sqliteDirOverride; // default: path_provider app-support dir
  final bool push;              // opt into push token registration
  const ArxaKitCairnConfig({...});

  /// dart-define surface — the only env contract apps ever see:
  ///   ARXA_CAIRN_MODE = local | sync | supabase   (default: local)
  ///   ARXA_CAIRN_URL  = wss://…/sync              (required unless local)
  ///   ARXA_CAIRN_PUSH = true|false                (default: false)
  factory ArxaKitCairnConfig.fromEnvironment() => ...;

  void validate();   // StateError with the exact missing define, mirroring kit/data
}
```

- Tokens are NEVER env: `supabaseBridge` pulls session JWTs from the kit's
  `ArxaKitAuthService` (which wraps supabase auth) and feeds `CairnDatabase.supabase`'s
  rotation path; `sync` mode takes a token provider callback.
- localOnly (free users, no database): `CairnDatabase.open` — zero env, zero server,
  identical app code. This is the decision recorded earlier in the session: free arxa
  users must work exactly like database-backed users.

## Phase 4 — the backend plugin + adapters

- `ArxaKitCairnBackend implements ArxaKitBackendPlugin`:
  - opens the right `CairnDatabase` per mode; owns its lifecycle + `dispose`.
  - registers `CairnKitRepository<E>` for every `ArxaKitEntityRegistration` (adapter as
    designed in `docs/cairn/warehouse-inventory-arxa-cairn-example.md` — getById→
    fetchById, watchAll→watchMapped, patch→column-diff LWW, upsertMany→writeBatch).
  - registers `ArxaKitCairnStorageService` over cairn attachments (kit storage seam).
  - `supabaseBridge` mode: reuses the existing `ArxaKitSupabaseAuthService` — auth stays
    a kit/data concern; the plugin only subscribes to token rotation.
- CRDT verbs without hard casts: `abstract interface class ArxaKitCrdtCapable { Future<void>
  adjustCounter(...); Future<void> orSetAdd/Remove(...); }` implemented by
  `CairnKitRepository`; repository services feature-detect (`repo is ArxaKitCrdtCapable`).
- Schema: one declaration drives all backends. kit/data's `ArxaKitTableSchema` already
  emits SQL/appwrite.json — add a cairn emitter in arxa_kit_cairn:
  `CairnSchemaEmitter.tableFor(schema)` → `CairnTable` + a generated server-side
  declaration snippet (`CAIRN_COUNTER_COLUMNS`/or-set) so client and server cannot drift
  silently. Counter/or-set tiers come from new optional flags on the kit column
  descriptor (`crdt: counter|orSet`), ignored by other emitters.
- Push: `push: true` registers the device token through cairn's API after auth, and the
  existing sign-out hook deregisters it. Surface it behind the kit notifications
  package seam, not as a new public API.

## Phase 5 — proof

- **Contract tests**: extract kit/data's repository behavior tests (seed backend already
  proves the contract) into a shared `arxa_kit_data/lib/arxa_kit_testing.dart` runner;
  run the same suite against `ArxaKitCairnBackend(localOnly)`. Patch-survives-concurrent-
  edit and counter-merge get cairn-specific additions.
- **Showcase smoke**: showcase_app boots with `--dart-define=ARXA_CAIRN_MODE=local` and
  the notes feature round-trips CRUD; nothing above the seam changed.
- **Live proof**: reuse cairn's own fixture tooling
  (`fixtures/flutter/todo/tool/cairn_live_up.sh` — docker PG + cairn dev) for one
  integration test in sync mode.

## Phase 6 — DX-redesign alignment (deferred, tracked)

- `predicate.dart` already exists in cairn_flutter; when the redesign ADR lands
  (query builder / `computed` / `.diffs()`), only `CairnKitRepository` internals and the
  facade guidance change — the plugin seam, config, and app code hold still. Covered by
  the appendix of the warehouse example doc.

## Open questions / risks

1. **FRB beta pin** — `flutter_rust_bridge 2.13.0-beta.5` hook versions travel with the
   pinned git SHA automatically, but each SHA bump must check whether the FRB pin or
   `hook/build.dart`/`prebuilt.json` changed — prebuilt-binary availability for the new
   rev is what makes consumers Rust-toolchain-free.
2. **Public-repo exposure** — the git dep means every arxa app build clones the public
   cairn repo; CI needs no auth, but builds now depend on GitHub availability (same
   trade-off as any pub.dev git dep; acceptable as the stated stopgap).
3. **Web**: cairn_flutter has a `web/` engine; kit apps targeting web need a decision
   (in scope for the emitter/config, out of scope for phase-1 proof).
4. **Tauri parity** (arxa studio itself): cairn_tauri is a scaffold — this kit is
   Flutter-only by design; studio uses the separate cairn integration plan.
5. **Auth in pure-cairn mode**: cairn identity is a bearer JWT; until cairn has its own
   arxa-grade auth story, `sync` mode assumes the host supplies tokens (agency
   deployments), `supabaseBridge` is the arxa-default, `localOnly` needs none.

## Execution order

1. Phase 1 seam in kit/data (blocks everything, tiny).
2. Phase 2 scaffold + git-pinned cairn_flutter dep.
3. Phase 3 config, Phase 4 repository adapter + emitter (parallelizable).
4. Phase 5 contract tests, then showcase smoke, then live proof.
5. Phase 4 push + storage after CRUD proof, Phase 6 deferred.
