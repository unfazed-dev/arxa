<!-- Promoted from the original stacked_kit port plan (2026-07-25).
     This file is the living playbook for the showcase_app. -->

> **What this is.** The recipe for standing up a new Stacked app on
> `arxa_kit`, extracted from the showcase_app port so it can be followed
> without reading the port's plan doc. `showcase_app/` itself is the worked
> example for every step below.
>
> Domain language is defined in the repo `CONTEXT.md`; use those terms verbatim.
> The full `stacked_cli` reference is in the stacked_cli docs.

# Building a new Stacked app from this template

> Audience: an engineer starting a new iOS/Android Stacked app on the
> `arxa_kit/*` kits. Each step names the exact CLI command. Run every
> `stacked create …` from the **app's root folder** (where `pubspec.yaml` lives).

## 7.1 Scaffold the app
```bash
stacked create app <app_name> --template=web --platforms=ios,android,web --org=com.<org>
# Flags:
#   -t, --template      mobile | web          (web → responsive stub structure)
#       --platforms     ios,android,windows,linux,macos,web
#       --org           reverse-DNS org
#       --description   pubspec description
#   -l, --line-length   formatter line length
#       --v1            use ViewModelBuilder instead of StackedView
#   -c, --config-path   custom stacked.json
```
Then `cd <app_name>` and `flutter run -d <device>`.

> **GOTCHA — iOS deployment target (verified 2026-07-12).** `stacked create app` internally runs `flutter create -e` (Flutter's *empty* template) and then overlays the Stacked template files — so the iOS project inherits Flutter's default `IPHONEOS_DEPLOYMENT_TARGET = 13.0` (×3 in `ios/Runner.xcodeproj/project.pbxproj`; reproduced with stacked_cli 1.15.5 + Flutter 3.44.0). `cupertino_native_better` (SPM) requires **iOS 15.0**, so the first iOS build fails with *"Target Integrity: the package product 'cupertino-native-better' requires minimum platform version 15.0 … but this target supports 13.0"*. The CLI has no flag for this; bump it as a mandatory post-scaffold step before §7.2:
> ```bash
> sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' ios/Runner.xcodeproj/project.pbxproj
> ```
> (Matches the `cupertino_native_better` playbook's Wiring requirement. `flutter test` is host-only and never surfaces this — it only appears on the first device build.)

## 7.2 Wire the kit (path deps + locator + theme)
Add to `pubspec.yaml`:
```yaml
dependencies:
  arxa_kit:        { path: ../../arxa_kit }
  arxa_kit_data:   { path: ../../arxa_kit_data }
  arxa_kit_native: { path: ../../arxa_kit_native }   # if used directly
  rxdart: ^0.28.0
```
In `lib/app/app.dart` register kit services as `LazySingleton` (ArxaKitErrorService, ArxaKitNotificationService, ArxaKitHapticService, ArxaKitThemeService, ArxaKitNavigationControllerService, ArxaKitOverlayService, ArxaKitSelectableService, Talker). Mirror the old showcase `app.dart`.

## 7.3 Boot the data layer
```dart
await ArxaKitData.initialize(
  config: const ArxaKitDataConfig(
    backend: ArxaKitDataBackend.seed,
    seedPersistence: ArxaKitSeedPersistenceMode.snapshot,
    auth: ArxaKitAuthConfig(fakeUsersAsset: 'data/seed/kit_auth_users.json'),
  ),
  entities: [/* ArxaKitEntityRegistration per table */],
  fixtureAssets: ['data/seed/<table>.json'],
);
```

## 7.3.1 The data/ contract (schemas → generated artifacts)

The app owns its data layer; the kit owns the machinery. Layout:

```
lib/data/
├── data.dart                     # barrel, chains only
├── models/<shell>_models/        # pure data classes (*_model.dart)
└── schemas/<shell>_schemas/      # ArxaKitTableSchema + ArxaKitEntityRegistration (*_schema.dart)
data/
├── seed/<table>.json             # runtime fixtures (pubspec-declared assets)
└── generated/                    # emitter output — NEVER hand-edit
    ├── supabase_migration.sql
    ├── supabase_seed.sql
    └── appwrite.tables.json
tool/generate_data.dart           # dart run tool/generate_data.dart [--check]
```

- **Schemas are the SSOT.** Edit a `*_schema.dart`, then regenerate:
  `dart run tool/generate_data.dart`. Schema files use targeted imports
  (never the kit barrel) so the tool compiles as a pure-Dart CLI.
- **`--check`** regenerates in memory and exits 1 on drift — the scaffold
  gate's **D1** section runs it, so a stale `data/generated/` fails the gate.
- **Backend coherence (D1):** the `ArxaKitDataBackend` declared in
  `lib/app/app_data.dart` must have its artifacts — supabase → both SQL files,
  appwrite → the tables fragment, seed → the fixtures (proven by `--check`).
- Fixtures keep the kit's `<table>.json` naming; the Appwrite `databaseId` is
  the package name (derived, never hardcoded).

<!-- PORTED — §7.3 DONE 2026-07-12. Boot lives in `lib/app/app_data.dart`:
`AppData.initialize({config, assetReader})` (renamed from the source's
`ArxaKitShowcase` — that name referenced the old package). It boots ArxaKitData
over the 3 seed fixtures AND registers the two Notes services (ShowcaseNotesFacadeService,
ShowcaseNotesMediaAdapterService) via the shared `locator` — the data slice boots itself (one
call = data layer usable). `main.dart` calls it after `setupLocator()`; a
`ThemeMode` StreamBuilder drives arxaKitLightTheme/arxaKitDarkTheme. The 12 kit
*infrastructure* services stay in `@StackedApp` (lib/app/app.dart). VERIFIED:
9 ported data-layer tests green (boot→seed→fake-auth→facade streams→mutation
round-trip→per-owner isolation) — `test/notes_service_test.dart`. -->

## 7.4 Define a Repository (swap seam)
```bash
stacked create service notes_repository   # scaffolds services/ + registers + test
```
One Repository per table, typed, talks only to the active Backend. Canonical IDs via Kit Id Service (ADR-0001) — **never** mint UUIDs in the Repository or Facade.

## 7.5 Compose a Facade Service (rxdart streams)
```bash
stacked create service notes_facade
```
`LazySingleton`; composes one or more Repositories; exposes `Stream<List<Note>>` / `ValueStream<Note>` via rxdart `BehaviorSubject`. UI reads only these streams.

<!-- PORT REALITY (fix during PLAYBOOK.md promotion, verify-gate #7): §7.4/§7.5
above are INACCURATE for the arxa_kit_data architecture. There is NO
hand-written Repository (and no `notes_repository`/`notes_facade` services).
2026-07-13 update: the services ARE now CLI-created — `stacked create service
notes / notes_media` scaffolds + registrations, with the ArxaKitDataFacade body
hand-authored INTO the CLI-created file (the documented exception). Correct
procedure:
(1) define the entity + `ArxaKitTableSchema` + `ArxaKitEntityRegistration` in the model
    file (lib/notes/models/*.dart);
(2) pass the registrations to `ArxaKitData.initialize(entities: [...])` — typed
    `ArxaKitRepository<T>` then comes FREE via `ArxaKitDataFacade.repository<T>()`; that
    IS the swap seam (no per-table Repository class to author);
(3) the Facade is a hand-authored `class ShowcaseNotesFacadeService extends ArxaKitDataFacade`
    (prefixed per the showcase naming convention, 2026-08-05). It
    composes `repository<Note>()` / `repository<NoteFolder>()`, derives rxdart
    streams, and routes writes through `mutate()`.
The stacked CLI cannot scaffold a ArxaKitDataFacade subclass — hand-author it. -->

## 7.6 Bind a ViewModel to a Facade
```bash
stacked create view notes
```
ViewModels expose the Facade's streams as getters (streams-only — see below); no direct Repository access.

**Streams-only convention (hard):** viewmodels `extends ArxaKitViewModel` (arxa_kit_ui_library), expose all state as `Stream`/`ValueStream` getters (facade pass-throughs, rxdart `switchMap` compositions, seeded `BehaviorSubject`s for UI-owned state) and NEVER call `notifyListeners`. Views add `@override bool get reactive => false;` to the CLI-generated `StackedView` and bind live values with `ArxaKitStreamBuilder` at the right subtree. Ops run `action('<verb>', () => ...)` (the `ArxaKitActionOwner` helper on `ArxaKitViewModel`) — no widgetId strings, no manual `ArxaKitAction.dispose` (ArxaKitViewModel auto-disposes via `disposeArxaKitActions`). A view file imports ONLY its viewmodel (+ kit packages + sibling views/widgets); the viewmodel re-exports every payload type the view names. Reference: `showcase_notes_shell/showcase_notes/`.

## 7.7 Lay out the shell route tree (IndexedStack tabs)

**View creation is CLI-only, and file placement mirrors the host app** (`p2/lib/ui/views` is the reference structure):

```bash
# every view (shells included) is a full CLI view — 4-file responsive set + viewmodel + test
stacked create view showcase_startup showcase_shell showcase_<tab>_shell showcase_<leaf_view> … --exclude-route
```

- **NAMING CONVENTION — every showcase-app view is `showcase_`-prefixed** (`showcase_startup`, `showcase_unknown`, `showcase_notes_shell`, `showcase_notes`, `showcase_note_editor`, …), including the scaffold's startup/unknown views, the shared widgets in `lib/ui/widgets/common/` (`showcase_tabs_shared/`, `showcase_gallery_chrome/`), and the root widget in `main.dart` (`ShowcaseApp`, not `MainApp`). This makes every showcase artifact instantly distinguishable from any other app's views. Pass the prefixed name to `stacked create view` so classes, files, routes, and tests all come out prefixed. The scaffold's sheet/dialog boilerplate is prefixed too (`showcase_notice_sheet/`, `showcase_info_alert_dialog/` under `lib/ui/bottom_sheets`/`lib/ui/dialogs`, files ending `_sheet.dart`/`_dialog.dart` with matching `…Sheet`/`…Dialog` class names; barrels live one level up as `bottom_sheets.dart`/`dialogs.dart` since a folder-named barrel would collide with the artifact file); what stays canonical is the `main.dart` filename — Flutter requires it.
- **No local `lib/ui/common/`** — the CLI-template `app_colors.dart`/`app_strings.dart`/`app_constants.dart`/`ui_helpers.dart` files are deleted. Colors, spacing helpers, app constants, glyphs, and fonts always come from the kit: `package:arxa_kit_core/common/arxa_kit_colors.dart`, `…/arxa_kit_ui_helpers.dart`, `…/arxa_kit_app_constants.dart`, `…/arxa_kit_glyphs.dart` (+ `arxa_kit_glyphs_lucide.dart`), `…/arxa_kit_fonts.dart`. App-specific shared *widgets* live in `lib/ui/widgets/common/`; app-specific strings live beside the feature that owns them.

- **Assets follow the ratified v2 ruling** (SSOT: passive `kit/assets_default/`
  — taxonomy `assets/{brand-icons/, fonts/, images/}` + `assets.manifest.json`).
  The designer authors the app's `assets/` (intake uploads merged over kit
  defaults); the scaffolder pure copy-pastes it and wires everything from the
  manifest. Fonts are **Google Fonts by name** (`google_fonts` package, roles
  from the manifest — `assets/fonts/` holds files only for user-uploaded brand
  fonts, which then get a real pubspec `fonts:` block). `brand-icons/` is the
  launcher/app-icon master (png + optional svg) consumed by
  `flutter_launcher_icons`; UI icons remain kit code glyphs
  (`arxa_kit_glyphs.dart`), never asset files. Every bundled image path is
  an `abxImg*` const in `arxa_kit_assets.dart` (generic kit template +
  app-authored copy, same pattern as `arxa_kit_app_strings.dart`); code and
  designs refer to the name, never a loose path. Showcase demo:
  `abxImgShowcaseLogo` → `assets/images/showcase_logo.png`.
- Each **shell is a full CLI view folder** (`<name>_shell/` with view + mobile/tablet/desktop variants + viewmodel), never an inline `StatelessWidget` outlet class.
- **Leaf views nest inside their shell's folder** after generation: `lib/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.dart` (host example: `account_shell/account_home/`). The CLI generates flat; move the folder under its shell — sibling-relative imports survive the move, only `app.dart`/cross-view absolute imports change. Viewmodel tests stay FLAT in `test/viewmodels/` (host convention).
- **`--exclude-route` for every view in the shell tree**, then hand-place the routes in `app.dart`: `CustomRoute(page: ShowcaseStartupView, initial: true)` + `CustomRoute(page: ShowcaseShellView, path: '/', children: [CustomRoute(page: <Tab>ShellView, children: [CustomRoute(page: <TabView>, path: '', initial: true), …])])`. Route-tree layout is hand-edited (normal development); file creation is not.
- **Keep the startup view** (the scaffold ships it; the host keeps it — here renamed `ShowcaseStartupView`): `main()` stays thin (setupLocator + theme + UI builders + runApp), and `ShowcaseStartupViewModel.runStartupLogic()` does app boot (e.g. `await AppData.initialize()`) then `_routerService.replaceWith(<Shell>ViewRoute())`. Do not delete startup and fold boot into `main()`.

Run `stacked generate` after the route tree edit.

## 7.8 Use native-chrome widgets (`arxa_kit`)
`ArxaKitNativeAppBar`, `ArxaKitNativeFab`, `ArxaKitNativeFabMenu`, `arxaKitShowSheet()`, `ArxaKitNativeSwitch`, `ArxaKitNativeSearchBar`, `ArxaKitNativeNavigationRail`, `ArxaKitGlassCard`, … — adaptive per platform; gated by `ArxaKitPlatform` / `ArxaKitNativeChromeGate`.

**Reuse mandates (hard — every showcase view, every host view built on the kit):**

- **Top bars → `ArxaKitNativeAppBar` in the `Scaffold.appBar` slot.** `ArxaKitNativeAppBar` implements `PreferredSizeWidget`, so it drops straight into `Scaffold.appBar` (no `PreferredSize` wrapper) — the exact pattern `ShowcaseGalleryChrome` and every notes view use. Never a hand-rolled `Row`/`Padding` bar, and never place the bar *inside* the scroll body. For scrollable content use `Scaffold(appBar: ArxaKitNativeAppBar(...), body: <scrollable>)`, **not** `ArxaKitNativeAppBar.sliver()` — the `.sliver()` variant's iOS tier is a Material `SliverAppBar` (no native nav-bar look), so it renders as a floating title instead of a bar (this is the exact bug the notes views hit). The leading back affordance is `leading: ArxaKitNativeIconButton(glyph: ArxaKitGlyphs.back, …)` with `automaticallyImplyLeading: false` (explicit leading keeps every tier consistent). iOS has **no** native nav bar in `cupertino_native_better`, so `ArxaKitNativeAppBar` wraps `CupertinoNavigationBar` itself — never reach for one directly. The bar owns its bottom edge on every tier; drop any hand-rolled `Divider(height: 1)` beneath it.
- **FABs → `ArxaKitNativeFab` / `ArxaKitNativeFabMenu`.** Never a hand-rolled `Container(BoxShape.circle) + IconButton`. The kit FAB owns its tier-correct size (56pt circle, 22pt glyph) and derives `colorScheme.primary` internally on both the iOS-glass and Android-M3E tiers — pass **no** color. Entrance animations chain on the widget (`.animate()`).
- **Glyphs → `ArxaKitGlyphs.<x>`.** Never hand-roll `icon:` + `sfSymbol:` pairs at a call site. When the same action appears in ≥2 places (or any native chrome), add a semantic entry to `common/kit_glyphs.dart` (`ArxaKitGlyph(materialIcon, 'sf.symbol')`) and pass `glyph:`. `ArxaKitGlyph` exposes `.icon` / `.sfSymbol` for the few widgets (`ArxaKitNativeFab`) that take them separately. The leading back glyph is `ArxaKitGlyphs.back` (`arrow_back_ios_new` / `chevron.backward` — the iOS back symbol; don't use ad-hoc `chevron.left`).
- **Colors → `Theme.of(context).colorScheme.*` roles only.** No per-feature accent constants (e.g. `kFeatureAccent = Color(0x…)`) and no raw `Color(0x…)` / `CupertinoColors.*` for themeable values. Filled accent surfaces pair the container role with its `on*` foreground (`primary`/`onPrimary`, `tertiary`/`onTertiary`, `error`/`onError`). The only exception is a genuine platform constant (e.g. a media lightbox that is always black) — extract it to a named `const` with a `ponytail:` comment naming the platform token and why a theme role would regress.
- **Sibling parity first.** Before adding chrome to a view, check the sibling showcases (home/search/profile) and reuse their pattern rather than inventing a parallel one. Reusability is the point of the kit — every new view should look like the existing ones because it's built from the same primitives.

## 7.9 Add a new package/tab (the "more incoming" recipe)
```bash
stacked create view <feature>
# add the shell route in app.dart, add the tab to ShellView.tabs
# add a Facade (`stacked create service <feature>_facade`) backed by a Repository
# add the path dep to pubspec
stacked generate
```
One tab per package surface; future packages append identically.

## 7.10 Sheets, dialogs, widgets

Generic transient UI needs NO scaffolded files — call the kit verbs on
`ArxaKitNotificationService` (via `arxaKitLocator`) from the viewmodel:
`confirm(title, actionLabel:, destructive:)` → bool, `prompt(title, placeholder:, initialValue:)` → String?,
`alert(title, message:)`, `notice(title, message:)` (modal sheet), `show(message, kind:)` (toast/snackbar).
`stacked create dialog/bottom_sheet` is only for genuinely custom branded
surfaces — never for confirm/text-input/notice, which the kit renders natively.

```bash
stacked create widget    note_card      # ui/widgets/common/note_card/ + WidgetModel
# Flags: --no-model (skip Model), -t/--template, -p/--path (widget), --exclude-route
#        --no-test (skip test file generation)
```

**Widget post-scaffold rule (per-shell structure):** the CLI only writes to `ui/widgets/common` with a `WidgetModel` — after `stacked create widget`, RELOCATE the widget into its shell home (`ui/widgets/<shell>_widgets/`), rename the file to `*_widget.dart` with the matching class name, drop the WidgetModel (widgets are dumb — state comes via constructor params or `ArxaKitStreamBuilder` bindings on the VM), and export it from the shell widgets barrel. `common/` is only for genuinely cross-shell widgets.

## 7.11 v2 web (route divergence + chrome fallback) — placeholder
Web v2 gets its own route tree (different navigation model). Native chrome falls back to Flutter widgets on web; media plugins are web-incompatible and stay ios/android-only. Filled in v2.

---

## 7.12 Per-platform route transitions (iOS swipe-back + Android predictive back)

Every route (root, tabs, grandchildren) renders native per platform through the
stacked router: cupertino slide + edge-swipe-back on iOS, Material + predictive
back on Android, no-animation on web. Mix the kit's `ArxaKitPlatformPagesMixin`
into a host router shell, wire it in `main.dart` (+ `RootBackButtonDispatcher`),
and add `enableOnBackInvokedCallback` to the Android manifest. Full how-to +
why-a-kit-helper-is-required (stacked 3.5.0 `AdaptivePage` is material on all
non-web platforms; the iOS gesture is route-mixin-only): **SKILL.md → "Per-platform route transitions"** and `docs/plans/kit-platform-route-transitions.md`. Showcase reference impl: `arxa_kit/showcase_app/lib/app/kit_platform_router.dart`.

---

## 7.13 The enums layer (reference implementation)

Every `enum` and sealed discriminator type in the app lives under
`lib/enums/`, one folder per shell with a shell barrel, and a root barrel that
exports only the shell barrels:

```
lib/enums/
├── enums.dart                        # root barrel — exports ONLY the shell barrels
├── showcase_application_enums/       # app-wide (tab identity, motion presets, …)
│   └── enums.dart                    # shell barrel
├── showcase_notes_enums/             # notes shell (ops, quick actions, folder scope, …)
│   └── enums.dart
├── showcase_profile_enums/
│   └── enums.dart
└── showcase_startup_enums/
    └── enums.dart
```

The rules this layer exists to make mechanical (canon:
`skills/arxa-builder/BUILDER_playbook.mdx` → Enums layer):

- **Behavior discriminators are enums, never raw strings/ints** — route-param
  actions, tab identity, rail/segment selections, dialog results, motion
  presets. Enhanced enums carry their label/route/preset fields so parallel
  arrays and label→value maps die.
- **abxAction op names are per-owner op-verb enums** (`ShowcaseNotesFacadeOp`,
  `ShowcaseNotesMediaOp`); `.name` is the hub/mutate wire key (camelCase —
  `'folder.create'` → `folderCreate`), entity-keyed ops interpolate the verb
  (`'${ShowcaseNotesMediaOp.playback.name}.$id'`), and facade op enums carry
  their mutate copy (`error`, nullable `success`) as fields.
- **Mixed domains are sealed types** — folder scope `'all' | 'trash' | <uuid>`
  is `ShowcaseFolderScope` with a `parse` at the route boundary and exhaustive
  switches; an enum cannot honestly hold an open set.
- Views, widgets, viewmodels, and services all import the enums barrels (pure
  types); the view↔viewmodel purity rule is unaffected — a view imports the
  barrel directly (G11: viewmodels never re-export).

Arch_guard's G12 flags any enum/sealed declaration outside
`lib/enums/**`; stringly-literal misuse stays a review rule.

---

## 7.14 File structure (semantic frontmatter)

Every covered file (`*_view.dart`, `*_viewmodel.dart`, facade/adapter/repository
services, `*_widget.dart`) carries a semantic library doc comment above
`library;` — the five-part spine: layer intro → plain paragraph (fixed role name
per kind) → numbered requirements (`N. [Name] — story-id`, story-id only when a
real story covers it) → ASCII relationships diagram + column inventory → history
line. Then `library;`, imports, and the class. Inline comments cite frontmatter
requirements: `/// [N. Requirement name] sentence.`

**Body sections (locked order, `// ── Name ──` separators):**

| Kind | Order |
|---|---|
| viewmodel | Setup / Initial state / Streams / Commands / Actions / Side effects / Cleanup |
| facade | Setup / Initial state / Streams / Writes / Reads / Cleanup |
| adapter | Setup / Initial state / Streams / Actions / Cleanup |
| repository | Setup / Reads / Writes / Cleanup |
| views/widgets | natural build order (no invented sections) |

Empty sections are omitted; models get the light variant (role paragraph +
field-purpose comments, no diagram); enums and tests are exempt.

**Reference implementation:**
`showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart`
(the pilot VM).

**Full grammar:** `skills/arxa-builder/BUILDER_playbook.mdx` → File structure
(semantic frontmatter).
