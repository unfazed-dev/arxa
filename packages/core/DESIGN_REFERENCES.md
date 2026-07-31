# stacked_kit — Design References (Material 3 Expressive + iOS HIG)

Authoritative spec sources for every native-chrome component the kit renders.
**Docs are the SSOT:** when a platform deprecates, renames, or re-scopes a
component, the kit follows the official reference — even when that means
diverging between iOS and Android (each OS keeps its own idiom).

Companion to [`NATIVE_COMPONENTS.md`](NATIVE_COMPONENTS.md) (the build matrix);
this file is the *why-it-looks-like-that*, with the primary URLs.

## Component → spec source

| Kit widget | Android — Material 3 (Expressive) | iOS — Human Interface Guidelines |
|---|---|---|
| `KitNativeTabBar` | [Navigation bar](https://m3.material.io/components/navigation-bar/overview) | [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) |
| `KitNativeSegmentedControl` | [Button groups (connected)](https://m3.material.io/components/button-groups/overview) — segmented button is [deprecated](https://m3.material.io/components/segmented-buttons/overview) | [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls) |
| `KitNativeButton` | [Buttons](https://m3.material.io/components/buttons/overview) | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) · [Materials / Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials) |
| `KitNativeIconButton` | [Icon button](https://m3.material.io/components/icon-button/overview) · [Buttons](https://m3.material.io/components/buttons/overview) | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) (SF Symbol via `CNButton.icon`) |
| `KitNativeSplitButton` | [Split button](https://m3.material.io/components/split-button/overview) | *(HIG has no split button — `CNGlassButtonGroup` action + menu)* |
| `KitNativeFab` | [Floating action button](https://m3.material.io/components/floating-action-button/overview) | *(HIG has no FAB — glass `CNButton`)* · [Materials / Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials) |
| `KitNativeFabMenu` | [FAB menu](https://m3.material.io/components/fab-menu/overview) (FAB→menu morph) · [FAB](https://m3.material.io/components/floating-action-button/overview) | *(HIG has no FAB — glass `CNPopupMenuButton`)* |
| `KitNativePopupMenu` | [Menus](https://m3.material.io/components/menus/guidelines) | [Menus](https://developer.apple.com/design/human-interface-guidelines/menus) (`CNPopupMenuButton`) |
| `KitNativeSearchBar` | [Search](https://m3.material.io/components/search/overview) | [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) |
| `KitNativeSwitch` | [Switch](https://m3.material.io/components/switch/overview) | [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) |
| `KitNativeSlider` | [Sliders](https://m3.material.io/components/sliders/overview) | [Sliders](https://developer.apple.com/design/human-interface-guidelines/sliders) |
| `KitNativeRangeSlider` | [Sliders](https://m3.material.io/components/sliders/overview) | [Sliders](https://developer.apple.com/design/human-interface-guidelines/sliders) *(HIG has no range slider — Material `RangeSlider`)* |
| `KitNativeAppBar` (+ sliver) | [Top app bar](https://m3.material.io/components/top-app-bar/overview) · [App bars](https://m3.material.io/components/app-bars/overview) | [Navigation bars](https://developer.apple.com/design/human-interface-guidelines/navigation-bars) |
| `KitNativeToolbar` | [Toolbars](https://m3.material.io/components/toolbars/overview) | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) |
| `KitNativeNavigationRail` | [Navigation rail](https://m3.material.io/components/navigation-rail/overview) | *(HIG has no rail — Material `NavigationRail`)* |
| `KitNativeLoadingIndicator` | [Loading indicator](https://m3.material.io/components/loading-indicator/overview) (shape-cycle) | *(HIG: `CupertinoActivityIndicator` — no morph)* |
| `KitNativeProgress` (`.linear`/`.circular`) | [Loading & progress](https://m3.material.io/components/loading-indicator/overview) | *(HIG: `CupertinoActivityIndicator` / Material linear)* |
| `KitGlassCard` | [Card](https://m3.material.io/components/cards/overview) | [Materials / Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials) (`LiquidGlassContainer`) |
| `kitShowNativeToast()` | [Snackbars](https://m3.material.io/components/snackbars/overview) (kit `SnackbarService`) | [Toast](https://developer.apple.com/design/human-interface-guidelines/toasts) (`CNToast`) |
| `kitShowNativeSheet()` | [Bottom sheets](https://m3.material.io/components/bottom-sheets/overview) | [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) (`CNBottomSheet`) |
| *(floating bottom bar — n/a)* | [Toolbars (floating)](https://m3.material.io/components/toolbars/overview) | *(tab bar floats — see Materials)* |

## Spec facts + the kit's decisions (deviations called out)

### Segmented control → **connected button group** (Android)
- **M3 Expressive deprecates the segmented button** in favour of the
  **connected button group**. So the SSOT-correct M3E widget is the button
  group, not a segmented button. Kit uses `button_group_m3e`
  (`type: connected`, `selection: true`, `equalizeWidths: true`).
- Selected segment: tonal **`secondaryContainer`** fill + `onSecondaryContainer`
  label (the M3 spec selected color), and it **shape-morphs** to a full pill;
  unselected segments are outlined. Single-select, driven by `selectedIndex`.
- **iOS:** the HIG still ships a **segmented control** — single selection,
  equal-width segments, **≤5 on iPhone**, and *don't mix text and icons in one
  control*. Kit uses the native `UISegmentedControl` (Liquid Glass) via
  `CNSegmentedControl` on iOS 26, `CupertinoSlidingSegmentedControl` below.

### Navigation bar — **full-width; no floating nav on Android**
- M3 / M3E navigation bars are **full-width, edge-to-edge**, anchored to the
  bottom, 3–5 destinations. M3 Expressive replaces the original ~80dp bar with a
  shorter **"flexible navigation bar"** (~64dp) — kit uses
  `NavigationBarM3E(size: small)`.
- The only M3E **floating** bottom element is the **Floating Toolbar**, which is
  for *actions / tabs between related subviews* and, per the docs, **must not be
  paired with a navigation bar**. So a floating *navigation* bar is **off-spec**
  on Android; the kit keeps it full-width.
- **iOS:** the HIG tab bar **"floats above content"** on Liquid Glass (a distinct
  functional layer — see Materials). The kit's iOS tier (`CNTabBar`) already
  floats. **This iOS-floats / Android-full-width split is intentional**, not a
  bug: each platform follows its own reference.

### FAB / FAB menu — HIG has no FAB
- The iOS HIG has **no floating action button** idiom — primary actions live in a
  toolbar/navigation bar or as a prominent glass button. So `KitNativeFab` renders a
  **glass `CNButton`** (prominent glass) on iOS, **not** a fake Material FAB. Android
  gets the real M3E `FabM3E` / `ExtendedFabM3E`.
- The FAB→**menu** morph (`FloatingActionButtonMenu`) is a distinct M3E component, so
  it is a **separate** kit widget — `KitNativeFabMenu` → `FabMenuM3E` (Android) / glass
  `CNPopupMenuButton` (iOS). Mirrors the split-button lesson: don't force menu params
  onto a plain action.
- **FAB metrics (Apple glass tier):** 56pt circle (M3 footprint — the CN
  defaults of 44/48pt made the FAB render smaller than the 44pt app-bar
  buttons it floats above) with a **22pt** SF Symbol glyph. 22, not the
  spec's nominal 24: SF Symbols draw ink ≈ 1.0× pointSize while Material's
  24dp icon has inner em-box padding (~16dp ink), so a 24pt SF `plus` reads
  0.44 of the circle vs Apple's own ~0.40 circular-button weight. Verified
  live on the iOS 26.5 sim (22.5pt ink / 56.3pt circle = 0.399).

### Glyph identity — `KitGlyphs` (one pair per semantic action)
- Every icon-bearing kit surface takes `glyph: KitGlyphs.<x>` (`KitGlyph` =
  Material `IconData` + SF Symbol name as ONE value; `common/kit_glyphs.dart`).
  Call sites never hand-pair `icon:`/`sfSymbol:` — that's how `'house'` vs
  `'house.fill'` drift happened. The registry owns **identity**; each surface
  owns **size** (18pt bar glyphs / FAB 22pt-in-56pt / Material 24dp on M3E) —
  `KitGlyph` deliberately has no size field, mirroring how SF Symbols take
  point size from context and Material icons from `IconTheme`.

### Switch — no M3E branch, by design
- M3 Expressive scopes `Switch` under **motion via theme** (broad), not a dedicated
  morph shape-widget — and `CNSwitch` already **self-degrades** glass → Material on its
  own. So the kit's switch is a **thin 1-way wrap**: iOS/else → `CNSwitch` (which itself
  renders Material `Switch` below iOS 26); there is **no `*_m3e` branch on Android by
  design**. Forcing one would duplicate what CN already does.

### Navigation rail — no CN rail
- `cupertino_native_better` ships no navigation rail (the idiom is iOS-tab-bar-first),
  so the iOS tier is the stock Material `NavigationRail`. Android gets the real
  `NavigationRailM3E`. **Drawer** is intentionally **not** wrapped — the rail covers the
  same idiom; see the deferred rows in `NATIVE_COMPONENTS.md`.

### Slider / range slider — iOS has no range slider
- `CNSlider` gives iOS a Liquid-Glass slider; `KitNativeSlider` is a 2-way gate
  (`SliderM3E` / `CNSlider`). The HIG has **no range slider**, so `KitNativeRangeSlider`
  renders Material `RangeSlider` on iOS and `RangeSliderM3E` on Android.

### Loading indicator / progress — morph is Android-only
- The M3E **shape-cycling `LoadingIndicator`** has no iOS counterpart (HIG uses the
  static `CupertinoActivityIndicator`), so the morph tier is Android-only; iOS falls
  back to the activity indicator. `KitNativeProgress` (`.linear`/`.circular`) follows
  the same split — Material `LinearProgressIndicator` / `CupertinoActivityIndicator`
  on iOS, `LinearProgressIndicatorM3E` / `CircularProgressIndicatorM3E` on Android.

## Sources (primary)

**Material 3 (Expressive)** — `m3.material.io` is a JS-rendered SPA; these are the
canonical component URLs:
- Navigation bar — https://m3.material.io/components/navigation-bar/overview
- Navigation rail — https://m3.material.io/components/navigation-rail/overview
- Button groups — https://m3.material.io/components/button-groups/overview
- Buttons — https://m3.material.io/components/buttons/overview
- Icon button — https://m3.material.io/components/icon-button/overview
- Split button — https://m3.material.io/components/split-button/overview
- Floating action button — https://m3.material.io/components/floating-action-button/overview
- FAB menu — https://m3.material.io/components/fab-menu/overview
- Top app bar — https://m3.material.io/components/top-app-bar/overview
- Toolbars — https://m3.material.io/components/toolbars/overview
- Sliders — https://m3.material.io/components/sliders/overview
- Search — https://m3.material.io/components/search/overview
- Switch — https://m3.material.io/components/switch/overview
- Loading indicator — https://m3.material.io/components/loading-indicator/overview
- Cards — https://m3.material.io/components/cards/overview
- Bottom sheets — https://m3.material.io/components/bottom-sheets/overview
- Snackbars — https://m3.material.io/components/snackbars/overview
- Segmented buttons *(deprecated)* — https://m3.material.io/components/segmented-buttons/overview
- Components index — https://m3.material.io/components

**iOS Human Interface Guidelines:**
- Tab bars — https://developer.apple.com/design/human-interface-guidelines/tab-bars
- Segmented controls — https://developer.apple.com/design/human-interface-guidelines/segmented-controls
- Buttons — https://developer.apple.com/design/human-interface-guidelines/buttons
- Search fields — https://developer.apple.com/design/human-interface-guidelines/search-fields
- Toolbars — https://developer.apple.com/design/human-interface-guidelines/toolbars
- Navigation bars — https://developer.apple.com/design/human-interface-guidelines/navigation-bars
- Sliders — https://developer.apple.com/design/human-interface-guidelines/sliders
- Toggles (switches) — https://developer.apple.com/design/human-interface-guidelines/toggles
- Sheets — https://developer.apple.com/design/human-interface-guidelines/sheets
- Toasts — https://developer.apple.com/design/human-interface-guidelines/toasts
- Materials (Liquid Glass) — https://developer.apple.com/design/human-interface-guidelines/materials
- Components index — https://developer.apple.com/design/human-interface-guidelines/components
