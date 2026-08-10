# Sheet identity + theme propagation to native views

Two device-reported defects in the showcase app's profile shell, investigated
2026-08-11 under `/systematic-debugging` Phase 1–3.

User report, verbatim:

> the current bottom sheet is it native as it does not seem to be a bottom
> sheet - looks similar to one but is not one
>
> when switching theme between light and dark, the liquid glass takes time to
> change, even though i am already navigating around, some liquid glass ui not
> all are still in dark even though theme is light from switching

Both reports are correct. Neither was a misreading.

---

## Bug A — the sheet is not a sheet

### What it actually is

`appBoxKitShowNativeSheet` (`kit/ui_library/lib/widgets/appbox_kit_native_sheet.dart:53`)
routes the iOS tier to `CNBottomSheet.show`. That call is, verbatim, a thin
wrapper around **Flutter's Material `showModalBottomSheet`**:

```dart
// kit/ui_library/vendor/cupertino_native_better/lib/components/bottom_sheet.dart
static Future<T?> show<T>({...}) {
  return showModalBottomSheet<T>(
    ...,
    builder: (ctx) => CNSheetGeometryProbe(child: builder(ctx)),
  );
}
```

There is **no platform channel** anywhere on this path. `CNSheetGeometryProbe`
only publishes the body's live rect to `CNTabBarRouteObserver.topModalRect` so
`ModalHideMixin` widgets can decide whether they are geometrically covered. It
adds no UI and no native presentation.

On top of that, the kit passes `backgroundColor: Colors.transparent`,
`elevation: 0`, `shape: RoundedRectangleBorder()` and renders `_GlassSheetBody`
— a `Padding(12, 0, 12, 8 + viewPadding.bottom)` around an
`AppBoxKitFrostedSurface(borderRadius: 28, blur: 30)`.

So the thing on screen is a **Material modal-bottom-sheet route with invisible
chrome, containing a floating inset frosted card**. That is precisely why it
reads as "similar to a bottom sheet but not one": it is a floating panel, not a
sheet. The name `appBoxKitShowNativeSheet` is misleading — nothing on this path
is native.

### What is available instead

The same vendored file already exposes `CNBottomSheet.showCupertino`, wrapping
Flutter's `showCupertinoSheet` — and it is **unused**.

`showCupertinoSheet` is still Dart-drawn (it never calls
`UISheetPresentationController`), but unlike the Material sheet it reproduces
the iOS stacked-card presentation in the framework. Verified against the SDK on
disk (`packages/flutter/lib/src/cupertino/sheet.dart`, Flutter 3.44.9):

- `:84` — "Amount the sheet in the background scales down. Found by measuring
  the width ... iPhone 16 pro running iOS 18.0"
- `:260` — "it will slide slightly up and scale down to appear"
- `:341`, `:373` — `scaleAnimation` applied via `Transform.scale`
- `:331-338` — border radius tweened from the device corner radius to 12
- `:819-823` — `delegatedTransition => CupertinoSheetTransition.delegateTransition`,
  which is what lets the route *behind* be transformed

A web-research subagent reported that `CupertinoSheetRoute` has "no
`UITransitionView`-driven parent scaling". That is true about the *mechanism*
and wrong about the *effect* — the SDK reproduces the visible stacked-card
result in Dart. Primary source beat the subagent; recorded here because the
distinction decides this bug.

### Swap risk — smaller than it looks

- **Only one app call site**:
  `kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_overlays_card_widget.dart:87`
  (plus two in `AppBoxKitBottomSheetService` and one in
  `AppBoxKitNotificationService`).
- **No production call site passes `backgroundColor`.** The documented
  "pre-wave-2 opt-out" branch is exercised only by
  `appbox_kit_native_sheet_test.dart:194`.
- The modal-depth bracket (`markAnyModalActive`/`markAnyModalInactive`) is
  manual and wraps whichever route is used, so it survives the swap.
- `CNSheetGeometryProbe` is injected by `showCupertino` too.

**Open risk to regression-check deliberately:** `showCupertinoSheet` pushes a
*page* route, not a `ModalBottomSheetRoute`. `AppBoxKitNativeChromeGate` now
reads `hasActiveTransitionAbove` plus the route's own animations (see
`liquid-glass-reappear-on-back.md`). That is the exact surface of the five-fix
saga, so it gets a test rather than a device discovery.

**Status: decided and shipped** — the user chose the Dart Cupertino sheet over a
bespoke `UISheetPresentationController` bridge. See "Shipped" at the end of this
document.

---

## Bug B — theme changes never reach some native views

### Root cause

Every iOS platform view in the plugin pins its own appearance:

```swift
container.overrideUserInterfaceStyle = isDark ? .dark : .light
```

`isDark` arrives from Dart as a **creation parameter**. Because
`overrideUserInterfaceStyle` isolates a subtree from inherited trait changes,
these views are immune to the window's appearance — by design.

That makes the per-view update channel the only way to change them. Most
components implement it; some do not. The split is the bug:

| Component | `isDark` at creation | Re-sends on theme change | Swift handler | Used by app |
|---|---|---|---|---|
| `button`, `icon`, `slider`, `switch`, `range_slider`, `segmented_control`, `popup_menu_button`, `tab_bar`, `native_tab_bar`, `search_scaffold`, `glass_button_group` | yes | **yes** (`setBrightness`) | yes | yes |
| `liquid_glass_container` | yes | **yes** (via `updateConfig`) | yes | yes |
| **`search_bar`** | yes (`:446`) | **NO** | **yes** (`CupertinoSearchBarPlatformView.swift:133`) | **yes** |
| **`text_field`** | yes (`:237`) | **NO** | **yes** (`CupertinoTextFieldPlatformView.swift:135`) | **yes** |
| `glass_card` (experimental) | yes | no | — | no (0 refs) |
| `floating_island` | yes | no | yes | no (0 refs) |

The Swift side of both stuck components **already implements the
`setBrightness` handler**. Dart simply never calls it.

`ThemeHelper.isDark(context)` reads `Theme.of(context)`, which registers an
inherited-widget dependency — so `didChangeDependencies` *does* fire on a theme
change. That is why the working components work, and it is the hook the two
stuck ones are missing. `search_bar.dart:250` even has a
`didChangeDependencies` already; it just does not sync brightness.

### Why both symptoms are one cause

- **"still in dark even though theme is light"** — the view keeps its
  creation-time `overrideUserInterfaceStyle` forever.
- **"takes time to change, even though I am already navigating around"** — such
  a view corrects itself only when the platform view is destroyed and recreated,
  which navigation eventually causes. The delay is the time until recreation,
  not a slow animation.

### The fix

Add the existing house idiom (`switch.dart:110,137-139,323-331`) to the two live
components:

```dart
bool? _lastIsDark;
bool get _isDark => ThemeHelper.isDark(context);

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  _syncBrightnessIfNeeded();
}

Future<void> _syncBrightnessIfNeeded() async {
  final channel = _channel;
  if (channel == null) return;
  final isDark = _isDark;
  if (_lastIsDark != isDark) {
    await channel.invokeMethod('setBrightness', {'isDark': isDark});
    _lastIsDark = isDark;
  }
}
```

Seed `_lastIsDark` where the channel is created, matching `switch.dart:284`.

**Rejected alternative — the window-level lever.** Setting
`overrideUserInterfaceStyle` on the Flutter window from Dart looks like a
one-lever fix, but every view already sets its own override, which makes them
immune to it. It would fix nothing and add a third mechanism on top of two.
Recorded because it is the obvious-looking wrong answer, and this repo has twice
disabled a correct mechanism to protect a defective one
(`conflicting-mechanisms-fix-direction`).

**Not fixing** `glass_card` and `floating_island`: zero references from either
app. Same defect, no consequence. Noted here so the omission is deliberate
rather than missed.

---

## Method notes

- Two early greps returned silent empties because they ran against
  `vendor/cupertino_native_better`, which does not exist — the real path is
  `kit/ui_library/vendor/cupertino_native_better`. An empty result from a wrong
  path reads exactly like evidence of absence. Re-run before concluding.
- `grep -c setBrightness` on `liquid_glass_container.dart` returned 0 and I
  briefly recorded it as stuck. It syncs through `updateConfig` instead. A
  single-token search is not a capability check.
- `.claude/worktrees/**` holds stale full-repo copies from prior agent runs and
  pollutes every unscoped search.

---

## Shipped (2026-08-11)

Both fixes are in. Verification: `kit/ui_library` **293/293**,
`vendor/cupertino_native_better` **121/121**, `kit/showcase_app` **119/119**,
`flutter analyze` clean in all three.

| Commit | What |
|---|---|
| `36242c3` | Bug B — `setBrightness` on theme change for `CNTextField` / `CNSearchBar` |
| `0121eaa` | Bug A — iOS sheet routed through `showCupertinoSheet`; API renamed |
| `3fdcc49` | this diagnosis + the supporting web research |
| `42a6d1d` | the three open flags from the previous fix |

### Bug A, as built

The user chose the Cupertino route over a bespoke
`UISheetPresentationController` bridge. `appBoxKitShowNativeSheet` →
`appBoxKitShowSheet` (the old name overclaimed; nothing on either tier is
native). `CNBottomSheet.showCupertino` gained `showDragHandle`/`topGap`
passthrough so the framework draws its own grabber rather than the kit painting
a second one.

Two deliberate behaviour changes, both pinned by rewritten tests:

- **No dim barrier, and an outside tap no longer dismisses.**
  `CupertinoSheetRoute.barrierDismissible` is false and its barrier is
  transparent, so `isDismissible` now maps to `enableDrag`. The scaled-back
  parent card is the separation, as on iOS.
- **The body no longer floats.** The 12 dp inset and 28 dp corners are gone;
  glass fills the sheet at `borderRadius: 0` because the route clips its own
  corners at r=12.

The old barrier-tap test did not merely fail under this — it **hung**, because
it awaited a sheet future that can never complete without a dismissible
barrier. Worth knowing: a behaviour change can turn a passing test into a hang
rather than a red.

**Android is unchanged and was already correct.** `m3e_collection` 0.3.7 *is*
the current release and ships no sheet component, and Android has no bridgeable
native sheet — its platform pattern is a Material component, which is what the
tier already renders.

### Bug B, as built

`_lastIsDark` + `didChangeDependencies` → `setBrightness`, matching the idiom
already in `switch.dart`. Both components reuse their own existing brightness
expression so the creation param and the sync cannot disagree.

**Mutation-checked:** removing the two sync calls fails the new tests while all
**119** pre-existing vendor tests stay green — they were blind to this.

Two corrections to the analysis above, both caught by re-checking rather than
by a test:

- `liquid_glass_container.dart` was first recorded as stuck. It is not; it syncs
  through `updateConfig`, so `grep -c setBrightness` returning 0 was a false
  negative. **A single-token search is not a capability check.**
- The platform-view id counter is **global and monotonic across a test file**,
  so a spy hard-coded to `<viewType>_0` observes a dead channel from the second
  test onward — which looks exactly like "the fix doesn't work". The harness
  reads the id back from the `create` call instead.
