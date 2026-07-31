# appbox_kit — Native Components (canonical matrix)

The kit's canonical contract for which widgets get a **native chrome tier** (real
Liquid Glass on iOS 26 / real Material 3 Expressive on Android, via platform views)
vs. a **pure-Flutter fallback**. This ships **with the package**; the host's
`docs/plans/appbox-kit-native-components.md` is the build roadmap / worklog.

> **Spec sources:** every component here is grounded in the official
> Material 3 (Expressive) and iOS HIG references — see
> [`DESIGN_REFERENCES.md`](DESIGN_REFERENCES.md) for the per-component URLs and
> the SSOT deviations (segmented button → connected button group; no floating
> nav on Android).

## Three eligibility dimensions (not two)

Liquid Glass and M3 Expressive do **not** scope the same way, so each Kit widget is
evaluated on three independent axes:

| Axis | Scope | Mechanism |
|---|---|---|
| **iOS Liquid Glass** | **Closed set** — UIKit *bars, sheets, popovers, controls* | Auto-applied by the iOS 26 SDK to standard UIKit; custom content gets nothing |
| **Android M3E motion** | **Broad** — any Material widget | `MaterialExpressiveTheme` set once at the app top cascades spring-physics + easing to **every** Material component |
| **Android M3E morph** | **Closed set** — 14 new/updated components | Shape-morph library + motion physics: FAB→Menu, Split Button, Button Group, LoadingIndicator, FlexibleBottomAppBar, Carousel, Contextual Menu, … |

> A widget can be motion-eligible (broad) without being morph-eligible (closed).
> That asymmetry is why the motion column is near-universal and the morph column
> is sparse. It is also why a `.native()`-on-any-widget helper is the wrong shape:
> Liquid Glass eligibility is a closed per-type set, not a blanket.

## The matrix

Status — ✅ built (both native tiers wired, engines named) · ⏳ deferred (no wrapper — reason given in the row). No bare `—` rows remain.

In the **Android M3E morph** column, `✅ `WidgetM3E`` = the kit wires that
`*_m3e` widget on Android **today**; a bare component name = available upstream,
not yet wired.

`· CNX` in the iOS column = [`cupertino_native_better`](https://pub.dev/packages/cupertino_native_better)
already ships that control (**ready to wire** even while Status is `—`). `✅`
means a Kit widget wraps it today. That package is the single engine for the
whole iOS Liquid Glass column — it self-gates real glass on iOS 26 and degrades
to Cupertino/Material below.

| Kit widget | iOS Liquid Glass | Android M3E motion | Android M3E morph | Flutter fallback | Phase | Status |
|---|---|---|---|---|---|---|
| **tab bar** | `UITabBar` [bar] · `CNTabBar` | ✓ theme | ✅ `NavigationBarM3E` | `NavigationBar` / `CupertinoTabBar` | 1 | ✅ iOS `CNTabBar` glass · **Android `NavigationBarM3E`** |
| **navigation rail** | — (no CN rail) · Material `NavigationRail` | ✓ theme | ✅ `NavigationRailM3E` | `NavigationRail` | 4 | ✅ iOS Material `NavigationRail` (no CN rail) · **Android `NavigationRailM3E`** · structural |
| **app bar** (+`.sliver()`) | `UINavigationBar` [bar] · `CupertinoNavigationBar` | ✓ theme | ✅ `AppBarM3E` / `SliverAppBarM3E` | `AppBar` / `CupertinoNavigationBar` | 3 | ✅ iOS `CupertinoNavigationBar` · **Android `AppBarM3E`/`SliverAppBarM3E`** · structural |
| **toolbar** | `UIToolbar` [bar] · `CNGlassButtonGroup` (glass pill) | ✓ theme | ✅ `ToolbarM3E` (`ToolbarActionM3E`) | `AppBar` / `TopAppBar` | 3 | ✅ iOS `CNGlassButtonGroup` glass pill · **Android `ToolbarM3E`** (actions via `ToolbarActionM3E`) · 3-way, structural |
| **button (CTA)** | `UIButton` [control] · `CNButton`/`CNGlassButtonGroup` | ✓ theme | ✅ `ButtonM3E` | `FilledButton` / `CupertinoButton` | 2 | ✅ iOS `CNButton` glass · **Android `ButtonM3E`** |
| **icon button** | `UIButton` [control] · `CNButton.icon` (SF Symbol) | ✓ theme | ✅ `IconButtonM3E` | `IconButton` | 2 | ✅ iOS `CNButton.icon` (SF Symbol) · **Android `IconButtonM3E`** |
| **split button** | `CNGlassButtonGroup` (action + menu) | ✓ theme | ✅ `SplitButtonM3E` | `Row` + `PopupMenuButton` | 3 | ✅ iOS `CNGlassButtonGroup` · **Android `SplitButtonM3E`** · 3-way (Material `Row`+`PopupMenuButton` fallback) |
| **segmented control** | `UISegmentedControl` [control] · `CNSegmentedControl` | ✓ theme | ✅ `ButtonGroupM3E` (connected) | `SegmentedButton` / `TabBar` | 4 | ✅ iOS `CNSegmentedControl` · **Android `ButtonGroupM3E`** (connected group — M3E deprecates segmented buttons) |
| **FAB** | glass bar button / `UIButton` [control] · glass `CNButton` | ✓ theme | ✅ `FabM3E` / `ExtendedFabM3E` | `FloatingActionButton` | 2 | ✅ iOS glass `CNButton` (HIG has no FAB) · **Android `FabM3E`/`ExtendedFabM3E`** |
| **FAB menu** | glass popover · glass `CNPopupMenuButton` | ✓ theme | ✅ `FabMenuM3E` (FAB→menu morph) | `FloatingActionButton` + menu | 2 | ✅ iOS glass `CNPopupMenuButton` · **Android `FabMenuM3E`** (FAB→menu morph) |
| **popover / menu** | popover / `UIMenu` [popover] · `CNPopupMenuButton` | ✓ theme | — (motion via theme) | `MenuAnchor` | 3 | ✅ iOS `CNPopupMenuButton` · **Android Flutter `MenuAnchor`** (M3E motion via theme) |
| **search bar** | `UISearchBar` [bar] · `CNSearchBar` | ✓ theme | — (motion via theme) | `SearchBar` / `SearchAnchor` | 3 | ✅ iOS `CNSearchBar` · **Android Material `SearchBar`** (M3E motion via theme) · structural (`wantNative`) |
| **text field** | `UITextField` [control] · `CNTextField` | ✓ theme | ✅ `TextFieldM3E` | `TextField` | 2 | ✅ iOS `CNTextField` (Liquid Glass capsule; two-way `TextEditingController`) · **Android `TextFieldM3E`** (vendored M3E fork — focus shape-morph, mirrors split-button/toolbar/FAB; official Flutter M3E field flutter/flutter#168813 not shipped, so the kit vendors one) · Material `TextField` fallback (`wantNative:false`) |
| **input bar** (`KitNativeInputBar`) | inherits text field + icon button | ✓ theme | inherits (`TextFieldM3E` / `IconButtonM3E`) | Material composition | 6 | ✅ composite — `KitNativeTextField` + leading/trailing `KitNativeIconButton` slots (typed, one-size enforced), pill shape, keyboard-riding inset handling · tiers inherited · structural |
| **switch / toggle** | `UISwitch` [control] · `CNSwitch` (self-degrades) | ✓ theme | — (no M3E branch **by design**) | `Switch` | 4 | ✅ iOS `CNSwitch` (self-degrades glass → Material) · **Android CN's Material `Switch` fallback** (no M3E by design; thin-wrap gate) |
| **slider** | `UISlider` [control] · `CNSlider` | ✓ theme | ✅ `SliderM3E` | `Slider` | 4 | ✅ iOS `CNSlider` · **Android `SliderM3E`** |
| **range slider** | two-thumb `UISlider` [control] · `CNRangeSlider` (iOS 26+) | ✓ theme | ✅ `RangeSliderM3E` | `RangeSlider` | 4 | ✅ iOS `CNRangeSlider` (iOS 26+; Material `RangeSlider` below) · **Android `RangeSliderM3E`** |
| **loading indicator** | `UIActivityIndicator` [control] · `CupertinoActivityIndicator` | ✓ theme | ✅ `LoadingIndicatorM3E` (shape-cycle) | `CircularProgressIndicator` | 3 | ✅ iOS `CupertinoActivityIndicator` · **Android `LoadingIndicatorM3E`** (shape-cycle) · 3-way (Material `CircularProgressIndicator` fallback) |
| **progress** (`.linear`/`.circular`) | `UIActivityIndicator` [control] · Material `LinearProgressIndicator` / `CupertinoActivityIndicator` | ✓ theme | ✅ `LinearProgressIndicatorM3E` / `CircularProgressIndicatorM3E` | `LinearProgressIndicator` / `CircularProgressIndicator` | 3 | ✅ iOS Material `LinearProgressIndicator` / `CupertinoActivityIndicator` · **Android `LinearProgressIndicatorM3E`/`CircularProgressIndicatorM3E`** |
| **toast** (`KitNotificationService.show`) | `CNToast.show`/`.success`/`.error` | — | — (kit snackbar infra) | `showSnackBar` | 3 | ✅ iOS `CNToast.show`/`.success`/`.error` · **Android kit snackbar via `SnackbarService`** (reuses kit infra) · function gate |
| **glass card** | glass over content · `LiquidGlassContainer` | ✓ theme | — (M3 `Card` theme is the M3E surface) | `Card` | 5 | ✅ iOS `LiquidGlassContainer` (gated on `supportsLiquidGlass`) · **Android Material `Card`** (M3 theme is the M3E surface) · structural |
| **sheet** (`kitShowNativeSheet()`) | sheet presentation [sheet] · `CNBottomSheet.show` route + **Flutter-frosted body** (`KitFrostedSurface` + grabber, floating inset) | ✓ theme | — (motion via theme) | `showModalBottomSheet` | 3 | ✅ iOS transparent `CNBottomSheet.show` route + frosted body (ADR 0010/0011) · **Android `showModalBottomSheet`** · function gate |
| **alert / dialog** (`kitShowNativeDialog()`) | iOS 26 alert idiom — Flutter-drawn frosted panel (`KitFrostedSurface`) + stacked full-width `KitNativeButton`s | ✓ theme | — (no `*_m3e` package) | `AlertDialog` | 3 | ✅ iOS frosted-glass panel + stacked pills (primary filled / secondary subdued / destructive tinted) · **Android stock M3 `AlertDialog`** · function gate |
| **carousel** | — | ✓ theme | Carousel (upstream only) | `PageView` + custom | — | ⏳ **deferred** — neither CN nor `*_m3e` ships one |
| **drawer** (`KitDrawer` + `KitDrawerVariant`) | — (no native tier on either platform, by design) | ✓ theme | — (stock `Drawer` machinery) | `Drawer` + `KitFrostedSurface` | — | ✅ pure Flutter — stock `Drawer` machinery (edge-swipe/scrim/drag-close free) + variants: `glassPeek` (85% peek, 28dp trailing corner, ADR 0010 frosted skin) / `plain` (stock themed); optional `KitMotionScope` driver seam via `appbox_kit_motion` (ADR 0011 item 4) |

### Composite content surfaces → compose on the `glass card` row

Product/menu **tiles**, **cards**, **banners**, promo **panels**, list items, and
section containers have **no standalone `KitNative*` row** — but they are **not
"absent"**: they compose on the ✅ **glass card** row above. Wrap the content in
`KitGlassCard` (real Liquid Glass on iOS 26 · M3E Material `Card` on Android).
**Never** hand-roll a `Material(color:)` / decorated `Container(` card surface —
that is the native-first miss `review_checklist.sh` 1x + `enforce_design.dart`
(`no_raw_card_surface`) now flag. Guidance:

- **Dense scrolling grid** (product grid, list) → `KitGlassCard(wantNative: false)`
  — the themed/M3E `Card` tier. A `SliverGrid` of real Liquid-Glass UIViews janks,
  and a full-bleed image hides the glass anyway.
- **Singular floating surface** (hero, upsell banner) → `KitGlassCard()`
  (`wantNative: true`, the default) — real glass is right for one promo surface
  over content.
- Inner tappables need their own `Material(type: MaterialType.transparency)` — the
  glass tier (`LiquidGlassContainer`) provides no `Material` ancestor for ink.
- **Deliberate plain Flutter**: `--flutter-only` (whole surface) or a per-widget
  `// flutter-only: <reason>` comment → maps to `wantNative: false`/stock and
  suppresses the gate. Native-first is otherwise always the default.

### Whole-matrix native-first is enforced (not just chrome + cards)

Every ✅ row above with a stock Flutter equivalent is guarded, so the pipeline
can't silently ship a plain-Flutter surface where a native one exists:

- **Chrome bars** (app bar, tab bar, icon button) → `review_checklist.sh` 1c–1w.
- **Content surfaces** (tile/card/banner/panel) → 1x + `enforce_design.dart`
  `no_raw_card_surface` (4f).
- **Interactive + overlay surfaces** — **text field, switch, slider, range
  slider, FAB, segmented control, search bar, popup/menu, navigation rail, toast,
  sheet** → `enforce_design.dart` `no_stock_native_surface` (4g, table-driven —
  the ban list IS this matrix) + `review_checklist.sh` 1y. Stock CTA buttons and
  progress indicators are 4b/4c.
- **Spacing** — gaps are the `appbox_kit_core` helpers (`verticalSpace*`/
  `horizontalSpace*`, or `verticalSpace(h)`/`horizontalSpace(w)` for one-offs)
  → `review_checklist.sh` 1w2 bans single-arg spacing `SizedBox` in app-side
  code (sizing with a child / both dims / a `child:`-mounted placeholder stays
  legal).
- **Colors** — palette classes (`KitColors`/`KitDarkColors`, host `kc*`/brand
  classes) or `Theme.of(context).colorScheme`, never raw `Colors.*` /
  `Color(0x…)` literals → `review_checklist.sh` 1x2.

An app view that reaches for the raw Flutter widget (`TextField`, `Switch`,
`showModalBottomSheet(`, …) instead of the `KitNative*`/`kitShowNative*` surface
fails the gate. Deliberate plain Flutter opts out with `// flutter-only: <reason>`.
Adding a new native surface = add its `KitNative*` row here **and** one ban row to
`_nativeSurfaceBans` — the guard and the matrix stay in lockstep.

## Content widgets (pure Flutter — no native tier, by design)

These ship in `ui_library` as `Kit*` (content) widgets, **not** `KitNative*`:
they have **no** Liquid-Glass or M3-Expressive surface to wrap (an image is
content, not chrome), so the closed-set rule above does not apply to them.
The `no_invented_native_widgets` gate allowlist therefore does **not** list
them — and they must never be named `KitNative*`, which would falsely claim a
native tier.

| Kit widget | What it is | Why no native tier |
|---|---|---|
| **image** (`KitImage`) | `Image.asset` + placeholder-glyph fallback + `ClipRRect` radius | UIKit / M3 have no "native image" chrome — an asset image is always content. The placeholder glyph keeps the slot honest before decode / on error. |
| **frosted surface** (`KitFrostedSurface`) | `BackdropFilter` blur + saturation + tint + rim highlight — the ADR 0010 content/sheet/dialog tier | Apple's HIG reserves Liquid Glass for the functional layer; content gets *standard materials* — a Flutter-drawn frosted surface is the documented-correct look, and being Flutter-drawn it is occlusion-safe by construction. |
| **list section / list tile** (`KitListSection`, `KitListTile`) | Grouped inset sections (glass-card-backed) + glyph-leading rows: settings / menu / plugin idioms | UIKit grouped tables and M3 lists are layout idioms, not native chrome with a Liquid Glass / M3E surface — the section composes on the `glass card` row. |
| **chip / chip carousel** (`KitChip`, `KitChipCarousel`) | Icon+label stadium chips and a horizontal rail (scroll, optional snap, overflow edge fades) | A chip rail is a scrolling content collection — no CN/`*_m3e` chip or rail exists, and the deferred M3E browsing-`Carousel` row is a different (large-format) component. |
| **scroll edge effect** (`KitScrollEdgeEffect`) | Progressive blur/fade on scrollable children beneath pinned chrome (ADR 0010) | It is a treatment applied to *content pixels* (ImageFiltered), not a chrome surface — the iOS 26 semantic it mirrors (`UIScrollEdgeEffect`) is a scroll-view property, not a widget. |

**CN extras now wired through kit rows:** `CNToast` → toast (`KitNotificationService.show`),
`LiquidGlassContainer` → glass card (`KitGlassCard`), and `CNIcon`'s SF-Symbol path →
covered by `KitNativeIconButton` / `KitNativeButton.icon` / the `sfSymbol` primitive on
`KitTab`, `KitMenuItem`, and `KitToolbarAction`. No `cupertino_native_better` surface is
left unmapped.

## Glyphs — `KitGlyphs` registry + sizing contract

Icon-bearing surfaces take a **`glyph: KitGlyphs.<x>`** (`common/kit_glyphs.dart`,
barrel-exported): a `KitGlyph` pairs the Material `IconData` (Android/M3E tier)
with its SF Symbol name (Apple tiers) as one value, so the two can never drift
apart at call sites (`'house'` vs `'house.fill'` was a live bug). Raw
`icon:`/`sfSymbol:` params remain as per-call overrides; `glyph:` is
const-friendly (resolved at build time). Surfaces: `KitTab`, `KitMenuItem`,
`KitToolbarAction`, `KitRailDestination`, `KitNativeButton`,
`KitNativeIconButton`, `KitNativeSplitButton`, `KitNativePopupMenu`,
`KitNativeFabMenu`.

**The registry owns identity; each surface owns size** (`KitGlyph` has no size
field — same model as SF Symbols taking point size from context / Material
icons from `IconTheme`):

- **Bar glyphs — 18pt** (`KitNativeIconButton` default, popup-menu trigger,
  toolbar symbols). `CNSymbol`'s 24 default reads oversized in bar contexts.
- **FAB — 22pt glyph in a 56pt circle** (both `KitNativeFab` and
  `KitNativeFabMenu`, Apple glass tier). Two measured facts drive this:
  (1) `CNPopupMenuButton.icon`'s default diameter is 44pt (toolbar size) —
  the FAB rendered *smaller* than the app-bar buttons it floats above, so the
  circle is pinned to the M3 56 footprint on both widgets; (2) SF Symbols draw
  ink ≈ 1.0× pointSize while Material's nominal 24dp icon carries inner em-box
  padding (~16dp ink) — a "24pt" SF `plus` fills 0.44 of the circle vs
  Material's ~0.29. 22pt lands the ~0.40 Apple-native optical weight
  (verified live on the iOS 26.5 sim: 22.5pt ink / 56.3pt circle = 0.399).
- **Android M3E tiers** keep Material defaults (24dp glyphs; `FabM3E` owns its
  own metrics).

**iOS-only / app-level CN surfaces (no kit row — hosts import CN directly):**
`CNFloatingIsland`, `CNSearchScaffold`, and the experimental `CNGlassCard`. These are
either iOS-only chrome idioms or still experimental; a host may depend on
`cupertino_native_better` directly when it needs one.

**Morph correction:** "FAB→SearchBar" is **not** a documented built-in morph. The
real one is **FAB→Menu** (`FloatingActionButtonMenu`), now wired as `KitNativeFabMenu` →
`FabMenuM3E` on Android; FAB→Search would be a custom shared-element transition, not a
named component.

## Runtime gating

Native-chrome widgets resolve **three tiers** through `KitPlatform` (the kit owns
the detection; hosts pass primitives, and the kit still owns **no** platform-view
viewType of its own):

1. **iOS 26 Liquid Glass** — delegate to `cupertino_native_better` (`CN*`), which
   self-gates real glass and degrades to Cupertino/Material below 26.
2. **Android Material 3 Expressive** — per-widget `*_m3e` packages (pure Dart,
   shape-*morph*, **no native bridge**): `KitNativeButton` → `ButtonM3E`,
   `KitNativeTabBar` → `NavigationBarM3E` (full-width flexible bar, `size: small`;
   active-tab pill tinted `colorScheme.primary` for iOS parity),
   `KitNativeSegmentedControl` → `ButtonGroupM3E` as a **connected button group**
   (M3E **deprecates** the segmented button in favour of it — see
   [`DESIGN_REFERENCES.md`](DESIGN_REFERENCES.md)). Gated by
   `KitPlatform.supportsComposeM3E` (== `isAndroid`).
3. **Flutter fallback** — Cupertino (Apple < 26) / Material (desktop/web).

Gate shape: `wantNative = native ?? KitPlatform.supportsNativeChrome`; then glass
if `supportsLiquidGlass`, else M3E if `supportsComposeM3E`, else fallback. The
button is 2-tier (Android → `ButtonM3E`; everything else → `CNButton`, which
itself self-degrades glass → Cupertino → Material).

**M3E theming (required, not optional).** The `*_m3e` widgets are token-driven by
`m3e_design`'s `M3ETheme` ThemeExtension; `button_m3e` reads `context.m3e`, which
**asserts `M3ETheme is not installed` in debug** when it's absent (release silently
falls back to defaults, masking the crash). So `kitLightTheme()`/`kitDarkTheme()`
wrap their result in `withM3ETheme(...)` — the extension rides the app's
`ColorScheme` automatically and the host sets nothing. Deps resolve through the
**`m3e_collection ^0.3.7` umbrella** — one dep brings every `*_m3e` widget the kit
wires (FAB/FAB-menu, loading + progress indicators, toolbar, app bar, rail, split
button, icon button, slider, plus the already-wired button/button-group/navigation
-bar). This **supersedes** the earlier 4-package cherry-pick (`m3e_design`,
`button_m3e`, `button_group_m3e`, `navigation_bar_m3e`): once the kit wires ~12 of
the 13 components, the "don't drag unused components" rationale inverts — see
[`docs/plans/kit-native-full-surface.md`](../../docs/plans/kit-native-full-surface.md).
`MaterialExpressiveTheme` does **not** exist in the Flutter 3.44 SDK — there is no
zero-dep path; a package is required.

The legacy `appbox_kit_native` Compose plugin is still on disk but unused by any
wired widget — pending removal.

## Customizing the `*_m3e` tier (three surfaces, cheapest first)

The `*_m3e` widgets share one adapter pattern — each reads
`Theme.of(context).extension<M3ETheme>() ?? M3ETheme.defaults(...)`
(`ButtonTokensAdapter`, `NavTokensAdapter`, button_group's `_tokens_adapter`). To
change how one looks, reach for these **in order**; stop at the first that holds:

1. **Constructor param.** `ButtonGroupM3EAction` exposes `shape:` (per-action
   override) **and** `style:`. `ButtonM3E` exposes `style` + `size`. When the
   param exists, pass it — no wrapper. (`ButtonM3E` deliberately has **no** static
   `shape`: its shape is state-driven — round↔square morph on press, a signature
   M3E behavior — so drive it via `style`, not by forcing a shape.)
2. **`M3ETheme` token at the ROOT.** All three adapters read the same extension,
   so `withM3ETheme(base, override: …)` in `kit_colors.dart` changes a token
   **app-wide**. This is the global knob.
3. **Own `Material` wrapper — last resort.** Only when *all* hold: you want a
   value the widget reads from a token, there's **no constructor param** for it,
   and you need it changed **locally** (not app-wide) with the scoped override not
   propagating. So far this is **only** `NavigationBarM3E`'s container shape
   (`square.lg = 16px`, not externally overridable): `kit_tab_bar.dart` `_m3e()`
   sets `backgroundColor: Colors.transparent` and paints its own shapeless
   `Material` (which cannot round) to get flat, edge-to-edge corners. Treat this
   as the exception, not the pattern — verified on Android emu; see
   [`docs/plans/m3e-keep-vs-discard-decision.md`](../../docs/plans/m3e-keep-vs-discard-decision.md).

## Full-screen overlays / blur over the iOS native (CN) tier

> **ADR 0010 updates this section two ways.** (1) The kit's own overlays no
> longer raise blur scrims — the GetX `overlayBlur` was removed from
> `kit_snackbar_setup.dart`, and kit sheet barriers are plain dims — so kit
> chrome stays mounted behind kit-owned overlays; plain translucent fills
> cover platform views correctly on post-2019 Flutter. (2) Where a hide *is*
> still required (a blur that must cover a platform view), the gate now
> performs a **dematerialize** (fade + slight scale) for content-layer glass
> rather than an instant alpha-0, matching Apple's `effect = nil` semantic.
> The rule below remains in force for host overlays that present a
> `BackdropFilter`/blur over the native tier.

On iOS, the CN widgets (`CNButton`, `CNSegmentedControl`, `CNTabBar`) are
`UiKitView`s composited **above** the Flutter scene. A Flutter `BackdropFilter`
— which is what a GetX snackbar's `overlayBlur` scrim uses — **cannot sample or
cover platform-view pixels**, so the native controls **bleed through any blur or
scrim, sharp** (iOS hybrid-composition z-order; cupertino_native_better Issue
#53). Android composites platform views into the Flutter scene, so the blur
works there — this is iOS-only.

**Rule: any full-screen Flutter overlay/blur shown over the native tier must
hide the CN widgets for its lifetime.** The package removes the platform views
while a modal *route* is up (via `CNTabBarRouteObserver`), but a snackbar is an
`Overlay` entry, not a route, so that never fires on its own. Wrap the
presentation in the kit helper:

```dart
withNativeChromeHidden(() => locator<SnackbarService>().showCustomSnackBar(...));
```

It brackets the overlay's visible window with `markAnyModalActive/Inactive`
(the package's public non-route hook), so the CN views vanish behind the blur
and restore on dismiss. Contract: the callback's Future must either complete on
dismiss or resolve to a GetX `SnackbarController` — `showCustomSnackBar` does
the **latter** (it completes one frame after the snackbar *appears*, resolving
to the controller; the dismissal signal is `controller.future`), and the helper
unwraps and awaits that. Awaiting only the returned future released the hide
~1 frame after show, remounting the CN views sharp over the live blur (the
original iOS bleed screenshot). No-op on Android / iOS < 26.
**Visual note:** on iOS the controls *disappear* behind the scrim rather than
render blurred-but-visible — native pixels can't be blurred, so removal is the
only clean fix. The kit's own KitAction snackbars
(`notification_manager.dart`) already route through this; **any direct
`showCustomSnackBar` call must wrap itself.** Balance is unit-tested in
`test/kit/utils/kit_native_overlay_test.dart`.

### Per-widget coverage — who actually hides when the depth bumps

`withNativeChromeHidden` only raises the *signal*
(`CNTabBarRouteObserver.anyModalDepth`); each platform view still needs a
listener that unmounts it. Two layers provide that:

| Widget | Guard | Notes |
|---|---|---|
| `CNButton`, `CNSegmentedControl`, `CNSwitch`, `CNSlider`, `CNSearchBar`, `CNPopupMenuButton`, `CNGlassButtonGroup`, `CNLiquidGlassContainer`, `CNFloatingIsland`, `CNBottomSheet` | package `ModalHideMixin` | Upstream; position-aware (`topModalRect`) — may stay visible beside a partial sheet. |
| raw `CNTabBar` (non-search) | **`KitNativeChromeGate`** (inside `KitNativeTabBar`) | Its own listener is on the narrow route-only `modalDepth`; snackbars never trip it. |
| `CNIcon`, `search_scaffold` | **none upstream — wrap in `KitNativeChromeGate` yourself** | Platform views with no mixin; bleed sharp otherwise. |
| Any third-party platform view (maps, webview, video) | **wrap in `KitNativeChromeGate`** | |

#### New native-chrome surfaces (17) — modal-hide participation

`CNTabBarRouteObserver` / `anyModalDepth` is a **chrome-class** concern only. The
new surfaces split cleanly: chrome whose iOS tier is a CN platform view participates
via `ModalHideMixin` (ships `autoHideOnModal: true`); the rest are Flutter
Material/Cupertino (no platform view to bleed) or inline content controls (never
chrome). Verified against `cupertino_native_better-1.5.1` (grep `autoHideOnModal`);
**no `*_m3e` package exposes it** — the Android tier is pure Flutter, so it is a
non-issue there.

| New surface (Kit widget) | iOS tier | `autoHideOnModal`? |
|---|---|---|
| `KitGlassCard` | `LiquidGlassContainer` | ✅ ships `autoHideOnModal: true` |
| `KitNativeToolbar` | `CNGlassButtonGroup` | ✅ via `ModalHideMixin` |
| `KitNativeFab` | glass `CNButton` | ✅ via `ModalHideMixin` |
| `KitNativeFabMenu` | glass `CNPopupMenuButton` | ✅ via `ModalHideMixin` |
| `KitNativeSearchBar` | `CNSearchBar` | ✅ via `ModalHideMixin` |
| `KitNativeAppBar` | `CupertinoNavigationBar` | ❌ none — stock Cupertino widget, **not** a CN platform view (nothing to bleed) |
| `KitNativeNavigationRail` | Material `NavigationRail` | ❌ none — Flutter Material widget (nothing to bleed) |

**Not chrome (inline content controls) — deliberately outside the hide system:**
`KitNativeSwitch`, `KitNativeSlider`, `KitNativeRangeSlider`, `KitNativeIconButton`,
`KitNativeProgress`, `KitNativeLoadingIndicator`. The function-shaped natives
(`kitShowNativeSheet()` / `KitNotificationService.show`) *raise* the modal signal (the sheet)
or render through the kit-snackbar overlay infra (the toast) — they are shown *by*
the system, not hidden *by* it.

`KitNativeChromeGate` (exported from `appbox_kit.dart`) hides any child on
`anyModalDepth`, with: a mount-depth snapshot (a gate *inside* a sheet never
self-destroys), **zero layout shift** in either direction, and a
`showDuration` fade-in on restore (default 180ms; `Duration.zero` opts out).
The default `KitChromeHideMode.keepAlive` hides at the **paint level** —
alpha 0 skips painting, an unpainted platform view is removed from the
native view hierarchy (so it can't bleed through the blur), but the native
view instance stays alive and restore fades the **same live view** back in.
That's the anti-jank property: no native re-init and no raster/platform
thread-merge stall on reappear (both inherent to destroy-and-remount, which
is why `KitChromeHideMode.unmount` exists only as a per-widget escape hatch,
with a measured same-size placeholder). Hide is deliberately **instant** in
both modes: fading out would keep the native view bleeding through the blur
for the fade's length, and the overlay materializing on top masks the swap
anyway. Hidden children also ignore pointers. The gate is all-or-nothing
(ignores `topModalRect`); a true crossfade of native content is impossible —
platform views can't be snapshotted by `RepaintBoundary.toImage`. Behavior
is widget-tested in `test/kit/widgets/kit_native_chrome_gate_test.dart`.

**Verified (red-bg refraction, iOS 26 sim):** a red Scaffold background shows red
refracting through both elements + glossy sheen + specular highlights + edge
lamination → confirmed real Liquid Glass. (Glass over a *flat* background has
nothing to refract, so it legitimately reads as flat — verify with a contrasting
backdrop.)

## Scrolled platform views & safe area — the `cnBlockSafeArea()` invariant

**Symptom:** a CN glass surface inside a scrollable visibly shifts or compresses
inside its Flutter slot after scrolling (the 2026-07 "split button moves on
scroll" showcase bug — the pill shifted ~17pt down, and separately the glass
card's bottom edge rode up over its content after a fling), and the displacement
*sticks* after the scroll settles.

**Mechanism:** Flutter moves a platform view's frame in **window** coordinates
while its host scrollable scrolls (viewport clipping is visual only). Whenever
that frame crosses the status-bar / home-indicator regions, a stock
`UIHostingController` insets its hosted SwiftUI content. Nothing inside the
SwiftUI view can opt out — `.ignoresSafeArea()` on the root,
`additionalSafeAreaInsets = .zero`, and `insetsLayoutMarginsFromSafeArea =
false` are all insufficient (Apple FB8176223); the only supported off-switch is
the hosting controller's `safeAreaRegions`.

**The invariant:** every `cupertino_native_better` platform view that hosts
SwiftUI calls `UIHostingController.cnBlockSafeArea()`
(`ios/…/Utils/HostingSafeArea.swift`, sets `safeAreaRegions = []` on iOS 16.4+)
immediately after creating its hosting controller. This also subsumes the old
keyboard-avoidance fix (Issue #4) — removing only `.keyboard` left the container
region active, which is exactly how `CNSwitch` stayed exposed after its original
fix.

| Hosting platform view | Kit widgets it backs | `cnBlockSafeArea()` |
|---|---|---|
| `GlassButtonGroupView` | `KitNativeSplitButton`, `KitNativeToolbar` (glass pill) | ✅ |
| `LiquidGlassContainerView` | `KitGlassCard` (and CN's search bar / floating island glass) | ✅ |
| `CupertinoButtonPlatformView` | `KitNativeButton`, `KitNativeIconButton`, `KitNativeFab` | ✅ |
| `CupertinoSearchBarPlatformView` | `KitNativeSearchBar` | ✅ |
| `CupertinoSwitchPlatformView` | `KitNativeSwitch` | ✅ (16.4+; pre-16.4 keeps the runtime `safeAreaInsets = .zero` subclass hack) |
| `FloatingIslandPlatformView` | app-level `CNFloatingIsland` | ✅ |
| `CNNativeTabBar` | `KitNativeTabBar` | ❌ **deliberate** — docked at the screen bottom, never scrolls, lays out WITH the home-indicator inset |

Everything else in the matrix (sliders, range slider, segmented control, popup
menu, progress, toast, sheet) is UIKit-control- or Flutter-drawn — no hosted
SwiftUI, structurally immune.

**Enforcement:** the repo guard test
`test/kit/guards/cn_hosting_safe_area_guard_test.dart` fails `flutter test` for
any CN Swift file that constructs a `UIHostingController(` without calling
`cnBlockSafeArea()`. Adding a new hosting platform view? Call the helper right
after allocation; if the view *intentionally* wants safe area (docked chrome
that never scrolls), add it to the test's allowlist with a comment saying why.

**Verified (iOS 26.5 sim, appbox lens frame tracking):** pill-to-label offset
and pill-to-card-bottom gap invariant across gentle scrolls, mid-scroll parks,
and repeated hard-fling cycles; Search-tab switches pixel-identical before/after
a fling. Native (Swift) changes need a **full stop + rebuild** to test — hot
reload/restart never recompiles plugin native code, and a piped
`flutter build … | tail` masks compile failures (check the build's own exit
code).

## Scrolled under pinned chrome — `KitScrollEdgeEffect` (ADR 0010)

**Current invariant (ADR 0010): chrome never hides on scroll.** iOS 26's own
semantic is the scroll edge effect — a progressive blur/fade applied to the
*scrolling content* where it underlaps pinned chrome (`UIScrollEdgeEffect`,
automatic on system bars), never to the chrome itself. The kit mirrors it with
`KitScrollEdgeEffect` (pure Flutter): wrap the scrollable's children (or use
the `.scrollEdgeEffect()` extension sugar):

```dart
KitScrollEdgeEffect(
  edge: KitScrollEdge.top,                    // or .bottom
  style: KitScrollEdgeEffectStyle.soft,       // automatic → soft; hard = full cut
  child: ...,                                 // a child of the scrollable
)
```

- **Blur/fade tracks the covered fraction** of the child as it passes under
  pinned chrome; at `t == 0` the child builds its bare subtree (zero
  overhead). The blur is `ImageFiltered` applied to the child's own Flutter
  pixels — unlike `BackdropFilter`, it does not sample the scene, so it works
  regardless of platform views in the tree.
- **Pinned chrome is detected automatically** — the same `getOffsetToReveal`
  geometry the retired gate used (pinned slivers' `maxScrollObstructionExtent`
  folds in); `occlusionPadding` covers chrome overlaid from *outside* the
  scrollable.
- **It serves the Flutter-drawn content tier.** Platform-view glass must not
  live inside scrollables at all — the tier split (pinned chrome only) makes
  that structural; the edge effect is how content *under* the chrome reads
  correctly.
- **`KitScrollOcclusionGate` is retired from scroll duty** (public API
  unchanged) — its residual role is the blur-over-glass case: a Flutter
  `BackdropFilter` overlay that must paint over a platform view. For scroll,
  use the edge effect.

Behavior is widget-tested in
`test/kit/widgets/kit_scroll_edge_effect_test.dart`; the reviewer's objective
gate flags glass-bearing `CustomScrollView`s without `KitScrollEdgeEffect` /
`.scrollEdgeEffect()` (`review_checklist.sh` check 1i, rewritten per ADR
0010).

**Historical (why the old invariant hid glass):** pre-ADR-0010 the kit hid
scroll-occluded glass at alpha 0 because iOS hybrid-composition clipping was
unreliable during scroll (flutter/flutter #25965, #76097, #154664 — since
fixed across 2.2/3.27, with residuals #176473/#188971) and hiding was the only
robust mutator. Flutter 3.41+ made plain clips/scrims over platform views
mostly reliable, and Apple's iOS 26 semantics never hide chrome — the full
evidence base is ADR 0010.

## Route transitions — the `CNTransitionObserver` invariant

**Symptom:** during a route push/pop — most visibly the **interactive
edge-swipe back** — a native glass surface (the shared app-bar
`KitNativePopupMenu`, `KitNativeIconButton`s, `KitNativeSearchBar`,
`KitGlassCard`'s native tier…) floats as a sharp Liquid-Glass panel *over* the
sliding routes, pinned at its last position instead of sliding with its view
(the "glass leaks on the back gesture, everywhere" bug — the shared chrome rides
on every screen, so it leaks on every transition).

**Mechanism:** a `CN*` / `LiquidGlassContainer` `UiKitView` composites in a
native layer *above* the Flutter scene; during a Navigator transition it is
neither clipped nor translated with either route (hybrid composition — same
class as the scroll-under ghost above). App-bar chrome is worse than the tab
bar: the tab bar auto-hides via `CNTabBar.autoHideOnPageTransition` (its
`secondaryAnimation` resolves to the **root** shell route), but the app-bar
actions live in the leaf view **inside the nested tab navigator**, whose
`secondaryAnimation` never fires for a root-level push — so nothing tells them a
transition is running.

**The invariant — two parts (both shipped by the kit):**

*1. Every Liquid Glass widget alpha-0 HIDES during a transition — de-tinting is
not enough.* Dropping the native `.glass()` effect to a flat `.tinted()` render
still leaves the platform view **visible and floating** over the slide (a blank
flat panel — device-confirmed). The view must leave the frame. So every
`KitNative*` glass tier appends **`.chromeGated()`** (→ `KitNativeChromeGate`,
the same keepAlive alpha-0 hide the tab bar uses: opacity→0 removes the
`UiKitView` from the layer tree, restored with a fade, no native re-init). This
is baked into the kit widgets — no per-call-site code.

*2. The app registers `CNTransitionObserver` in the router's
`navigatorObservers` — the signal that drives the hide.* It exposes a Dart
`activeTransitions` `ValueListenable` (`> 0` during any push/pop/replace/remove)
and — critically — hooks `didStartUserGesture`/`didStopUserGesture` so the
**interactive back-swipe** holds the transition open (`didPop` fires only at
gesture *commit*, leaving the drag otherwise unguarded). `KitNativeChromeGate`
listens to it and hides while it is non-zero.

```dart
// app root (main.dart), feeding the KitPlatformPagesMixin router:
MaterialApp.router(
  routerDelegate: kitPlatformRouter.delegate(
    navigatorObservers: () => [CNTransitionObserver()], // re-exported by ui_library
  ),
  // …
)
```

- **Global signal, whole-app coverage.** `activeTransitions` is a static
  notifier and `auto_route` propagates the observer to nested tab/account
  navigators (`inheritNavigatorObservers`), so one root registration covers the
  nested-navigator gap that leaves leaf app-bar glass un-notified by its own
  `secondaryAnimation`. (The observer ALSO flips the native `isTransitioning`
  flag via `beginTransition`/`endTransition` — a complementary tint; the
  alpha-0 hide is what actually closes the leak.)
- **Push AND interactive pop, device-verified on iOS 26.** Before: the
  account-menu button / shop search bar leak over the slide (glass, then a flat
  panel once merely de-tinted). After: hidden across the whole drag, faded back
  in at rest — account menu, icon buttons, and content glass (search bar) alike.
- **Sibling of the other two hide gates.** `KitScrollOcclusionGate` (scroll) and
  the modal-depth path of `KitNativeChromeGate` (overlay blur) hide on their own
  signals; the transition path added here reuses the same gate. A full app gets
  all three, and `KitNativeChromeGate` now ORs modal-depth with
  `CNTransitionObserver.activeTransitions`.
- **`CNTransitionHelper.beginTransition()/endTransition()`** is the manual API
  for custom / non-Navigator transitions the observer can't see.

The reviewer's objective gate flags an app root that mounts
`MaterialApp.router` / `CupertinoApp.router` without `CNTransitionObserver`
(`review_checklist.sh` check 1z; a `// flutter-only:` no-native-glass app opts
out). The whole-matrix `.chromeGated()` contract — every glass widget wraps its
platform-view tier — is enforced two ways so a new/edited glass widget can't
silently ship un-gated: `review_checklist.sh` check **1v2** (reviewer gate, scans
the kit `lib/widgets`) and the kit test
`ui_library/test/kit/widgets/kit_glass_transition_gate_test.dart` (`// transition-exempt:`
opts a file out of both). That backstop caught `kit_native_textfield` and
`kit_glass_card` during this very change.

**Verified (iOS 26 sim, live):** account-menu push + interactive back-swipe from
Account across Shop / Train / Support / Community — the pre-fix sharp glass
panel over the slide reproduced on every transition; clean after registering the
observer.

## Sources
- Liquid Glass — [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [WWDC25 #284](https://developer.apple.com/videos/play/wwdc2025/284/)
- M3 Expressive — [Start building](https://m3.material.io/blog/building-with-m3-expressive), [Motion theming](https://m3.material.io/blog/m3-expressive-motion-theming), [Shape Morph](https://m3.material.io/styles/shape/shape-morph), [Compose M3](https://developer.android.com/develop/ui/compose/designsystems/material3)
