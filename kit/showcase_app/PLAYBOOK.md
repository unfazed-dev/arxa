<!-- Promoted from the original stacked_kit port plan (2026-07-25).
     This file is the living playbook for the showcase_app. -->

> **What this is.** The recipe for standing up a new Stacked app on
> `appbox_kit`, extracted from the showcase_app port so it can be followed
> without reading the port's plan doc. `showcase_app/` itself is the worked
> example for every step below.
>
> Domain language is defined in the repo `CONTEXT.md`; use those terms verbatim.
> The full `stacked_cli` reference is in the stacked_cli docs.

# Building a new Stacked app from this template

> Audience: an engineer starting a new iOS/Android Stacked app on the
> `appbox_kit/*` kits. Each step names the exact CLI command. Run every
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
  appbox_kit:        { path: ../../appbox_kit }
  appbox_kit_data:   { path: ../../appbox_kit_data }
  appbox_kit_native: { path: ../../appbox_kit_native }   # if used directly
  rxdart: ^0.28.0
```
In `lib/app/app.dart` register kit services as `LazySingleton` (KitErrorService, KitNotificationService, KitHapticService, KitThemeService, KitNavigationControllerService, KitOverlayService, KitSelectableService, Talker). Mirror the old showcase `app.dart`.

## 7.3 Boot the data layer
```dart
await KitData.initialize(
  config: const KitDataConfig(
    backend: KitDataBackend.seed,
    seedPersistence: KitSeedPersistenceMode.snapshot,
    auth: KitAuthConfig(fakeUsersAsset: 'assets/seed/kit_auth_users.json'),
  ),
  entities: [/* KitEntityRegistration per table */],
  fixtureAssets: ['assets/seed/<table>.json'],
);
```

<!-- PORTED — §7.3 DONE 2026-07-12. Boot lives in `lib/app/app_data.dart`:
`AppData.initialize({config, assetReader})` (renamed from the source's
`AppboxKitShowcase` — that name referenced the old package). It boots KitData
over the 3 seed fixtures AND registers the two Notes services (ShowcaseNotesFacadeService,
ShowcaseNotesMediaAdapterService) via the shared `locator` — the data slice boots itself (one
call = data layer usable). `main.dart` calls it after `setupLocator()`; a
`ThemeMode` StreamBuilder drives kitLightTheme/kitDarkTheme. The 12 kit
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
above are INACCURATE for the appbox_kit_data architecture. There is NO
hand-written Repository (and no `notes_repository`/`notes_facade` services).
2026-07-13 update: the services ARE now CLI-created — `stacked create service
notes / notes_media` scaffolds + registrations, with the KitDataFacade body
hand-authored INTO the CLI-created file (the documented exception). Correct
procedure:
(1) define the entity + `KitTableSchema` + `KitEntityRegistration` in the model
    file (lib/notes/models/*.dart);
(2) pass the registrations to `KitData.initialize(entities: [...])` — typed
    `KitRepository<T>` then comes FREE via `KitDataFacade.repository<T>()`; that
    IS the swap seam (no per-table Repository class to author);
(3) the Facade is a hand-authored `class ShowcaseNotesFacadeService extends KitDataFacade`
    (prefixed per the showcase naming convention, 2026-08-05). It
    composes `repository<Note>()` / `repository<NoteFolder>()`, derives rxdart
    streams, and routes writes through `mutate()`.
The stacked CLI cannot scaffold a KitDataFacade subclass — hand-author it. -->

## 7.6 Bind a ViewModel to a Facade
```bash
stacked create view notes
```
ViewModel subscribes to the Facade's streams (reactive); no direct Repository access.

## 7.7 Lay out the shell route tree (IndexedStack tabs)

**View creation is CLI-only, and file placement mirrors the host app** (`p2/lib/ui/views` is the reference structure):

```bash
# every view (shells included) is a full CLI view — 4-file responsive set + viewmodel + test
stacked create view showcase_startup showcase_shell showcase_<tab>_shell showcase_<leaf_view> … --exclude-route
```

- **NAMING CONVENTION — every showcase-app view is `showcase_`-prefixed** (`showcase_startup`, `showcase_unknown`, `showcase_notes_shell`, `showcase_notes`, `showcase_note_editor`, …), including the scaffold's startup/unknown views, the shared helpers in `lib/ui/common` (`showcase_notes_shared.dart`, `showcase_tabs_shared.dart`), and the root widget in `main.dart` (`ShowcaseApp`, not `MainApp`). This makes every showcase artifact instantly distinguishable from any other app's views. Pass the prefixed name to `stacked create view` so classes, files, routes, and tests all come out prefixed. The scaffold's sheet/dialog boilerplate is prefixed too (`showcase_notice_sheet/`, `showcase_info_alert_dialog/` under `lib/ui/bottom_sheets`/`lib/ui/dialogs`, files ending `_sheet.dart`/`_dialog.dart` with matching `…Sheet`/`…Dialog` class names; barrels live one level up as `bottom_sheets.dart`/`dialogs.dart` since a folder-named barrel would collide with the artifact file); what stays canonical is `app_colors`/`ui_helpers` and the `main.dart` filename — Flutter requires it.
- Each **shell is a full CLI view folder** (`<name>_shell/` with view + mobile/tablet/desktop variants + viewmodel), never an inline `StatelessWidget` outlet class.
- **Leaf views nest inside their shell's folder** after generation: `lib/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_view.dart` (host example: `account_shell/account_home/`). The CLI generates flat; move the folder under its shell — sibling-relative imports survive the move, only `app.dart`/cross-view absolute imports change. Viewmodel tests stay FLAT in `test/viewmodels/` (host convention).
- **`--exclude-route` for every view in the shell tree**, then hand-place the routes in `app.dart`: `CustomRoute(page: ShowcaseStartupView, initial: true)` + `CustomRoute(page: ShowcaseShellView, path: '/', children: [CustomRoute(page: <Tab>ShellView, children: [CustomRoute(page: <TabView>, path: '', initial: true), …])])`. Route-tree layout is hand-edited (normal development); file creation is not.
- **Keep the startup view** (the scaffold ships it; the host keeps it — here renamed `ShowcaseStartupView`): `main()` stays thin (setupLocator + theme + UI builders + runApp), and `ShowcaseStartupViewModel.runStartupLogic()` does app boot (e.g. `await AppData.initialize()`) then `_routerService.replaceWith(<Shell>ViewRoute())`. Do not delete startup and fold boot into `main()`.

Run `stacked generate` after the route tree edit.

## 7.8 Use native-chrome widgets (`appbox_kit`)
`KitNativeAppBar`, `KitNativeFab`, `KitNativeFabMenu`, `KitNativeSheet`, `KitNativeSwitch`, `KitNativeSearchBar`, `KitNativeNavigationRail`, `KitGlassCard`, … — adaptive per platform; gated by `KitPlatform` / `KitNativeChromeGate`.

**Reuse mandates (hard — every showcase view, every host view built on the kit):**

- **Top bars → `KitNativeAppBar` in the `Scaffold.appBar` slot.** `KitNativeAppBar` implements `PreferredSizeWidget`, so it drops straight into `Scaffold.appBar` (no `PreferredSize` wrapper) — the exact pattern `ShowcaseGalleryChrome` and every notes view use. Never a hand-rolled `Row`/`Padding` bar, and never place the bar *inside* the scroll body. For scrollable content use `Scaffold(appBar: KitNativeAppBar(...), body: <scrollable>)`, **not** `KitNativeAppBar.sliver()` — the `.sliver()` variant's iOS tier is a Material `SliverAppBar` (no native nav-bar look), so it renders as a floating title instead of a bar (this is the exact bug the notes views hit). The leading back affordance is `leading: KitNativeIconButton(glyph: KitGlyphs.back, …)` with `automaticallyImplyLeading: false` (explicit leading keeps every tier consistent). iOS has **no** native nav bar in `cupertino_native_better`, so `KitNativeAppBar` wraps `CupertinoNavigationBar` itself — never reach for one directly. The bar owns its bottom edge on every tier; drop any hand-rolled `Divider(height: 1)` beneath it.
- **FABs → `KitNativeFab` / `KitNativeFabMenu`.** Never a hand-rolled `Container(BoxShape.circle) + IconButton`. The kit FAB owns its tier-correct size (56pt circle, 22pt glyph) and derives `colorScheme.primary` internally on both the iOS-glass and Android-M3E tiers — pass **no** color. Entrance animations chain on the widget (`.animate()`).
- **Glyphs → `KitGlyphs.<x>`.** Never hand-roll `icon:` + `sfSymbol:` pairs at a call site. When the same action appears in ≥2 places (or any native chrome), add a semantic entry to `common/kit_glyphs.dart` (`KitGlyph(materialIcon, 'sf.symbol')`) and pass `glyph:`. `KitGlyph` exposes `.icon` / `.sfSymbol` for the few widgets (`KitNativeFab`) that take them separately. The leading back glyph is `KitGlyphs.back` (`arrow_back_ios_new` / `chevron.backward` — the iOS back symbol; don't use ad-hoc `chevron.left`).
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
```bash
stacked create bottom_sheet notice      # ui/bottom_sheets/ + registers BottomSheetService
stacked create dialog    error          # ui/dialogs/      + registers DialogService
stacked create widget    note_card      # ui/widgets/common/note_card/ + WidgetModel
# Flags: --no-model (skip Model), -t/--template, -p/--path (widget), --exclude-route
#        --no-test (skip test file generation)
```

## 7.11 v2 web (route divergence + chrome fallback) — placeholder
Web v2 gets its own route tree (different navigation model). Native chrome falls back to Flutter widgets on web; media plugins are web-incompatible and stay ios/android-only. Filled in v2.

---

## 7.12 Per-platform route transitions (iOS swipe-back + Android predictive back)

Every route (root, tabs, grandchildren) renders native per platform through the
stacked router: cupertino slide + edge-swipe-back on iOS, Material + predictive
back on Android, no-animation on web. Mix the kit's `KitPlatformPagesMixin`
into a host router shell, wire it in `main.dart` (+ `RootBackButtonDispatcher`),
and add `enableOnBackInvokedCallback` to the Android manifest. Full how-to +
why-a-kit-helper-is-required (stacked 3.5.0 `AdaptivePage` is material on all
non-web platforms; the iOS gesture is route-mixin-only): **SKILL.md → "Per-platform route transitions"** and `docs/plans/kit-platform-route-transitions.md`. Showcase reference impl: `appbox_kit/showcase_app/lib/app/kit_platform_router.dart`.
