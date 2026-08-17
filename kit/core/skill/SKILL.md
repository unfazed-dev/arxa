---
name: appbox-kit
description: Use when working on a Flutter app that depends on `appbox_kit`, or when integrating the kit into a new Stacked project, or when creating ANY app/view/service/sheet/dialog/widget in a kit app (Stacked CLI only — `stacked create …` / `stacked generate`, never `flutter create` or hand-rolled files). Reach for it to run async operations with loading/error/success/retry/streaming/cancellation via KitAction (`KitAction.run(...).withLoading(...).execute()`); log errors and events via KitErrorService (Talker-backed); trigger haptics; persist and react to ThemeMode; show transient feedback (toast/snackbar) via `KitNotificationService`; show blur overlays (`withOverlay`) or multi-select UI (`withSelectable`); use the kit's formatters and design tokens; or wire the sibling data layer (`appbox_kit_data`) via KitDataConfig, KitRepository, KitDataFacade, KitDataSeeder, seed data, fixtures, supabase, appwrite; or wire its auth seam via KitAuthService/KitAuthConfig for fake auth, sign in, OTP, google sign-in, or apple sign-in. Triggers — KitAction, KitErrorService, KitHapticService, KitThemeService, KitNotificationService, KitOverlayService, KitSelectableService, KitDataConfig, KitRepository, KitDataFacade, KitDataSeeder, KitAuthService, KitAuthConfig, "fake auth", sign in, OTP, google sign-in, apple sign-in, appbox_kit, appbox_kit_data, "add the kit to this project", "add a data layer".
---

# appbox_kit

A reusable Stacked MVVM toolkit, consumed as a path or git package. The kit owns
**generic infrastructure and the default Material 3 theme** (palette +
light/dark `ThemeData` + `ThemeMode` state); the host app owns **domain code
and UI registration**. The kit has zero knowledge of any host — no app imports,
no hardcoded project references, no host-specific colors. Its theme is a generic
default any host can use as-is or override.

```dart
import 'package:appbox_kit/appbox_kit.dart';
```

## When to use

Use this skill any time you touch a Stacked app with `appbox_kit` in its
pubspec, especially when:

- A ViewModel action loads data or calls an API → wrap it in **KitAction** for loading state, error handling, success/error snackbars, retry, timeout, streams, and cancellation in one fluent chain.
- You need centralized, reactive error logging or event tracking → **KitErrorService** (Talker-backed; streams for latest error, unread count, per-widget errors/loading).
- Triggering haptics, persisting/reacting to theme mode, showing a blur overlay, or building a multi-select list.
- A widget should render real Liquid Glass (iOS 26) or Material 3 Expressive (Android), with a Flutter fallback elsewhere → use a **KitNative\*** widget; see **Native chrome**.
- Adopting `appbox_kit` into a fresh Stacked project → follow **Host integration**.

## Building on the kit — Stacked CLI only (no flutter CLI)

**Every structural artifact in a kit app is created by the Stacked CLI, never by
hand and never with `flutter create`.** The CLI's whole value is auto-wiring:
routes, locator registration, mocks, tests. Hand-copying files (or `cp -R`
porting) silently loses all of it — this rule exists because that exact
violation happened during the showcase-app port and had to be redone.

| Artifact | Command | What auto-wires |
|---|---|---|
| App | `stacked create app <name> --template=web --platforms=ios,android,web --org=com.<org>` | full scaffold + `stacked.json` + startup/home/unknown views + sheets/dialogs + test harness |
| View | `stacked create view <name> [name…]` | `lib/ui/views/<name>/` — view + **`.mobile`/`.tablet`/`.desktop` variants** (with `prefer_web: true`) + viewmodel + `test/viewmodels/<name>_viewmodel_test.dart` + route & import in `app.dart` (skip with `--exclude-route` for nested-shell children) |
| Service | `stacked create service <name>` | `lib/services/<name>_service.dart` + test + `LazySingleton` in `@StackedApp` + `MockSpec` + register/create in `test/helpers/test_helpers.dart` |
| Sheet / dialog / widget | `stacked create bottom_sheet\|dialog\|widget <name>` | file + model + test + `BottomSheetService`/`DialogService` registration |
| Codegen | `stacked generate` | wraps `build_runner build --delete-conflicting-outputs` — never call build_runner directly |

Verified mechanics (stacked_cli 1.15.5, 2026-07-12):

- `stacked create app` internally runs **`flutter create -e`** then overlays the
  Stacked template — so the iOS project inherits Flutter's
  `IPHONEOS_DEPLOYMENT_TARGET = 13.0`. `cupertino_native_better` needs **15.0**;
  bump it immediately after scaffolding (×3 in
  `ios/Runner.xcodeproj/project.pbxproj`) or the first iOS build fails on
  Target Integrity. The CLI has no flag for it.
- Auto-editing only works while the **template identifiers** survive in
  `app.dart` / `test_helpers.dart`: `// @stacked-import`, `// @stacked-route`,
  `// @stacked-service`, `// @stacked-bottom-sheet`, `// @stacked-dialog`,
  `// @stacked-mock-spec`, `// @stacked-mock-register`, `// @stacked-mock-create`.
  Never delete them.
- The CLI scaffold pins stale deps (`stacked_generator` 1.x, `flutter_lints` 2.x,
  discontinued `golden_toolkit`/`url_strategy`) — upgrade after scaffolding.
- Nested shell routes (IndexedStack tabs): create child views with
  `--exclude-route`, then hand-place their `CustomRoute` inside the shell's
  `children:` in `app.dart` and run `stacked generate`. Route-tree layout is
  normal development; file creation is not.
- **Folder structure mirrors the host app** (`p2/lib/ui/views` is the
  reference): every shell is a full CLI view folder (`<name>_shell/`, 4-file
  variant set + viewmodel — never an inline outlet class), and leaf views are
  moved to nest inside their shell's folder
  (`showcase_notes_shell/showcase_notes_folder/…`, like the host's
  `account_shell/account_home/`).
  Viewmodel tests stay flat in `test/viewmodels/`. Keep the scaffold's
  startup view (boot logic in `runStartupLogic()` → `replaceWith(...)`), a
  thin `main()`, and `app.dart` at `lib/app/app.dart`.
- **Showcase naming convention**: every showcase-app view (startup and unknown
  included), the shared widgets in `lib/ui/widgets/common/`, and the root
  widget in `main.dart` are `showcase_`-prefixed (`showcase_startup` /
  `ShowcaseStartupView`, `showcase_notes_shell`, `ShowcaseApp`) so showcase
  artifacts are always distinguishable from any other app's. Pass the prefixed
  name to `stacked create view`. CLI-template boilerplate keeps its canonical
  names (notice sheet, info_alert dialog; `main.dart` filename is fixed by
  Flutter). There is **no local `lib/ui/common/`**: delete the CLI-template
  `app_colors`/`app_strings`/`app_constants`/`ui_helpers` files and import
  colors, spacing helpers, constants, glyphs, and fonts from
  `package:appbox_kit_core/common/…` instead.
- **Documented exceptions** (the CLI has no verb for these — hand-author):
  a `KitDataFacade` subclass body (create the service via
  `stacked create service`, then make it `extends KitDataFacade`), entity
  models + `KitTableSchema`/`KitEntityRegistration`, and plain shared widget
  files (put those in `lib/ui/widgets/common/`; never recreate
  `lib/ui/common/` — kit-core `common/` owns colors/helpers/constants).

Reference template + full step-by-step: `showcase_app` and
`docs/plans/appbox-kit-showcase-app-port.md` §7.

## The kit's surface

| Layer | Entry point | Notes |
|---|---|---|
| Operations | `action(name, () => ...)` helper from the `KitActionOwner` mixin (`KitViewModel`, `KitDataFacade`) → `utils/kit_action/kit_action.dart` | Awaitable fluent builder (await = execute; `.execute()` only for fire-and-forget); owner-identity keys + auto-dispose; `.toStream()` / `.toCancellable()` single-call terminals |
| Notifications | `KitNotificationService.show(msg, {kind, position, actionLabel, …})` → `services/notifications/kit_notification_service.dart`; `KitNotificationKind`/`KitToastPosition`; snackbar vocab `KitSnackbarType.kitAutoProcess{Info,Success,Error,Warning}` → `kit_snackbar_type.dart`; `setupKitSnackbars()` → `kit_snackbar_setup.dart` | One entry point picks the native surface per platform (see **Transient feedback**); host registers the service + calls `setupKitSnackbars()` |
| Services | `services/{error,haptics,theme,navigation,notifications}/` + `KitOverlayService`/`KitSelectableService` (defined in their extensions) | Resolved via `locator` |
| Theme | `KitColors` / `KitDarkColors` + `kitLightTheme()` / `kitDarkTheme()` → `common/kit_colors.dart`; `KitThemeService` owns `ThemeMode` + status bar | Generic default; host passes builders to `MaterialApp` |
| Extensions | `extensions/` — `withHapticFeedback`, `withOverlay`, `withSelectable`, hover effects, `context.dismissKeyboard`, `String.toTitleCase` | All `on Widget` / `BuildContext` / `String` |
| Native chrome | `KitNative*` widgets → `widgets/kit_native_*.dart` (tab bar, button, icon button, segmented control, split button, FAB, FAB menu, popup menu, search bar, switch, slider, range slider, app bar + sliver, toolbar, navigation rail, loading indicator, progress, glass card) + function helper `kitShowNativeSheet()` (transient feedback is `KitNotificationService.show()`, not a widget); primitives `KitMenuItem` / `KitToolbarAction` / `KitRailDestination`; `KitNativeComponent` → `enums/`; gate `KitPlatform`; matrix `NATIVE_COMPONENTS.md` | Liquid Glass iOS 26 (`cupertino_native_better`) / M3E Android (`m3e_collection`), Flutter fallback elsewhere; explicit per-component widgets (not a `.native()` helper) |
| Utils | `utils/` — `kit_time_utils`, input formatters (email/mobile/OTP), mouse-transforms; `common/kit_app_constants` (design tokens) | Pure, drop-in |
| Locator | `kit_locator.dart` exports `locator` = `StackedLocator.instance` | Same singleton the host registers into |

## Transient feedback (KitNotificationService)

One service — `KitNotificationService.show(message, {kind, position, duration, context, actionLabel, onAction, title, variant})` — picks the right native surface per platform. **Use it for every toast/snackbar**; do not call `SnackbarService` or `CNToast` directly (the old `kitShowNativeToast()` helper was deleted).

Routing in `show()`:
- **Android** (`KitPlatform.supportsComposeM3E`) → host `SnackbarService` (native Material `ScaffoldMessenger`), wrapped in `withNativeChromeHidden`.
- **iOS / desktop, no `actionLabel`** → `CNToast` (Flutter-drawn capsule on every OS — the vendor's glass tier is disabled, `docs/liquid-glass-allowlist.md` rule 12). Default — **no snackbar on iOS unless an action is required**.
- **iOS / desktop, with `actionLabel`** → `SnackbarService` fallback (CNToast can't host an action button). `actionLabel` is the ONLY thing that promotes iOS from toast to snackbar.

- `kind` (`KitNotificationKind`) drives the CNToast preset (iOS: `info`/`success`/`error`/`warning` — `warning` is the yellow/orange `CNToast.warning`, NOT info-blue) and the snackbar variant (Android: mapped to `KitSnackbarType.kitAutoProcess{Info,Success,Error,Warning}`).
- `position` (`KitToastPosition` top/center/bottom, default `top`) places the iOS CNToast; ignored on the snackbar tiers (always bottom-anchored). **Center render note:** CNToast's center branch must pin all four edges (`top=0; bottom=0;`) so the Overlay lays it out as a real `Positioned` child — with both null it paints nothing (top/bottom work because each sets one edge). Fixed in `cupertino_native_better/lib/components/toast.dart`.
- `context` is honored on the iOS tier; null → falls back to `StackedService.navigatorKey`'s current context so context-less callers (KitAction) still render; pre-boot it debugPrints + no-ops rather than throwing.
- `variant` overrides the kind-derived snackbar variant (may be a host enum with a registered config).

Boot: register `KitNotificationService` as a `LazySingleton` in the host `@StackedApp` + run `build_runner`, and call `setupKitSnackbars()` in `main()` — it registers a `SnackbarConfig` per `KitSnackbarType` and sets `mainButtonTextColor: foreground` so action buttons stay legible on every variant (without it, stacked defaults button text to white, invisible on the pale warning bg). KitAction notifications (`NotificationManager` loading/success/error) route through this service → CNToast on iOS.

## Data layer (appbox_kit_data)

`appbox_kit_data` is a sibling package (`appbox_kit/data`, a path
dependency exactly like `appbox_kit` itself) that gives a Stacked host one
**Backend** at a time — seed (fixture-backed, in-memory), Supabase, or
Appwrite — chosen entirely by a runtime `KitDataConfig` passed to
`KitData.initialize` in `main()`; **supabase is the default**. `KitRepository<T>`
is the swap seam: one generic interface, three backend implementations, no
codegen, and host code never references a concrete implementation. Facade
Services (`KitDataFacade` subclasses) are the only layer ViewModels ever
see — they compose repositories into UI-facing streams and route mutations
through `KitAction` via `mutate(...)`.

```dart
import 'package:appbox_kit_data/appbox_kit_data.dart';
```

### The data layer's surface

| Layer | Entry point | Notes |
|---|---|---|
| Entry point | `KitData.initialize({required KitDataConfig config, required List<KitEntityRegistration<dynamic>> entities, List<String> fixtureAssets = const [], AssetBundle? bundle})` → `kit_data.dart` | Host calls this once in `main()`, after `setupLocator()`; registers one `KitRepository<T>` per entity for the configured backend into the shared locator. The kit never self-registers. |
| Config | `KitDataConfig({backend = KitDataBackend.supabase, supabase, appwrite, seedPersistence = KitSeedPersistenceMode.none, idNamespace})` → `config/kit_data_config.dart`; `KitDataBackend {seed, supabase, appwrite}`; `KitSeedPersistenceMode {none, snapshot}` | `.validate()` throws a `StateError` if the selected backend is missing its credential object (`supabase`/`appwrite`) |
| Repository | `KitRepository<T>` → `repositories/kit_repository.dart` — `getById(id)`, `getAll([KitQuery])`, `watchById(id)`, `watchAll([KitQuery])`, `upsert(entity)`, `upsertMany(entities)`, `delete(id)` | The swap seam. Three impls — `KitSeedRepository<T>`, `KitSupabaseRepository<T>`, `KitAppwriteRepository<T>` — are never referenced directly by host code, only through `KitRepository<T>` |
| Registration | `KitEntityRegistration<T>({required schema, required fromJson, required toJson})` → `models/kit_entity_registration.dart` | The Codec: binds `T` to its `KitTableSchema`. One per entity, passed to `KitData.initialize` |
| Schema | `KitTableSchema({required table, required columns})` + `KitColumn(name, type, {nullable, references})` → `schema/kit_table_schema.dart`; `KitColumnType {id, text, integer, real, boolean, timestamptz, jsonb, reference}` | The Schema Descriptor — single source of truth for fixture validation, the seed store, and the emitters |
| IDs | `KitIdService({String? namespace})` → `ids/kit_id_service.dart` — `canonicalId(table, key)`, `canonicalizeRow(schema, row)`, `canonicalizeQuery(schema, query)`, `isUuid(value)` | ADR-0001: deterministic UUID v5 of `'<table>:<key>'`; registered as a locator singleton by `KitData.initialize` |
| Facade | `KitDataFacade` → `facades/kit_data_facade.dart` — `repository<T>()`, `registerSubject(subject)`, `mutate<T>({required operation, op, entity, error, success})`, `dispose()` | The only layer ViewModels see; subjects registered via `registerSubject` get closed by `dispose()` |
| Seeder | `KitDataSeeder({KitIdService? idService, KitSchemaRegistry? registry}).push({required List<String> fixtureAssets, AssetBundle? bundle})` → `seeding/kit_data_seeder.dart` | Idempotent upsert of Fixtures into the active **remote** Backend; throws if `KitData.config.backend == KitDataBackend.seed` (the seed Backend loads Fixtures itself at `initialize`) |
| Emitters | `KitSupabaseSqlEmitter().emit(schemas)`, `KitSupabaseSeedEmitter(idService:).emit(fixturesByTable:, schemasByTable:)`, `KitAppwriteJsonEmitter().emit(schemas:, databaseId:)` → `emitters/` | Pure Dart — safe inside a `dart run` script. Schema Descriptors are the only input; never hand-edit the generated SQL/JSON |
| Auth | `KitAuthService` → `auth/kit_auth_service.dart` — `session$`, `currentSession`, `signUpWithEmailPassword({email, password})`, `signInWithEmailPassword({email, password})`, `requestOtp({email, phone})`, `confirmOtp({email, phone, code})`, `signInWithGoogle()`, `signInWithApple()`, `signInAnonymously()`, `signOut()`, `dispose()` | The identity seam, sibling to `KitRepository<T>` — NOT a repository. Three impls — `KitSeedAuthService`, `KitSupabaseAuthService`, `KitAppwriteAuthService` — selected by the same `KitDataConfig.backend`; see **Auth seam** below |
| Auth config | `KitAuthConfig({googleServerClientId, googleClientId, fakeUsersAsset})` → `config/kit_data_config.dart`; `KitDataConfig.auth` | Present ⇒ `KitData.initialize` registers a `KitAuthService` for the active backend; absent (default) ⇒ no auth is wired |

### Host integration (data layer)

1. **Dependency.** Add `appbox_kit_data` as a path dep. It pulls in the
   `win32 ^6` `dependency_overrides` the package itself needs — copy the same
   override into the host's own `pubspec.yaml` (pub overrides don't
   propagate): *"appwrite's transitive graph pins win32 5.x while appbox_kit
   → talker_flutter → share_plus 13 needs win32 ^6. win32 is Windows-only FFI —
   forcing 6.x is inert on iOS/Android/web/macOS."*
2. **Registration.** Declare one `KitEntityRegistration<T>` per entity — a
   plain model + `fromJson`/`toJson`. The wire contract lives on the model;
   storage mapping (table/columns/references) lives in the `KitTableSchema`,
   never in the model.
3. **Initialize.** Call `await KitData.initialize(...)` in `main()` **after**
   `setupLocator()` — the data layer registers `KitRepository<T>` instances
   into the same shared locator the rest of the kit uses.
4. **Fixtures.** Author `assets/seed/<table>.json` per table and declare them
   under `flutter: assets:` in `pubspec.yaml` — `KitData.initialize` and
   `KitDataSeeder.push` both load them via `rootBundle` by default.
5. **Operator flow, per Backend:**
   - **seed** — nothing to configure; fixtures load straight into memory.
   - **supabase** — supply `url` + `publishableKey`, then run the generated
     migration and `seed.sql` (produced by an example-style `dart run
     example/generate.dart` script) through the Supabase CLI.
   - **appwrite** — supply `endpoint`/`projectId`/`databaseId`, push the
     generated `appwrite.tables.json` fragment through the Appwrite console
     or CLI, then call `KitDataSeeder().push(fixtureAssets: [...])` to
     upsert the Fixtures at runtime.

### Patterns

```dart
// Facade: composes a repository into UI state; mutations route through KitAction.
class ShopFacade extends KitDataFacade {
  late final _products = repository<Product>();

  late final query$ = registerSubject(BehaviorSubject<String>.seeded(''));

  Stream<List<Product>> get visible$ =>
      Rx.combineLatest2(_products.watchAll(), query$, _filterByQuery);

  List<Product> _filterByQuery(List<Product> all, String query) => query.isEmpty
      ? all
      : all.where((p) => p.name.toLowerCase().contains(query.toLowerCase())).toList();

  Future<void> save(Product product) async {
    await mutate<Product>(
      () => _products.upsert(product),
      name: 'save',
      entity: product.id,
      error: 'Could not save',
      success: 'Saved',
    );
  }
}
```

- **Seed Key → Canonical ID.** A Fixture authors rows by Seed Key —
  `assets/seed/products.json` has `{"id": "p-1", "category": "cat-1", ...}` —
  and `KitIdService.canonicalId('products', 'p-1')` turns it into the *same*
  UUID v5 on every Backend (seed, Supabase, Appwrite): `p-1` always resolves
  to `ca5d7037-042d-51e2-86cf-cce64586ab8a` under the kit's default namespace.
  Storage never sees `p-1` — only the Canonical ID.
- **Query by Seed Key.** Repository reads canonicalize `eq` filters against
  the id/reference columns before hitting storage, so a caller can filter by
  Seed Key or Canonical ID interchangeably:
  `productRepo.getAll(const KitQuery(filters: [KitFilter.eq('category', 'cat-1')]))`
  resolves `'cat-1'` to its Canonical ID on every Backend.

### Rules (data layer)

- **Subjects live only in facades and the seed store** — never in a
  repository. Repositories are stream-backed from their source; buffering a
  reactive source a second time double-buffers it.
- **Queries stay single-table `eq`/`gt`/`lt`/`order`/`limit`** — no joins, no
  aggregates. Aggregation is Facade `.map()` work.
- **Nested collections are `jsonb` columns, never child tables** — keeps
  every repository method single-table and realtime-streamable.
- **Never hand-mint a UUID.** Every identifier — fixture row, cross-reference,
  runtime-created entity — goes through `KitIdService`.
- **Fixtures author with Seed Keys; storage only ever sees Canonical IDs.**
  If a Seed Key shows up in a database row or an Appwrite document, something
  bypassed `KitIdService`.
- **Never edit generated SQL/Appwrite fragments by hand.** Change the Schema
  Descriptor (`KitTableSchema`) and regenerate — hand edits drift silently
  from the source of truth on the next regen.
- **The kit never self-registers.** `KitData.initialize` only runs when the
  host calls it, matching `appbox_kit`'s host-integration contract.

### Auth seam (KitAuthService)

One interface, three impls, picked by the same `KitDataConfig.backend` that
picks the repositories — Auth is a sibling seam to `KitRepository<T>`, never
one. Enable it by passing `auth: KitAuthConfig(...)` to `KitDataConfig`;
`KitData.initialize` then registers a `KitAuthService` singleton for the
active backend. Access it via `locator<KitAuthService>()` or the `auth`
getter on `KitDataFacade`.

**Fake Auth pairs ONLY with the Seed Backend.** Real backends reject fake
sessions outright — Supabase RLS keys on `auth.uid()`, Appwrite rows are
default-deny — so signing in through `KitSeedAuthService` against Supabase or
Appwrite storage is a client-side fiction, not a bypass. Smoke-testing
against a real backend: call `signInAnonymously()` (a real, server-issued
Session on both Supabase and Appwrite) or sign in as an Operator-seeded test
user. Do not assume Fake Auth works once a real Backend is wired.

**Fake auth mechanics.** `KitSeedAuthService` stores fake users in the
reserved `kit_auth_users` table inside the seed store — NOT a registered
entity (never emitted by the emitters, never pushed by the Seeder) but
snapshot-persisted like every other table. Optionally pre-seed it via
`KitAuthConfig.fakeUsersAsset`; unknown identities are auto-created on
sign-in regardless. Every sign-in method *resolves* an identity rather than
authenticating one — any password, any OTP code (`000000` is the
conventional one) succeeds. Fixture-ownership synergy: a data Fixture's
`"owner": "user-1"` lines up with the Session you get signing in as that
fixture identity's email, because both resolve through the same
`KitIdService.canonicalId('kit_auth_users', ...)`.

**OTP is two-step** — `requestOtp({email, phone})` then
`confirmOtp({email, phone, code})` — because both real backends are two-step:
Supabase `signInWithOtp` → `verifyOTP`; Appwrite
`createEmailToken`/`createPhoneToken` → `createSession(userId, secret)`.

Per-backend notes:

- **Supabase Google** — native flow via `google_sign_in` v7
  (`GoogleSignIn.instance.initialize` once, then `.authenticate()`), needs
  `KitAuthConfig.googleServerClientId`; feeds
  `signInWithIdToken(OAuthProvider.google)`. Supabase's own guide still shows
  the pre-v7 API — verify against installed source, not the docs
  (supabase/supabase#36775).
- **Supabase Apple** — the nonce round-trip (raw nonce → SHA-256 to Apple,
  raw nonce back into `signInWithIdToken`) is handled inside the kit; hosts
  don't touch it.
- **Appwrite OAuth** (Google + Apple) — browser flow via `createOAuth2Token`,
  redirecting through the `appwrite-callback-<PROJECT_ID>` URL scheme; the
  Operator enables + configures providers in the Appwrite console, not in
  Dart.
- **Appwrite user ids** — email/OTP sign-ups pass
  `userId = canonicalId('kit_auth_users', email|phone)`, so those Canonical
  IDs are minted at creation. OAuth and anonymous sign-ins don't supply a
  `userId` — Appwrite assigns its own `$id`, and `KitAuthUser.id` is a
  Canonical-ID derivation of that `$id` (stable, deterministic, but NOT equal
  to `$id`). Operator note: server-side permission rules written against the
  raw Appwrite `$id` will not match `KitAuthUser.id`.

**Operator checklist per backend** (platform config, not Dart):

- **Seed** — nothing; fixtures and fake users load automatically.
- **Supabase** — Google: SHA-1/SHA-256 fingerprints + OAuth client in Google
  Cloud console (Android), URL scheme in Info.plist (iOS),
  `googleServerClientId`/`googleClientId` supplied to `KitAuthConfig`. Apple:
  "Sign in with Apple" capability enabled in Xcode + Apple Developer portal.
- **Appwrite** — register the `appwrite-callback-<PROJECT_ID>` URL scheme on
  each platform, enable the Google/Apple providers (with their own OAuth
  credentials) in the Appwrite console.

## Showcase & app template (appbox_kit_showcase_app)

**`showcase_app` is the reference template** for bespoke
appbox_kit apps — a standalone runnable app scaffolded and grown *entirely*
via the Stacked CLI (see "Building on the kit" above; the step-by-step playbook
lives in `docs/plans/appbox-kit-showcase-app-port.md` §7). The older
`packages/appbox_kit_showcase` (pluggable, host-embedded) is superseded as the
template — read it only for history. The showcase ships the 17 native kit
surfaces as routed tabs (Home/Search/Profile) plus **AppBox Notes** — an
iOS-Notes-style app smoke-testing every appbox_kit_data capability over
seeded data (folders, pinned, date groups, search, soft delete/restore,
photo capture, voice memos, fake-auth sign-in with per-owner isolation).

- **Host plug-in is exactly three moves** (see the package README):
  `await AppboxKitShowcase.initialize()` in `main()`, the `/showcase`
  `CustomRoute` block in `@StackedApp` (paths must match
  `ShowcaseShellView.tabPaths`), and startup navigation to
  `ShowcaseShellViewRoute()`.
- **It's a sibling package, not part of appbox_kit** — it depends on
  appbox_kit_data (which depends on appbox_kit); nesting it in the kit
  would cycle the graph and force supabase/appwrite/media deps on every
  consumer.
- **The template patterns to copy** for bespoke apps: every tab is its own
  SHELL route with children (exactly like the host's Train/Shop shells), and
  the outer shell hosts them in a `StackedTabsRouter` — stacked's IndexedStack
  tabs model: per-tab live navigation stacks, `context.tabsRouter` for
  `activeIndex`/`setActiveIndex` (tab taps never push on the root stack).
  **Tab-model decision rule (load-bearing):** the router model is for tab
  bodies that stay PURE FLUTTER (the showcase's tabs). When tabs mount native
  chrome (`KitNative*`/UiKitView app bars, search bars, glass), use the
  atlet/asko model instead — a kept-alive `IndexedStack` of shell views driven
  by an `IndexTrackingViewModel` (bar/rail calls `setIndex` directly), detail
  views pushed full-screen on the root navigator (`// root-push:` marker).
  **Either way, the switch-transition default is `KitAnimatedTabStack`**
  (self-driving PAIRED exit+enter direction-aware slide, fade off) — the showcase demonstrates
  it inside `StackedTabsRouter`, P2 over the flat `IndexedStack`. Fade over
  native-chrome stacks ghosts platform views (flutter#24164/#148639 — P2
  verified; review check 1c2 rejects `KitDirectionalTabTransition` and
  `fade: true` in consumer apps without a `// pure-flutter-tabs:` opt-out).
  P2's `application_shell` + `docs/plans/tabbar-storms-ghosting-and-shifting-fix.md`
  are the reference implementation and incident record.
  Package shells declare tab routes as name-based `PageRouteInfo('PageClassName',
  path: ...)` — never host-generated route classes — so packages stay
  host-agnostic; deeper pushes navigate by path string via
  `locator<RouterService>().navigateToPath(path: ...)`; path params read with
  `context.routeData.pathParams.getString('id')` (codegen does NOT inject
  them into constructors); facades (`NotesService extends KitDataFacade`) as
  the only layer viewmodels touch.
- **Media**: `record` (voice memos, m4a) + `just_audio` (playback) +
  `image_picker` (camera/library). Binaries under app-documents; rows store
  file names + metadata as jsonb. Host needs the three iOS usage keys
  (mic/camera/photo library); Android needs nothing.

## Host integration (the contract)

The kit is decoupled by design — the host wires three things, **none of them inside the kit**:

1. **Dependency.** Add `appbox_kit` (path/git/pub). Declare in the host only what the host uses directly (commonly `stacked` + `stacked_services`); the kit's own deps resolve transitively — see **Dependency management** below.
2. **Registration.** In the host `@StackedApp(dependencies:)`, register `Talker`, `KitErrorService`, `KitHapticService`, `KitThemeService`, `KitNavigationControllerService`, `KitNotificationService`, `KitOverlayService`, `KitSelectableService` as `LazySingleton`, then run `dart run build_runner build`. The kit reaches them via `locator` (same `StackedLocator.instance`).
3. **Snackbar setup.** The kit owns the `KitSnackbarType` vocabulary AND its default presentation — call `setupKitSnackbars()` in `main()` after `setupLocator` to register a `SnackbarConfig` per variant (KitColors). Hosts may register additional custom variants; KitActionConfig's snackbar-type fields are `dynamic`, so a call site can pass a host enum.

## Dependency management

- **The kit owns its deps.** `core/pubspec.yaml` declares every
  package the kit imports (`stacked`, `stacked_services`, `stacked_shared`,
  `rxdart`, `talker_flutter`, `flutter_animate`, `haptic_feedback`,
  `shared_preferences`) on **caret-latest** — `flutter pub outdated` confirms the
  direct deps are current.
- **Coexisting with the host's existing deps.** Pub resolves the **intersection**
  of every constraint across the graph and picks the **highest** version that
  satisfies all of them. If both the kit and host constrain `stacked`, the host
  gets the latest version both allow — never two copies. If constraints are
  disjoint (e.g. kit needs `stacked ^3` but host pins `stacked ^2`), pub reports
  a version-solving failure; the host can force a version with
  `dependency_overrides`.
- **Keeping current.** Caret tracks the latest within each major automatically —
  `flutter pub upgrade` pulls new minor/patch, `flutter pub upgrade
  --major-versions` advances the kit's constraints to new majors. (For a library
  that must *never* constrain the host, `any` is the maximally-permissive
  alternative — but it drops the kit's declared compatibility range, so prefer
  caret.)

## Patterns

```dart
// ViewModel operation: owner-owned (KitViewModel mixes in KitActionOwner),
// busy state binds as a stream; awaiting the chain executes it
final user = await action<User>(
  'fetch',
  () => userService.fetch(id),
)
    .completeOnError('Failed to load user', withValue: User.empty())
    .withSnackbars(success: 'User loaded', error: 'Load failed');

// Views bind op state as a stream — no setBusy plumbing:
// KitStreamBuilder(stream: viewModel.actionState$('fetch'), builder: ...)
```

**Streams-only views (hard convention):** viewmodels `extends KitViewModel`,
expose all state as `Stream`/`ValueStream` getters, and never call
`notifyListeners`; views set `@override bool get reactive => false;` on the
`StackedView` and bind live values with `KitStreamBuilder`. A view file
imports ONLY its viewmodel (+ kit packages + sibling views/widgets) — the
viewmodel re-exports every payload type the view names. After
`stacked create widget`, relocate the widget into its shell's
`ui/widgets/<shell>_widgets/` folder, rename to `*_widget.dart` (class name
matches), drop the WidgetModel, and export from the shell barrel.

- Log an error: `locator<KitErrorService>().error(error: e, stackTrace: s, message: 'fetch failed', widgetId: 'profile_view');` (also `info`/`warning`/`critical`/`handle`/`logEvent`; per-widget `setWidgetError`/`setWidgetLoading`).
- Theme: `KitThemeService` persists/reacts to `ThemeMode` (seeded `system`) and syncs the status bar to the resolved brightness. `ThemeData` comes from the kit's `kitLightTheme()` / `kitDarkTheme()` — pass them to `MaterialApp` and bind `themeMode` to `themeMode$`. `await locator<KitThemeService>().initialize()` in `main()` restores the persisted mode before first frame.
- Haptics on a widget: `button.withSuccessHaptic(onTap: () => ...)` or `widget.withHapticFeedback(type: ..., onTap: ...)`.
- Overlay / selectable: `card.withOverlay(...)` / `item.withSelectable(isSelected: ..., onTap: ...)`.

## Design tokens & spacing (never hardcode)

The kit ships design tokens in `common/` — **use them instead of raw numbers**.
A `SizedBox(height: 24)`, `BorderRadius.circular(10)`, or `fontSize: 32` in host
or kit code is a defect: it drifts off the scale and can't be themed. All of the
below are re-exported from the barrel (`package:appbox_kit/appbox_kit.dart`).

- **Spacing widgets** (`common/kit_ui_helpers.dart`) — const `SizedBox`es on a
  4 / 8 / 16 / 24 / 48 / 96 scale. Drop them straight into a `Column`/`Row`
  instead of a `SizedBox` gap:
  - Vertical: `verticalSpaceTiny` (4), `verticalSpaceXSmall` (8),
    `verticalSpaceSmall` (16), `verticalSpaceMedium` (24), `verticalSpaceLarge`
    (48), `verticalSpaceMassive` (96).
  - Horizontal: `horizontalSpaceTiny/XSmall/Small/Medium/Large/Massive` (same
    scale).
  - Arbitrary vertical gap: `verticalSpace(double)`. There is **no**
    `horizontalSpace(double)` — use a `horizontalSpace*` const or
    `SizedBox(width: kSize…)`.
  - Screen helpers: `screenHeight/screenWidth(context)`,
    `screenHeightFraction/screenWidthFraction`, `halfScreenWidth`.
- **Numeric constants** (`common/kit_app_constants.dart`):
  - Radii: `kRad0…kRad36` (e.g. `kRad8`, `kRad10`, `kRad12`, `kRad16`, `kRad20`).
  - Sizes: `kSize1…kSize500` — generic px for width/height/padding.
  - Button heights: `kButtonHeight{Tiny 32, Small 40, Medium 48, Large 56,
    XLarge 64, XXLarge 72}`.
  - Fonts: `kFont13…kFont48` + aliases `kFont{Small 14, Medium 16, Large 18,
    XLarge 20, XXLarge 24, XXXLarge 32, Huge 48}`.
  - Also `kDefaultBorderRadius`, `kPad16`/`kPad20`, `kOpacity*`.
- **Colours** — `KitColors`/`KitDarkColors` (`common/kit_colors.dart`) for the
  semantic palette (`accent`, `good`, `warn`, `danger`, `muted`, …). Prefer
  `Theme.of(context).colorScheme.*` for anything that must follow light/dark;
  reach for `KitColors.*` only for fixed brand semantics.

No token fits your value? Pick the nearest on-scale token (the *scale* is the
design intent, not the exact px), or size **intrinsically** — drop the fixed
`SizedBox` and let the widget size to its content + tap target. Don't invent a
magic number. (A segmented control or CTA wrapped in `SizedBox(280×40)` only
clips its own content; intrinsic sizing is both correct and token-free.)

## Native chrome (Liquid Glass iOS 26 / Material 3 Expressive Android)

Some Kit widgets render a **real native** tier via platform views — real Liquid
Glass on iOS 26, real Compose M3/M3E on Android — with a pure-Flutter fallback
everywhere else (web, desktop, iOS <26, tests). Canonical matrix + per-platform
build status: `core/NATIVE_COMPONENTS.md` (ships with the kit).

**Three eligibility dimensions** (Liquid Glass and M3E don't scope alike):

- **iOS Liquid Glass** — closed set: UIKit bars/sheets/popovers/controls.
- **Android M3E motion** — broad: `MaterialExpressiveTheme` cascades to any Material widget.
- **Android M3E morph** — closed set of 14 components (FAB→Menu, Split/Button Group, `LoadingIndicator`, …).

**Pattern — one explicit `KitNative<X>` widget per component** (not a `.native()`
helper). The native surface is **20 widgets + 1 function helper** today, each
resolving a real native tier (iOS 26 Liquid Glass via `cupertino_native_better`;
Android M3E via `m3e_collection`), with a Flutter fallback elsewhere:

- **2-way gate** (Android → `*_m3e` / Material, else → `CN*`): `KitNativeButton`
  (`ButtonM3E`), `KitNativeTabBar` (`NavigationBarM3E`, full-width flexible bar,
  `size: small`, `colorScheme.primary` active pill), `KitNativeSegmentedControl`
  (`ButtonGroupM3E` — **connected button group**; M3E deprecates the segmented button
  → button group; selected fill = tonal `secondaryContainer`), `KitNativeSlider`
  (`SliderM3E`), `KitNativeRangeSlider` (`RangeSliderM3E`), `KitNativeIconButton`
  (`IconButtonM3E` / `CNButton.icon`), `KitNativeFab` (`FabM3E`/`ExtendedFabM3E`;
  iOS = glass `CNButton`, HIG has no FAB), `KitNativeFabMenu` (`FabMenuM3E` FAB→menu
  morph / glass `CNPopupMenuButton`), `KitNativeSearchBar` (Material `SearchBar`,
  M3E motion via theme), `KitNativeAppBar`+`.sliver()` (`AppBarM3E`/`SliverAppBarM3E`),
  `KitNativeNavigationRail` (`NavigationRailM3E`; iOS = Material rail), `KitGlassCard`
  (`LiquidGlassContainer` / Material `Card`), `KitNativeProgress` (linear/circular).
- **3-way gate** (adds an explicit Material/Cupertino fallback branch):
  `KitNativeSplitButton` (`SplitButtonM3E` / `CNGlassButtonGroup` / `Row`+`PopupMenuButton`),
  `KitNativeToolbar` (`ToolbarM3E` + `ToolbarActionM3E` / `CNGlassButtonGroup` / Material),
  `KitNativeLoadingIndicator` (`LoadingIndicatorM3E` / `CupertinoActivityIndicator` / `CircularProgressIndicator`).
- **Thin wrap** (no M3E branch by design — CN self-degrades): `KitNativeSwitch` (`CNSwitch`).
- **Function-shaped** (static CN APIs, not widgets): `kitShowNativeSheet()`
  (`CNBottomSheet.show` / `showModalBottomSheet`). Transient feedback (toast/
  snackbar) is **not** a function helper — it goes through
  `KitNotificationService.show()` (see **Transient feedback**).
- **Primitives** (host passes these, never the dep): `KitMenuItem`, `KitToolbarAction`,
  `KitRailDestination`.

### Glyphs — `KitGlyphs` registry (identity) + per-surface sizes

Every button-ish surface takes a **`glyph:`** — a `KitGlyph` pairing the
Material `IconData` (Android/M3E tier) with its matching SF Symbol name (Apple
tiers) as ONE value, from the central catalog `KitGlyphs`
(`common/kit_glyphs.dart`, barrel-exported). **Never hand-roll `icon:` +
`sfSymbol:` combos at call sites** — that's how the same action drifts between
`'house'` and `'house.fill'` across screens. Add a semantic entry to
`KitGlyphs` instead and pass it everywhere that action appears. The raw
`icon:`/`sfSymbol:` params still exist on every widget as per-call overrides
(they win over `glyph` when both are given); `glyph:` stays const-friendly
(resolution happens at build time, so `const KitMenuItem(label: 'Refresh',
glyph: KitGlyphs.refresh)` compiles).

Surfaces accepting `glyph:`: `KitTab`, `KitMenuItem`, `KitToolbarAction`,
`KitRailDestination`, `KitNativeButton`, `KitNativeIconButton`,
`KitNativeSplitButton`, `KitNativePopupMenu`, `KitNativeFabMenu`.

**Sizing contract: the registry owns *identity*; each surface owns *size*.**
`KitGlyph` deliberately has no size field — the same `KitGlyphs.add` renders at
different sizes per context (exactly how SF Symbols take point size from
context and Material icons from `IconTheme`):

| Surface | Glyph size | Rationale |
|---|---|---|
| `KitNativeIconButton` (+ popup-menu trigger, toolbar) | **18pt** | bar-glyph scale; CNSymbol's 24 default reads oversized in bars |
| `KitNativeFab` / `KitNativeFabMenu` (Apple glass tier) | **22pt** in a **56pt** circle | measured live: SF Symbols draw ink ≈ 1.0× pointSize (a 24pt `plus` = 0.44 of the circle); 22pt lands the ~0.40 Apple-native optical weight. Material's nominal 24dp icon has inner em-box padding (~16dp ink), so "24" is NOT the same optical size across systems |
| Android M3E tiers | Material defaults (24dp) | M3 spec; `FabM3E` owns its own metrics |

The FAB circle is pinned to 56pt on both FAB widgets (M3 footprint;
`CNPopupMenuButton.icon`'s 44pt default made the FAB render *smaller* than the
app-bar buttons it floats above).

Spec sources per component: `DESIGN_REFERENCES.md`. The authoritative status matrix —
iOS Liquid Glass / Android M3E motion / Android M3E morph, plus deferred rows
(alert/dialog, carousel, drawer) with reasons — is `NATIVE_COMPONENTS.md` (ships with
the kit). Each widget resolves its tier via `KitPlatform.supportsNativeChrome`
**and** `KitNativeComponent.<x>.nativeBuilt` (stays `false` until the native factory
ships, so a widget never emits a view for an unregistered `viewType`); `native: bool?`
forces the tier in tests. To add a component: add a `KitNativeComponent` entry + a
`KitNative<X>` widget (fallback first), then flip `nativeBuilt` when the native tier ships.

**Why not `.native()` on any widget:** Liquid Glass eligibility is a closed per-type
set, the type-switch can't mirror most built widgets, the silent no-op on disallowed
types is a footgun, and the native Swift/Kotlin must ship regardless — the extension
is glue, not a way to avoid native code. Native surfaces ship via the kit's
`cupertino_native_better` / `m3e_collection` dependencies (the separate
`appbox_kit_native` plugin was removed); unavailable surfaces fall back to the
built widget.

### Glyph ink & theme wiring — the contract (centralized, no hardcoding)

`KitGlyphs` says WHICH mark; **`KitInk`** (`common/kit_glyphs.dart`) says what COLOR.
Every glyph/text color in a native widget routes through one of these — never a literal,
never `CupertinoColors.*`, never a raw `Color(0x…)`:

| Role | Resolver | Use for |
|---|---|---|
| Glyph ink (text-weight marks: button/icon/toolbar/tab/popup glyphs) | `KitInk.of(context)` → `onSurface` | default for almost every glyph |
| Muted ink (unselected rail, secondary marks) | `KitInk.mutedOf(context)` → `onSurfaceVariant` | unselected nav rail |
| Per-call override (destructive, custom) | `KitInk.of(context, override: c)` — `override` wins | destructive = `colorScheme.error` |
| Selection / active (pill, switch-on, slider, progress, active tab) | `colorScheme.primary` | accent — do NOT swap to ink |
| Glyph ON a filled accent surface (filled FAB, filled button) | `colorScheme.onPrimary` / `onPrimaryContainer` | filled containers (M3: FAB container = `primaryContainer`) |

**Two-lane glass rule (iOS 26).** Liquid Glass re-derives glyph color from the view's
`tint` and **discards** baked `.alwaysOriginal` image colors. So a glass glyph color must
ride BOTH lanes: `CNSymbol(color:)` (baked, for pre-glass) AND the control's `tint:`.
`KitNativeIconButton` is the gold standard. **Style-dependent `tint` caveat:** `tint` maps
to `baseForegroundColor` for `glass`/`plain`/`tinted`/`bordered`, but to `baseBackgroundColor`
for `filled`/`borderedProminent`/`prominentGlass`. So **do NOT add `tint:` to
`KitNativeButton`/`KitNativeFab`** (filled/prominentGlass) — tint would dye the *background*;
their glyph color travels the SF-Symbol hierarchical-config lane instead.

**Reactivity rule (platform views).** Pure-Flutter widgets recolor automatically on theme
flip (rebuild via `Theme.of(context)`). Native (`UiKitView`) widgets bake color into pixels
at item-build time, so a color-only change must **force an item rebuild (new objects)** to
flush glass's glyph cache — `setStyle` alone (appearance + reused objects) does NOT recolor
on glass. See `CNTabBar._syncPropsToNativeIfNeeded` (`colorChanged` → forces `setItems`) and
the tab-bar `setStyle` re-bake. Symptom of a violation: a native tier keeps its old tint
after a theme switch.

**Safe-area rule (platform views).** Flutter moves platform-view frames in *window*
coordinates while a scrollable scrolls, so a stock `UIHostingController` insets its hosted
SwiftUI whenever the frame crosses the status-bar / home-indicator regions — the glass
visibly shifts or compresses inside its Flutter slot and the inset sticks (Apple FB8176223;
nothing inside the SwiftUI view can opt out). Every CN platform view that hosts SwiftUI must
call `hosting.cnBlockSafeArea()` (`Utils/HostingSafeArea.swift`) right after creating the
controller; `CNNativeTabBar` is the one deliberate exception (docked, never scrolls). The
guard test `test/kit/guards/cn_hosting_safe_area_guard_test.dart` fails `flutter test` when
a new hosting call site lacks it. Symptom of a violation: a widget "moves from its position"
when the list scrolls near a screen edge. Full write-up + per-view table:
`NATIVE_COMPONENTS.md` → *Scrolled platform views & safe area*. Testing native Swift changes
requires a **full stop + rebuild** (hot reload/restart never recompiles plugin code) — and
never pipe `flutter build` through `tail` (it masks compile failures; check the exit code).

**No hardcoded themeable colors** in widgets. Platform constants that deliberately match a
native control (e.g. iOS `tertiarySystemFill` for the range-slider neutral rail, `Colors.white`
thumb, `Colors.transparent` scrims) are the ONLY exception — extract them to a named `const`
with a comment naming the platform token and why a theme role would regress. Full reference:
`docs/plans/kit-native-theme-contract.md`.

**Label text (titles) coloring.** Text *labels* (tab bar titles, segment titles) are not
glyphs — dedicated channels: tab bar titles via `UITabBarItemAppearance` title attributes
(unselected = ink in `applyUnselectedTint`; selected = accent in `applySelectedTint` via the
`selectedTint` stored property — `tint` is init-local), segment titles via
`UISegmentedControl.setTitleTextAttributes` driven by `CNSegmentedControl.labelColor`
(`.normal` = ink) / `selectedLabelColor` (`.selected` = `onPrimary`). M3E/Cupertino fallback
segments set the same via `Text` `TextStyle.color`.

**Native popup menu labels can't be inked.** iOS `UIMenu` / SwiftUI `Menu` item *titles* are
system-colored (default / `.destructive`=red / `.disabled`=grey): no `attributedTitle`, and
the "custom-view in menu" path is macOS-only (`NSMenuItem.customView`), not iOS. Item *icons*
ARE inkable (`CNSymbol.color` / `CNButtonDataPopupItem.iconColor`); Flutter-rendered menus
(`showMenu`, `PopupMenuButton`) ink both. Colored native labels require a custom popover — a
**product decision**, not a wiring fix. Full reference: `docs/plans/kit-native-theme-contract.md`.

## Per-platform route transitions (iOS swipe-back + Android predictive back)

Every route — root, tab children, nested grandchildren — renders **native per
platform through the stacked router**: cupertino slide + interactive
edge-swipe-back on iOS, Material motion + predictive back on Android,
no-animation on web. Path-params, guards, deep links, and the back-button
dispatcher all survive (the route stays declarative — no raw `Navigator.push`).

**Why a kit helper is required:** stacked 3.5.0's `AdaptivePage` builds a
material route on *all* non-web platforms, and the iOS swipe-back gesture lives
only in the cupertino *route mixin* (`CustomCupertinoRouteTransitionMixin`),
never in a themed `CupertinoPageTransitionsBuilder` (which gives only the slide
*visual*). So `AdaptiveRoute`/`MaterialRoute` + a themed cupertino builder — the
"obvious" setup — silently loses the gesture. The kit's `KitPlatformPagesMixin`
overrides `RootStackRouter.pageBuilder` to re-wrap each generated page as
`CupertinoPageX` on iOS / `MaterialPageX` elsewhere, reusing `routeData` +
`child`; it propagates to nested tab controllers, so children + grandchildren
are covered.

**Host setup (3 steps):**

1. **Router shell** (the class can't live in the kit — it `extends` the host's
   generated, per-app `StackedRouterWeb`):
   ```dart
   // lib/app/app_platform_router.dart
   import 'package:appbox_kit/appbox_kit.dart' show KitPlatformPagesMixin;
   import 'package:stacked_services/stacked_services.dart' show StackedService;
   import 'app.router.dart' show StackedRouterWeb;

   class AppPlatformRouter extends StackedRouterWeb
       with KitPlatformPagesMixin {
     AppPlatformRouter({super.navigatorKey});
   }
   final appPlatformRouter =
       AppPlatformRouter(navigatorKey: StackedService.navigatorKey);
   ```
2. **`main.dart`** — pass the instance to `setupLocator`, use it for the
   delegate/parser (replaces the generated `stackedRouter` global), add the
   root back dispatcher:
   ```dart
   await setupLocator(stackedRouter: appPlatformRouter);
   // MaterialApp.router:
   routerDelegate: appPlatformRouter.delegate(),
   routeInformationParser: appPlatformRouter.defaultRouteParser(),
   backButtonDispatcher: RootBackButtonDispatcher(),
   ```
3. **Android predictive back** — `android/app/src/main/AndroidManifest.xml`
   `<application>`:
   ```xml
   android:enableOnBackInvokedCallback="true"
   ```

Route annotations in `app.dart` are **moot** — the mixin re-wraps whatever the
generator produces. There is **no `predictiveBack` flag** in Flutter 3.44 (the
manifest flag + the default theme's `PredictiveBackPageTransitionsBuilder`
drive it). Full design + decision rationale:
`docs/plans/kit-platform-route-transitions.md`.

## Rules (don't break the decoupling)

- **Never add a host import** (`package:<app>/...`) inside `appbox_kit/`. The kit stays host-agnostic; reach services only through `locator`.
- **Don't register services from inside the kit** — registration belongs in the host `@StackedApp`. The kit defines classes; the app owns their lifecycle.
- **Theme is kit-owned but generic.** The kit ships a default Material 3 palette + `ThemeData` (`common/kit_colors.dart`) and `ThemeMode`/status-bar state (`KitThemeService`). It must stay free of host-specific colors and third-party UI libs (no shadcn_ui) — no `package:<app>/...` imports, and `KitThemeService` holds no color values. Hosts override the accent via `kitLightTheme(accent:)` or substitute their own `ThemeData`.
- **Native chrome = explicit `KitNative<X>` widgets**, gated by `KitPlatform` + `KitNativeComponent.<x>.nativeBuilt`. Never build a `.native()`-on-any-widget helper (Liquid Glass is a closed per-type set; most widgets can't be mirrored; the silent no-op is a footgun; native code ships regardless). The matrix + per-platform build status live in `core/NATIVE_COMPONENTS.md`; native surfaces come via the kit's `cupertino_native_better`/`m3e_collection` deps (`appbox_kit_native` was removed).
- **Host/showcase views reuse the kit chrome wholesale — never hand-roll a parallel version.** Top bars are `KitNativeAppBar` slotted into `Scaffold.appBar` (it implements `PreferredSizeWidget` — no wrapper; avoid the `.sliver()` variant, whose iOS tier is a non-native Material `SliverAppBar` that renders as a floating title), FABs are `KitNativeFab`/`KitNativeFabMenu` (the kit owns tier-correct size + `colorScheme.primary`; pass no color), and every themeable color is a `colorScheme` role (`primary`/`onPrimary`, `tertiary`/`onTertiary`, `error`/`onError`) — no per-feature accent consts (`kFooAccent = Color(0x…)`) and no raw `Color(0x…)`/`CupertinoColors.*` for themeable values. The leading back affordance is `KitGlyphs.back`. A hand-rolled bar or FAB, or a stray accent constant, is a defect even if it renders fine. Fixed platform constants (e.g. an always-black media lightbox) are the lone exception, each a named `const` with a `ponytail:` comment naming the platform token. Full playbook: `docs/plans/appbox-kit-showcase-app-port.md` §7.8.
- **Never hand-roll `icon:` + `sfSymbol:` pairs.** Pass `glyph: KitGlyphs.<x>` (add a semantic entry to `common/kit_glyphs.dart` if missing) so the Material icon and SF Symbol can never drift apart. `KitGlyph` carries no size — surfaces own sizing (18pt bar glyphs; FAB 22pt glyph in a 56pt circle). See **Glyphs** above.
- **Transient feedback goes through `KitNotificationService.show()`.** Never call `SnackbarService.showCustomSnackBar` or `CNToast` directly, and don't reach for a `kitShowNativeToast` helper (deleted). `actionLabel` is the only thing that promotes iOS from a CNToast to a snackbar.
- KitAction snackbar-type fields are `dynamic` — an app may pass its **own** enum variant at a call site; defaults are `KitSnackbarType.*`.
- **New CN platform view hosting SwiftUI? Call `cnBlockSafeArea()`** right after `UIHostingController(rootView:)` — or the widget will drift inside its slot when scrolled near screen edges. Enforced by `test/kit/guards/cn_hosting_safe_area_guard_test.dart`; deliberate safe-area users (docked chrome) go on that test's allowlist with a why-comment. See **Safe-area rule** above.
- Before asserting any API in generated code or advice, read the file under `core/lib/` — it is the source of truth.
- **Never hardcode magic numbers.** Use the kit's design tokens — spacing widgets (`verticalSpace*`/`horizontalSpace*`), `kRad*`, `kSize*`, `kButtonHeight*`, `kFont*`, and `KitColors`/`colorScheme` — not raw `SizedBox(height: 24)` / `BorderRadius.circular(10)` / `fontSize: 32`. If no token fits, size intrinsically rather than inventing a value. See **Design tokens & spacing**.
- **Per-platform route transitions come from `KitPlatformPagesMixin`, not route annotations or a themed `CupertinoPageTransitionsBuilder`.** stacked 3.5.0's `AdaptivePage` is material on all non-web platforms and the iOS swipe-back gesture is route-mixin-only — so annotations + themed builders silently lose the gesture. Mix `KitPlatformPagesMixin` into the host's generated router + add `backButtonDispatcher: RootBackButtonDispatcher()` + `enableOnBackInvokedCallback` in the manifest. Never raw-push `CupertinoPageRoute` around the router (loses path-params/guards/deep-links — fatal for `@PathParam` views). See **Per-platform route transitions** above.

## Notes

- Source of truth: `core/lib/`. Porting decisions (what was kept/dropped, the locator shim, `KitSnackbarType` reconciliation): `docs/plans/port-kinly-kit-to-p2.md`. Notification-service design (as-built): `docs/plans/kit-notification-service.md`.
- Data layer source of truth: `appbox_kit/data/lib/`. Architecture + locked decisions: `docs/plans/appbox-kit-data-layer.md`. Auth seam decisions: `docs/plans/appbox-kit-data-auth.md`. Vocabulary (Backend, Seed Key, Canonical ID, Schema Descriptor, Auth Service, Session, Fake Auth, …): `CONTEXT.md`. Canonical-ID derivation: `docs/adr/0001-deterministic-v5-canonical-ids.md`.
- SSOT: this skill lives IN the kit package at `appbox_kit/skills/appbox-kit/SKILL.md`; `.claude/skills/appbox-kit` is a symlink to it (edit either path, same file). When adopting the kit in another project, symlink `appbox_kit/skills/appbox-kit` into that project's `.claude/skills/appbox-kit` — do not copy (copies go stale).
- Verified runtime: services resolve via the host `setupLocator`; `KitAction.run(...).execute()` runs end-to-end (see `test/kit/services/kit_services_resolve_test.dart`).
