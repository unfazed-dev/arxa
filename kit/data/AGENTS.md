# data/ — AGENTS.md

Nested schema for the data layer. Repo-wide contract: `../AGENTS.md`; deep
reference: `data_playbook.mdx`; vocabulary (Backend, Fixture, Seed Key,
Canonical ID, Schema Descriptor, Repository, Facade Service, Codec, Seeder,
Operator): the host project's `CONTEXT.md` — use those terms, not synonyms.
This file owns the data-layer contract.

## The contract

- **Schema Descriptor is the single source of truth.** One `ArxaKitTableSchema`
  per table (`lib/schema/arxa_kit_table_schema.dart`) drives fixture validation,
  the seed store, and the emitters. Storage mapping lives on the schema,
  **never on the model** — a model is plain Dart plus its Codec
  (`fromJson`/`toJson`), registered as one `ArxaKitEntityRegistration<T>`.
- **Layering:** `View → ViewModel → Facade Service → Repository → Backend`.
  The `ArxaKitDataFacade` subclass is the only layer ViewModels talk to; it
  composes repositories into derived streams and routes writes through the
  KitAction hub via `mutate(...)` (hot send — the returned future is
  an observation handle). `ArxaKitRepository<T>` is the swap seam — one
  interface, three implementations (seed / Supabase / Appwrite), no codegen.
  Writes: `upsert` for creates, **`patch(original, patched)` for every
  mutation of an existing row** — only the columns that differ (codec
  wire-shape diff) hit storage, so a concurrent edit to another column is
  never clobbered by a full-row write.
- **`ArxaKitQuery` stays deliberately tiny** (`lib/query/arxa_kit_query.dart`): eq/gt/lt
  filters + orderBy + limit — every operator satisfiable single-table on all
  three backends. **Joins and aggregates are facade work** (`.map()` over
  streams), never query work. Nested collections live in `jsonb` columns,
  never child tables.
- **Canonical IDs are deterministic UUIDv5** (`lib/ids/arxa_kit_id_service.dart`,
  ADR-0001): anything not already a UUID becomes
  `uuid.v5(namespace, '<table>:<key>')`, so one fixture yields byte-identical
  PKs on every backend and re-seeding is idempotent. The namespace is
  load-bearing — changing it orphans every stored row.
- **Fixtures carry Seed Keys** (human-readable, e.g. `p-1`); the
  `ArxaKitIdService` canonicalizes them. The **Seeder**
  (`lib/seeding/arxa_kit_data_seeder.dart`) pushes the same fixtures to the remote
  backend — idempotent upserts in reference order; it refuses the seed
  backend (fixtures load themselves at initialize).
- **Backend swap is config, not code:** `ArxaKitDataConfig.backend`
  (`lib/config/arxa_kit_data_config.dart`) — exactly one of seed / Supabase
  (default) / Appwrite active per run. The host calls `ArxaKitData.initialize`
  once in `main()` after `setupLocator()`; the kit never self-registers.
- **Seed Profiles are config too:** `ArxaKitDataConfig.seedProfile`
  (`lib/config/arxa_kit_seed_profile.dart`) — latency/failure injection applied
  by every `ArxaKitSeedRepository` (`ArxaKitSeedProfile.slow` / `.failing`, typed
  `ArxaKitSeedException`; default is a pass-through). The host owns the profile
  names, the fixture selection (`empty` = an empty fixture list), and any
  persona sign-in after boot; `ArxaKitSeedAuthService` bypasses injection (it
  reads the store directly, never through repositories).
- **Generated artifacts are never hand-edited.** The emitters
  (`lib/emitters/`) render Supabase migration SQL, Supabase seed SQL, and the
  Appwrite `appwrite.json` tables fragment from schemas — each output is
  stamped "Do not edit by hand". Edit the schema, regenerate
  (`dart run example/generate.dart`, see `example/generated/`).

## Gotchas that bite

- Files defining a `ArxaKitTableSchema` or `ArxaKitEntityRegistration` use **targeted
  imports, never the barrel** — the barrel re-exports the Supabase/Appwrite
  adapters, whose FFI deps crash the pure-Dart kernel compile inside
  `dart run` generators.
- The host's `pubspec.yaml` must mirror the kit's `dependency_overrides`
  (`win32`, `device_info_plus`, `package_info_plus`) — pub overrides don't
  propagate.
- Sign-in backends live here temporarily (fold into `arxa_kit_auth`
  planned, Phase 4 — see `../kit_matrix.md` §4); use `as`-prefixed imports if
  both kits are needed.

## Testing

`lib/arxa_kit_testing.dart` ships `FakeArxaKitRepository<T>` + `FakeArxaKitDataFacade`;
`ArxaKitMemoryAssetReader` (`lib/assets/arxa_kit_asset_reader.dart`) injects fixture
JSON with no Flutter binding, and `ArxaKitData.resetForTesting()` clears the
composition root between cases. Prefer real components over scripted mocks —
a real `ArxaKitSeedStore` backed by `ArxaKitNoPersistence` is the usual substrate;
assert on stream emissions and `tableSnapshot` rows, not mock call-counts.
