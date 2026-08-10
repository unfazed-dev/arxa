# Slowness (symptom 4) — measured, 2026-08-10

Base commit: `c9192b7` (merged master, includes C1–C5). Every number below came out of
a command actually run in this worktree. Anything not measured is labelled **NOT MEASURED**.

Harness: `kit/showcase_app/test/slowness_measurement_test.dart` (7 tests, all passing,
`flutter analyze` clean). Run from `kit/showcase_app`:

```
flutter test test/slowness_measurement_test.dart
```

The tests print numbers; they assert only the facts the numbers depend on. They are a
measurement instrument, not a regression guard.

**Scope caveat that applies to every boot number:** the harness's `bootShell()` boots
straight into `ShowcaseApplicationHubViewRoute` (the existing showcase helper does this so
`AppData.initialize` is not re-run). `ShowcaseStartupView`, the app's real initial route, is
therefore **NOT MEASURED**. "Boot" below means *the first interactive hub frame*.

---

## 1. Cold-start / boot platform-view count — **14**

### What was measured

Every widget **element** mounted at the first interactive hub frame was tallied by walking
the live element tree (`Element.visitChildren`, which walks past `Offstage`). Each type was
then classified by whether its build actually reaches a `UiKitView(` / `AppKitView(`
constructor, established by grepping constructor call sites:

```
grep -rn 'UiKitView(\|AppKitView(\|PlatformViewLink(' --include='*.dart' \
  kit/ui_library/lib kit/ui_library/vendor/cupertino_native_better/lib
```

15 vendor component files construct one: `text_field`, `experimental/glass_card`,
`search_bar`, `popup_menu_button`, `segmented_control`, `button`, `tab_bar`, `icon`,
`search_scaffold`, `floating_island`, `range_slider`, `slider`, `glass_button_group`,
`liquid_glass_container`, `switch`. Nothing in `kit/ui_library/lib` constructs one directly —
the kit's `AppBoxKitNative*` widgets are tier selectors that delegate to these.

Two corrections were required before the number meant anything:

**(a) The headless census is a mixture, not the device tier.** `AppBoxKitNativeIconButton`
falls through to `CNButton` on any non-Android host, so it appears headless. But
`AppBoxKitNativeTabBar`/`SegmentedControl`/`SplitButton` gate on
`AppBoxKitPlatform.supportsLiquidGlass` (`= isIOS && iosMajor >= 26`,
`kit/core/lib/platform/appbox_kit_platform.dart:58`), which is false headless — so those take
the Flutter fallback and never appear. Test **M1b** forces
`AppBoxKitPlatform.override = AppBoxKitPlatformOverride(isIOS: true, iosMajor: 26,
targetPlatform: TargetPlatform.iOS)` plus `debugDefaultTargetPlatformOverride`, which
reproduces the device's widget selection.

**(b) A nested `CNIcon` is not a platform view.** The default census showed `CNIcon: 11`, all
of them inside a `CNButton` or `CNPopupMenuButton`. On device that nesting does not exist:
`CNButton`'s native branch (`vendor/.../components/button.dart:675`) is a bare
`UiKitView(viewType:, creationParams:, creationParamsCodec:, onPlatformViewCreated:,
gestureRecognizers:)` with **no Flutter children** — the icon travels as a creationParam
(SF Symbol name). The `CNIcon` children appear only in the fallback tier
(`button.dart:1136/1147/1333/1345`). The test therefore reports top-level and nested
separately.

### The numbers

| Census | Result |
|---|---|
| Headless default tiers (M1) | 22 CN\* mounted — `CNButton: 9`, `CNIcon: 11`, `CNPopupMenuButton: 2`; **11 top-level, 11 nested** |
| **iOS 26 tiers forced (M1b) — the device figure** | `CNButton: 9`, `CNPopupMenuButton: 2`, `CNSegmentedControl: 1`, `CNGlassButtonGroup: 1`, `CNTabBar: 1` = **14 top-level, 0 nested** |
| Total elements at boot, fallback tiers | 1596 |
| Total elements at boot, iOS 26 tiers | 756 |

**Boot platform-view count on device = 14.** Each is one native view creation plus a
raster/platform-thread merge on the boot path.

### The naming convention is not the marker (confirmed again)

`AppBoxKitNative*`-named widgets mounted at boot: `AppBoxKitNativeIconButton: 8`,
`AppBoxKitNativeChromeGate: 11`, `AppBoxKitNativeButton: 1`,
`AppBoxKitNativeSegmentedControl: 1`, `AppBoxKitNativeProgress: 2`,
`AppBoxKitNativeLoadingIndicator: 1`, `AppBoxKitNativeSplitButton: 1`,
`AppBoxKitNativeAppBar: 1`, `AppBoxKitNativePopupMenu: 1`, `AppBoxKitNativeFabMenu: 1`,
`AppBoxKitNativeTabBar: 1` — 28 instances across 11 types.

Of these, `AppBoxKitNativeProgress` (2), `AppBoxKitNativeLoadingIndicator` (1),
`AppBoxKitNativeAppBar` (1, → `CupertinoNavigationBar`; its own doc at
`appbox_kit_native_app_bar.dart:16` says the CN tier is pure Flutter) and
`AppBoxKitNativeChromeGate` (11, a gate, not a surface) contribute **zero** platform views.

The plan doc's "Home has **5** platform views" is not contradicted so much as differently
scoped: 14 is the whole first interactive hub frame (tab bar + app bar chrome + FAB menu +
body), not the home body alone. The 5-vs-8 correction there remains right about its own claim;
the boot-path total is 14.

---

## 2. Tab-shell inflation eagerness — **lazy; 4 widget allocations, 1 inflation**

### Mechanism (read)

`stacked-3.5.0/lib/src/router/widgets/stacked_tabs_router.dart`,
`_AutoTabsRouterBuilderState.build()`:

```dart
final stack = _controller!.stack;
...
List.generate(stack.length, (index) => KeepAliveTab(key: ValueKey(index), page: stack[index]))
```

`stack` is `_pages`, populated once by `setupRoutes` → `_pushAll` →
`_pages.add(pageBuilder(data))` (`routing_controller.dart:481-506`), called from
`_setupController` at initState. `pageBuilder` is the generated
`app.router.dart:93-125`, which constructs the shell widget instance
(`ShowcaseHomeShellView(key: args.key)` …) — **once at controller setup, not per frame**.
`KeepAliveTab.build()` calls `widget.page.buildPage(context)`; that is where the shell
widget actually enters the tree, and it only runs if the element is inflated.

So per host rebuild the router allocates **4 `KeepAliveTab` objects** (two fields each).

### Measurement (M2)

```
[M2] mounted shell elements at boot: home=1 search=0 profile=0 notes=0
[M2] KeepAliveTab elements mounted = 1
[M2] AppBoxKitAnimatedTabStack elements = 1
[M2] NestedRouter elements = 1
[M2] total elements in tree at boot = 1596
```

`find.byType` walks the element tree, so a widget the router built but never mounted does not
appear. Three of the four shells are absent.

### Verdict — count without consequence

The router does **not** build four tab shell trees per frame. It allocates four cheap wrapper
objects; `AppBoxKitAnimatedTabStack` inflates only the visited index, so three of the four
`KeepAliveTab`s never reach `build()` — no ViewModel construction, no `NestedRouter`, no shell
widget tree. Only **one** `NestedRouter` and **one** `KeepAliveTab` element exist at boot.
**This is not a slowness source.**

---

## 3. Per-frame rebuild sources during scroll

Exhaustive enumeration. The broad grep
`grep -rn 'NotificationListener\|addListener(' --include='*.dart' kit/showcase_app/lib
kit/ui_library/lib` (excluding doc comments) returns **6 hits total, and zero
`NotificationListener` of any kind** — no `NotificationListener<ScrollNotification>`, no bare
`NotificationListener(`, no `ScrollMetricsNotification`. All 6 are:

| Site | Status |
|---|---|
| `appbox_kit_scroll_edge_effect.dart:128` → `_recompute` | measured below (M3a/M3b/M5) |
| `appbox_kit_scroll_occlusion_gate.dart:134` → `_recompute` | C6, already measured fine — not re-chased |
| `appbox_kit_scroll_occlusion_gate.dart:118` → `_onModalDepthChanged` | modal notifier, not scroll-driven |
| `appbox_kit_native_chrome_gate.dart:149` → `_onDepthChanged` | modal notifier, not scroll-driven |
| `appbox_kit_native_chrome_gate.dart:150` → `_onDepthChanged` | transition notifier, not scroll-driven |
| `appbox_kit_chip_carousel.dart:72` → `_updateFades` | source-verified negative (below) |

So exactly **two** scroll-position listeners exist in the whole codebase, and one of them
(C6) is already closed.

### M3a — does the scroll-frame `setState` reach the child? **No.**

`_KitScrollEdgeEffectState._recompute` quantises `t` to 1/50 steps and returns early when
unchanged (`:180`), then `setState`s. Its `build()` returns
`IgnorePointer > Opacity > ClipRect > _EdgeEffectBlur > widget.child`.

The probe was placed twice: once as an identical instance handed to
`AppBoxKitScrollEdgeEffect` as `child` (the real usage), once rebuilt inline by a control that
`setState`s on every scroll frame. 300 scroll steps:

```
[M3a] scroll steps = 300
[M3a] child rebuilds UNDER AppBoxKitScrollEdgeEffect = 0
[M3a] control rebuilds (inline-constructed child) = 300
[M3a] frames with a LIVE blur/saveLayer (Opacity < 1) = 115
```

**0 vs 300.** `widget.child` is the same instance every rebuild, so `Element.updateChild`
short-circuits and the subtree does not rebuild. The `setState` count is a count without
consequence *for UI-thread build work* — same shape as the previously corrected audit claims.

### M3b — the real home list: **nothing fires**

```
[M3b] AppBoxKitScrollEdgeEffect instances on home = 2
[M3b] frames (of 200) with a LIVE blur/saveLayer = 0
[M3b] total elements before=1596 after=1596
[M3b] platform-view-backed count before=22 after=22
```

Over 200 scroll steps on the actual home tab the effect never engages, no elements are
created or destroyed, and the platform-view count is invariant. (The 22 here is the
fallback-tier census; the device figure is 14 per §1 — invariance is the point, not the
magnitude.) **The home tab has no measurable Dart-side scroll cost.**

### M5 — the Notes folder list: blur live every frame, but **nothing native under it**

`showcase_notes_folder_view.mobile.dart:182-183` chains `.scrollEdgeEffect()` twice per group
(top edge, then bottom edge with `occlusionPadding: kShowcaseTabBarBlockHeight`). Run with
the iOS 26 tier override, since §1 showed the tiers change the tree structurally:

```
[M5] AppBoxKitScrollEdgeEffect instances mounted on notes folder = 15
[M5] total elements on notes folder = 2050
[M5] scroll distance = 200 steps x 2px = 400px, monotonically down
     (hysteresis: enter 0.04, exit 0.01 — once engaged it stays engaged)
[M5] frames (of 200) with >=1 LIVE blur/saveLayer = 200
[M5] max SIMULTANEOUS live blur layers in one frame = 4  (of 15 mounted -> 11 never go live)
[M5] PLATFORM VIEWS under a LIVE blur: max in one frame = 0; frames with >=1 = 0
```

`Opacity < 1` is exactly equivalent to `sigma > 0` here — both are driven by the same `t`
(`alpha = 1 - 0.85t`, `sigma = 8t`, `:188-189`) — so a frame with `Opacity < 1` is a frame in
which `_EdgeEffectBlur` pushes an `ImageFilterLayer(ui.ImageFilter.blur(...))` (`:263-267`)
**and** `Opacity` forces a `saveLayer`.

**Read 200/200 with two caveats, or it overstates.** The gesture is 400px monotonically
downward and never returns to the top; the hysteresis (enter 0.04 / exit 0.01) means that once
engaged it *should* stay engaged. So 200/200 is what a correctly-working scroll-edge effect
produces for this gesture — it is not by itself evidence of a defect. And M3b used 1px steps
(200px total), so home-vs-notes is not a clean distance-matched A/B.

**The lead this was chasing is dead.** The reason a live blur over this list would matter is
the documented hybrid-composition pathology the kit's own docs cite
(`appbox_kit_animated_tab_stack.dart:60`, `appbox_kit_directional_tab_transition.dart:6`;
flutter#24164 / #148639): an `ImageFilterLayer` + `saveLayer` over a `UiKitView`. Measured
under device tiers, **zero platform views are ever under a live blur** — 0 in every one of the
200 frames. It is a plain Flutter blur over plain Flutter content. That is an ordinary raster
cost, not the defect.

Also measured, and a negative in its own right: **11 of the 15 mounted effects never go
live**. The plan doc's "chains it twice per row → 15 instances" concern is mostly inert —
`RenderOpacity` short-circuits at alpha 255 and `_EdgeEffectBlur` returns `super.paint` at
sigma 0 (`:259-262`), so dormant effects cost essentially nothing.

Its raster time is still **NOT MEASURED** (see §5b), but the reason to prioritise it is gone.

### M6 — `AppData.initialize` on the boot path: **~3 ms**

The seed-backend asset read + JSON parse + fake auth runs on the real boot path but is hoisted
into `setUpAll`, so it is excluded from every element count above. Timed directly:

```
[M6] AppData.initialize microseconds, 3 runs = [11187, 3144, 2703]
```

11.2 ms cold, then ~2.7–3.1 ms warm — on host disk, not device flash, and Dart work only.
**Negligible.** This bounds, and does not measure, on-device cold start, but it removes the
data layer from the list of cold-start suspects.

---

## Measured NOT to be a problem — do not re-chase

1. **Tab-shell eagerness.** The `stacked` router builds 4 `KeepAliveTab` objects but inflates
   1. Shell elements at boot: home 1, search 0, profile 0, notes 0. (M2)
2. **`AppBoxKitScrollEdgeEffect`'s per-scroll `setState`.** 0 descendant rebuilds against a
   300-rebuild control. `widget.child` identity short-circuits `updateChild`. (M3a)
3. **Home-tab scrolling.** 0/200 frames with a live blur; zero element churn; platform-view
   count invariant across the scroll. (M3b)
4. **`AppBoxKitNative*` naming as a platform-view proxy.** 28 `AppBoxKitNative*` instances at
   boot map to 14 platform views. `AppBoxKitNativeProgress`, `AppBoxKitNativeLoadingIndicator`,
   `AppBoxKitNativeAppBar` and `AppBoxKitNativeChromeGate` contribute zero. (M1/M1b)
5. **Nested `CNIcon` inside `CNButton`/`CNPopupMenuButton`.** 11 headless, 0 on device — the
   native button is a childless `UiKitView` and the icon is a creationParam
   (`button.dart:675`). (M1b, source-verified)
6. **`AppBoxKitChipCarousel._updateFades`** (`appbox_kit_chip_carousel.dart:72`).
   Source-verified negative, **not runtime-measured**: the listener is edge-triggered — it
   only `setState`s when one of `hasOverflow`/`canBack`/`canForward` actually flips, so it is
   not a per-frame rebuild. It is also only mounted on the profile tab, not on the boot path.
7. **Platform views under a live blur on the Notes folder list — zero.** The documented
   hybrid-composition pathology (flutter#24164 / #148639) does **not** occur here; 0 platform
   views under a live `ImageFilterLayer` in all 200 measured frames, under device tiers. (M5)
8. **Scroll-edge instance density on the Notes list.** 11 of 15 mounted effects never engage;
   dormant ones short-circuit in `RenderOpacity`/`_EdgeEffectBlur`. (M5)
9. **`AppData.initialize` as a cold-start suspect.** ~2.7–11 ms of Dart work. (M6)
7. Everything on the plan doc's existing "Verified negatives" list (C6 occlusion gate, the
   `PlatformViewGuard` 500 ms debug swap, per-frame method-channel traffic, the tab bar's
   deliberate nil appearance, the §3d tab-stack fade claim) was not re-investigated.

---

## 5. NOT MEASURABLE HEADLESS — and how to measure it on device

Widget tests measure UI-thread build/element work only. Three things the user reports live
outside that boundary:

**(a) Cold-start wall clock.** No headless equivalent exists; `bootShell` also skips the real
initial route. Measure with:
```
flutter run --profile --trace-startup --target lib/main.dart
```
then read `build/start_up_info.json`: `timeToFirstFrameRasterizedMicros` is the number that
matches the user's complaint (`timeToFrameworkInitMicros` /
`timeToFirstFrameMicros` split tells you whether the cost is Dart init or the first raster).
Take 5 cold runs after a device reboot; compare against a build with the 14 platform views
stubbed to Flutter tiers (`AppBoxKitPlatform.override` accepts `iosMajor: 25` at runtime,
which flips every `supportsLiquidGlass` gate) — that A/B isolates the platform-view boot cost
without changing anything else.

**(b) Raster-thread cost of the always-live Notes blur.** `flutter run --profile` + DevTools
Performance, scrolling the Notes folder list. The discriminator is the **UI vs raster thread
split**: M3a/M3b/M5 prove UI-thread build work is ~zero, so if frames are dropping, the
raster bar is where it will show. Confirm by toggling `.scrollEdgeEffect()` off on
`showcase_notes_folder_view.mobile.dart:182-183` and re-measuring the same scroll.

**(c) True on-device platform-view count.** Add a `NSLog`/`debugPrint` in the iOS platform-view
factory's `create` (the `FlutterPlatformViewFactory` implementations in
`kit/ui_library/vendor/cupertino_native_better/ios/`) and count lines to first interactive
frame. This validates the 14 above against reality, including anything the tier override
model got wrong.

---

## Bottom line

**No Flutter-side mechanism was found that explains the reported slowness.** That is the
result, not a placeholder for one.

- Boot platform views: **14** (measured, device tier selection simulated). This is the only
  finding with a plausible route to the symptom, and its cost is unmeasured — it is a
  *quantity*, not yet a *cost*.
- Tab-shell eagerness: **not a problem** — 4 cheap allocations, 1 inflation.
- Scroll rebuilds: **zero** propagate. Both scroll-position listeners in the entire codebase
  are either edge-triggered or short-circuited by `widget.child` identity (0 vs 300 control).
- The Notes folder's always-live blur was the leading candidate and **was measured out**: no
  platform view is ever underneath it, so the documented hybrid-composition pathology does not
  apply. It remains a plain Flutter blur whose raster time is unmeasured, but there is no
  longer a reason to rank it first.
- `AppData.initialize`: ~3 ms. Not a cold-start suspect.

If the symptoms persist on device, the surviving candidates are all outside the headless
boundary: raster-thread compositing of the 14 boot platform views, native-side view creation
cost, and engine-level cold start. §5 says exactly how to measure each. Nothing further should
be "fixed" on the Flutter side without one of those numbers first — three prior audit claims
in this project were located correctly and wrong about consequences, and every candidate this
pass produced went the same way.
