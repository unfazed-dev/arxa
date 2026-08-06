# appbox_kit_data

The data layer for `appbox_kit` apps: generic repositories over one
**Backend** at a time — seed (fixture-backed, in-memory), Supabase, or
Appwrite — selected at runtime by `AppBoxKitDataConfig`, with deterministic
canonical IDs, Dart schema descriptors that generate every backend's SQL/JSON
artifacts, and rxdart facade services that compose repositories into UI
state.

End-to-end UI → backend data-flow diagrams: `docs/plans/appbox-kit-data-flow-diagrams.md`.

Vocabulary (Backend, Fixture, Seed Key, Canonical ID, Schema Descriptor,
Repository, Facade Service, Codec, Seeder, Operator) lives in the host
project's `CONTEXT.md` — use those terms, not synonyms.

## Layering

```
View → ViewModel → Facade Service → Repository → Backend
```

- **Repository** (`AppBoxKitRepository<T>`) is the swap seam: one interface,
  three backend implementations (`AppBoxKitSeedRepository`, `AppBoxKitSupabaseRepository`,
  `AppBoxKitAppwriteRepository`). No codegen.
- **Facade Service** (`AppBoxKitDataFacade` subclass) is the only layer ViewModels
  talk to. It composes repositories into derived streams and routes
  mutations through `AppBoxKitAction` via `mutate(...)`.
- Only one Backend is active per app run, chosen by `AppBoxKitDataConfig.backend`
  (default `AppBoxKitDataBackend.supabase`).

## Quickstart

**1. Dependency.** Add the package as a path dep, and copy its `win32 ^6`
override into the host's own `pubspec.yaml` — pub overrides don't propagate:

```yaml
dependencies:
  appbox_kit_data:
    path: ../appbox_kit/data

# appwrite's transitive graph pins win32 5.x while appbox_kit → talker_flutter
# → share_plus 13 needs win32 ^6. win32 is Windows-only FFI — forcing 6.x is
# inert on iOS/Android/web/macOS.
dependency_overrides:
  win32: ^6.0.1
```

**2. Register entities.** One `AppBoxKitEntityRegistration<T>` per model — a plain
model + `fromJson`/`toJson`. Storage mapping lives on the `AppBoxKitTableSchema`,
never on the model:

```dart
final productRegistration = AppBoxKitEntityRegistration<Product>(
  schema: productsSchema,
  fromJson: Product.fromJson,
  toJson: (p) => p.toJson(),
);
```

**3. Initialize.** Call `AppBoxKitData.initialize` in `main()`, after
`setupLocator()`:

```dart
// Seed — nothing to configure.
await AppBoxKitData.initialize(
  config: const AppBoxKitDataConfig(backend: AppBoxKitDataBackend.seed),
  entities: [productRegistration, categoryRegistration],
  fixtureAssets: ['assets/seed/products.json', 'assets/seed/categories.json'],
);

// Supabase (default backend) — just swap the config:
config: const AppBoxKitDataConfig(
  supabase: AppBoxKitSupabaseConfig(url: '...', publishableKey: '...'),
),

// Appwrite:
config: const AppBoxKitDataConfig(
  backend: AppBoxKitDataBackend.appwrite,
  appwrite: AppBoxKitAppwriteConfig(endpoint: '...', projectId: '...', databaseId: '...'),
),

final products = appBoxKitLocator<AppBoxKitRepository<Product>>();
```

`AppBoxKitData.initialize` registers one `AppBoxKitRepository<T>` per entity into the
shared `StackedLocator.instance`. The kit never self-registers — the host
owns the call.

## Fixtures and Canonical IDs

Fixtures are hand-authored JSON under `assets/seed/<table>.json`, one file
per table, keyed by human-readable **Seed Keys** (`"id": "p-1"`). At load
time `AppBoxKitIdService` turns every Seed Key — and every reference column
pointing at another table — into a deterministic UUID v5 of `'<table>:<key>'`
(ADR-0001: `docs/adr/0001-deterministic-v5-canonical-ids.md`). The same
fixture therefore yields byte-identical **Canonical IDs** on the seed
Backend, Supabase, and Appwrite: `p-1` always resolves to the same UUID,
which is valid as a Postgres `uuid` primary key and as an Appwrite row ID.
Seed Keys never leave the seeding path — storage only ever sees Canonical
IDs. Repository reads canonicalize `eq` filters too, so
`AppBoxKitQuery(filters: [AppBoxKitFilter.eq('category', 'cat-1')])` resolves `'cat-1'`
the same way a row reference would.

## Snapshot persistence

The seed Backend is a hybrid: an in-memory reactive core (one
`BehaviorSubject` per table) plus pluggable write-through persistence via
`AppBoxKitDataConfig.seedPersistence`:

- `AppBoxKitSeedPersistenceMode.none` (default) — pure in-memory, every boot
  reloads Fixtures fresh.
- `AppBoxKitSeedPersistenceMode.snapshot` — writes through to a JSON file per
  table under the app-documents directory. Boot resolves precedence
  **per table**: a table the snapshot has ever persisted comes from the
  snapshot (including a deliberately-empty `{}` — user deletions survive
  reboot), and a table the snapshot has never seen comes from Fixtures.
  Snapshots are written per table, so a partial snapshot is normal — e.g.
  the seed auth service write-throughs only `kit_auth_users` on first boot.
  Delete the snapshot directory to reset.

## Generating operator artifacts

Schema Descriptors (`AppBoxKitTableSchema`) are the single source of truth. Three
emitters turn them into per-backend artifacts — see `example/generate.dart`
for the full pattern (`dart run example/generate.dart` from this package's
directory):

- `AppBoxKitSupabaseSqlEmitter().emit(schemas)` → migration SQL (`CREATE TABLE`,
  UUID PKs, foreign keys, `jsonb` columns).
- `AppBoxKitSupabaseSeedEmitter(idService:).emit(fixturesByTable:, schemasByTable:)`
  → `seed.sql` (`INSERT ... ON CONFLICT (id) DO UPDATE`).
- `AppBoxKitAppwriteJsonEmitter().emit(schemas:, databaseId:)` →
  `appwrite.tables.json`, a tables fragment for the Appwrite console/CLI.

Never hand-edit the generated SQL or JSON — change the Schema Descriptor and
regenerate.

## Seeding a remote backend

Once the migration/tables fragment exists on the remote Backend, push the
same Fixtures at runtime with the Seeder:

```dart
await AppBoxKitDataSeeder().push(
  fixtureAssets: ['assets/seed/products.json', 'assets/seed/categories.json'],
);
```

Idempotent by construction — Canonical IDs are deterministic, so every push
upserts the same rows in reference order (referenced tables before their
dependents). Throws if the active backend is `AppBoxKitDataBackend.seed` (it loads
Fixtures itself at `initialize`).

## Auth

The identity seam — sign-in/sign-out and the Session stream — lives beside
the repositories, not inside them: `AppBoxKitAuthService` is one interface with
three implementations (`AppBoxKitSeedAuthService`, `AppBoxKitSupabaseAuthService`,
`AppBoxKitAppwriteAuthService`), selected by the same `AppBoxKitDataConfig.backend`.
Enable it by adding an `auth:` config; leave it off and no Auth Service is
registered.

```dart
await AppBoxKitData.initialize(
  config: const AppBoxKitDataConfig(
    supabase: AppBoxKitSupabaseConfig(url: '...', publishableKey: '...'),
    auth: AppBoxKitAuthConfig(googleServerClientId: '...'),
  ),
  entities: [productRegistration, categoryRegistration],
);

// Facade services see it as `auth`; anything else resolves it directly.
class ProfileFacade extends AppBoxKitDataFacade {
  Stream<AppBoxKitAuthSession?> get session$ => auth.session$;

  Future<void> signIn(String email, String password) => mutate<AppBoxKitAuthSession>(
        () => auth.signInWithEmailPassword(email: email, password: password),
        name: 'signIn',
        error: 'Sign-in failed',
      );
}

final authService = appBoxKitLocator<AppBoxKitAuthService>();
```

**Fake Auth pairs ONLY with the Seed Backend.** Supabase RLS keys on
`auth.uid()` and Appwrite rows are default-deny, so a Session minted by
`AppBoxKitSeedAuthService` is a client-side fiction against either real Backend —
storage rejects it. Smoke-test a real Backend with `signInAnonymously()`
(a genuine server-issued Session on both Supabase and Appwrite) or an
Operator-seeded test user, never Fake Auth.

Fake Auth mechanics: fake users live in the reserved `kit_auth_users` table
inside the seed store — not a registered entity, so the emitters and Seeder
never touch it, but it's snapshot-persisted like any other table. Optionally
pre-seed it via `AppBoxKitAuthConfig.fakeUsersAsset`; unregistered identities are
auto-created on sign-in either way. Every sign-in method resolves an identity
rather than authenticating one — any password, any OTP code (`000000` is
conventional) succeeds. A data Fixture's `"owner": "user-1"` lines up with
the Session from signing in as that identity's email, because both resolve
through the same `AppBoxKitIdService.canonicalId('kit_auth_users', ...)`.

OTP is two-step — `requestOtp({email, phone})` then
`confirmOtp({email, phone, code})` — matching both real backends' own
two-step flows (Supabase `signInWithOtp` → `verifyOTP`; Appwrite
`createEmailToken`/`createPhoneToken` → `createSession`).

Per-backend Operator notes:

- **Supabase Google** — native `google_sign_in` v7 flow, needs
  `AppBoxKitAuthConfig.googleServerClientId`; configure Android SHA fingerprints
  and the iOS URL scheme per Google's console instructions. Supabase's own
  guide still documents the pre-v7 API (supabase/supabase#36775) — verify
  against installed source.
- **Supabase Apple** — enable the "Sign in with Apple" capability in Xcode +
  the Apple Developer portal; the nonce round-trip is handled inside the kit.
- **Appwrite OAuth** (Google + Apple) — a browser flow via the
  `appwrite-callback-<PROJECT_ID>` URL scheme; register that scheme per
  platform and enable/configure each provider in the Appwrite console.
- **Appwrite user ids** — email/OTP sign-ups get a Canonical ID as their
  `userId` from creation. OAuth/anonymous sign-ins get an Appwrite-assigned
  `$id`; `AppBoxKitAuthUser.id` is a stable, deterministic Canonical-ID derivation
  of that `$id` — but it is NOT the same string as `$id`, so server-side
  permission rules keyed on the raw `$id` won't match it.

## Swap rules

1. Repositories are stream-backed from their source; `BehaviorSubject`s live
   only in the seed store and in Facade Services — never double-buffer a
   reactive source, and never put one in a repository.
2. Every repository method is single-table `eq`/`gt`/`lt`/`order`/`limit` —
   no joins, no aggregates (those are Facade `.map()` work). Nested
   collections are `jsonb` columns, never child tables.
3. Singleton rows are `Stream<T?>`; collections are `Stream<List<T>>`.
4. The kit never self-registers and never imports the host — `main()` calls
   `AppBoxKitData.initialize` explicitly, matching `appbox_kit`'s contract.

## Further reading

- Architecture and locked decisions: `docs/plans/appbox-kit-data-layer.md`
- Auth seam decisions: `docs/plans/appbox-kit-data-auth.md`
- Vocabulary: `CONTEXT.md`
- Canonical ID derivation: `docs/adr/0001-deterministic-v5-canonical-ids.md`
- Kit-wide skill (patterns, rules, host-integration contract):
  `core/skill/SKILL.md` → **Data layer (appbox_kit_data)**
