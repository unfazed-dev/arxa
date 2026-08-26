# Flutter platform views on iOS — best practices, and how cupertino_native expects to be wired

Research doc. Read-only investigation; no code was changed to produce it.
Written against repo HEAD `34c53b0`, 2026-08-10.

## How to read the evidence tiers

Every claim below is tagged, because the tiers are not equally trustworthy:

- **[V]** — Verified. I fetched the page and read the text quoted.
- **[S]** — Search-summary only. Came from a WebSearch result summarizing a page I did
  **not** open. Issue numbers and version-regression lists in this tier are plausible
  but unconfirmed — verify before acting on them.
- **[R]** — Repo corroboration. Read directly out of this checkout at HEAD.
- **[I]** — Inference. Follows logically from [V] facts, but no source states it. Sound
  reasoning is still not a citation; flagged so it can be argued with.

Do not promote an [S] claim to a rule without opening the source first.

---

## 1. Flutter official docs and engine: iOS platform views

### 1.1 iOS has exactly one mode, and it is hybrid composition

> "iOS only uses Hybrid composition, which means that the native `UIView` is appended to
> the view hierarchy."

**[V]** — [Host native iOS views in your Flutter app with platform views](https://docs.flutter.dev/platform-integration/ios/platform-views)
(page states it reflects Flutter 3.44.7, last updated 2026-07-17).

Consequences worth internalizing:

- There is no iOS equivalent of Android's mode selection. No Virtual Display, no TLHC
  (Texture Layer Hybrid Composition), no HCPP. Those are **Android-only** concepts. **[V]**
  for TLHC being filed under `android/` in the engine docs tree; **[S]** for HCPP/Vulkan
  specifics.
- Dart-side API is `UiKitView` with `viewType`, `layoutDirection`, `creationParams`, and
  `creationParamsCodec`. **[V]** (same page, code sample).
- The native `UIView` is genuinely in the UIKit hierarchy — which is exactly why z-order
  against Flutter-drawn content is a recurring source of bugs (see §2.3).

### 1.2 The threading cost — the one real "cost model" statement

The engine doc is the primary source for *why* platform views cost something:

> "in a typical Flutter app, the Flutter UI is composed on a dedicated raster thread. This
> allows Flutter apps to be fast, as the main platform thread is rarely blocked. While a
> platform view is rendered with Hybrid Composition, the Flutter UI is composed from the
> platform thread, which competes with other tasks like handling OS or plugin messages, etc."

**[V]** — [Flutter engine `docs/platforms/Hybrid-Composition.md`](https://flutter.googlesource.com/mirrors/flutter/+/refs/tags/3.32.6/docs/platforms/Hybrid-Composition.md)
(tag 3.32.6).

Read that carefully. The cost is **not** primarily "a platform view is slow to draw." The
cost is that mounting *any* platform view moves Flutter's compositing onto the platform
(main) thread, where it now contends with OS and plugin message handling. That is a
whole-screen, whole-app property, not a per-widget one.

Caveat on scope: this Performance section sits in an engine doc whose surrounding
paragraphs are Android-specific (the pre-Android-10 per-frame graphics-memory copy, and
the Virtual Display comparison, are explicitly Android). The thread-migration sentence is
stated as a general property of hybrid composition, and iOS is hybrid-composition-only, so
it applies — but note the doc was not written iOS-first.

### 1.3 The only mitigation the docs actually offer

> "you could use a placeholder texture while an animation is happening in Dart. In other
> words, if an animation is slow while a platform view is rendered, then consider taking a
> screenshot of the native view and rendering it as a texture."

**[V]** — both the iOS docs page and the engine doc carry this identical guidance.

This is the entire official mitigation story. It is three sentences. It is also, notably,
*exactly* the shape of the problem arxa hits during tab transitions (§3.2).

### 1.4 Composition limitations — hard constraints

> - "The `ShaderMask` and `ColorFiltered` widgets are not supported."
> - "The `BackdropFilter` widget is supported, but there are some limitations on how it can
>   be used."

**[V]** — [iOS platform views docs, "Composition limitations"](https://docs.flutter.dev/platform-integration/ios/platform-views#composition-limitations),
which links to the [iOS Platform View Backdrop Filter Blur design doc](https://flutter.dev/go/ios-platformview-backdrop-filter-blur).

These are the sharpest constraints on the page. Any design that wants to tint, mask, or
blur a region containing native chrome is fighting the framework, not tuning it.

### 1.5 Negative finding: there is no per-screen platform-view budget

The brief asked "how many platform views per screen is sane." **The official docs give no
number, no budget, and no threshold.** They give the three-sentence Performance section
quoted above and nothing else. Anyone who cites "N platform views per screen" as a Flutter
guideline is inventing it.

What *can* be said, and is defensible from §1.2: the meaningful threshold is **zero versus
non-zero**, not 3 versus 8. The thread migration happens once the screen contains any
platform view. Adding a second and third native control to a screen that already has one
does not re-pay that architectural cost — it adds incremental native layout/compositing
work on an already-migrated thread. So the design question is "which screens are native-
chrome screens at all," not "have we exceeded the platform-view quota."

### 1.6 Reported flicker and lifecycle bugs — treat as leads, not facts

All **[S]**, from WebSearch summaries. Each needs opening before it's load-bearing:

| Issue | Claim | Relevance |
|---|---|---|
| [flutter#48632](https://github.com/flutter/flutter/issues/48632) | Changing `creationParams` does not rebuild a `UiKitView`; forcing recreation via `key` is the workaround, and it flickers | The core "don't recreate, message instead" lead |
| [flutter#163498](https://github.com/flutter/flutter/issues/163498) | iOS: animations cause Flutter UI flicker / platform view visible on foregrounding; summary lists 3.27.4 / 3.29.0 / 3.32.5 / 3.35.1 with Impeller as broken | Version list is **unverified** — do not quote it as fact |
| [flutter#148639](https://github.com/flutter/flutter/issues/148639) | Memory leak with `IndexedStack` containing a `UiKitView` | Directly relevant to kept-alive tab stacks; **corroborated in-repo**, see §3.2 |
| [flutter#46147](https://github.com/flutter/flutter/issues/46147) | Crash embedding a `UiKitView` in a `TabBarView` | Same family |
| [flutter#110381](https://github.com/flutter/flutter/issues/110381) | `PlatformException(recreating_view, ...)` after hot restart; keys don't fix it | Explains hot-restart noise during dev |
| [flutter#57397](https://github.com/flutter/flutter/issues/57397) | `IndexedStack` builds hidden children | Why off-screen tabs still hold native views |

The consistent thread across these: **platform-view identity and lifecycle are where the
bugs live**, not raw draw performance.

---

## 2. Upstream `cupertino_native`, and the fork this repo actually ships

### 2.1 Upstream is explicit that it is a proof of concept

> "This plugin hosts real UIKit/AppKit controls inside Flutter using Platform Views and
> method channels."
>
> "Does it work and is it fast? Yes. Is it a vibe-coded Frankenstein's monster patched
> together with duct tape? Also yes."
>
> "This package is a proof of concept for bringing Liquid Glass to Flutter. ... The vision
> for this package is to bridge the gap until we have a good, new Cupertino library written
> entirely in Flutter."

**[V]** — [pub.dev/packages/cupertino_native](https://pub.dev/packages/cupertino_native)
(v0.1.1, publisher serverpod.dev) and the mirrored
[GitHub README](https://github.com/serverpod/cupertino_native).

Upstream also documents that macOS "compiles and runs, but it's untested with Liquid Glass
and generally doesn't look great," and lists combining scroll views with native components
as future work. **[S]** (search summary of the README's status section).

Take the self-assessment at face value when planning: upstream is a starting point, not a
hardened dependency.

### 2.2 Upstream's intended `CNTabBar` wiring

```dart
int _tabIndex = 0;

// Overlay this at the bottom of your page
CNTabBar(
  items: const [
    CNTabBarItem(label: 'Home', icon: CNSymbol('house.fill')),
    CNTabBarItem(label: 'Profile', icon: CNSymbol('person.crop.circle')),
    CNTabBarItem(label: 'Settings', icon: CNSymbol('gearshape.fill')),
  ],
  currentIndex: _tabIndex,
  onTap: (i) => setState(() => _tabIndex = i),
)
```

**[V]** — identical snippet on pub.dev and GitHub.

Two things this tells us about intended usage:

1. **State is pushed in as a prop** (`currentIndex`), not held natively. The widget is
   meant to be a controlled component: Flutter owns the selected index; the native view is
   told about it. This is the "message the existing view" model, not the "recreate with a
   new key" model.
2. **"Overlay this at the bottom of your page"** — the comment is upstream's own. It
   expects the bar to be composed *over* page content, which is the natural fit for a
   root-level persistent chrome layer.

Upstream does **not** document a per-screen platform-view budget, a recreation policy, or
any explicit performance caveat beyond the proof-of-concept framing. That is a gap, not a
green light.

### 2.3 The vendored fork documents what upstream doesn't

This repo vendors `cupertino_native_better` at
`kit/ui_library/vendor/cupertino_native_better/` **[R]**, so the fork's caveats are the
operative ones. Its README is far more forthcoming than upstream's.

**The z-order problem, stated plainly:**

> "iOS 26 Liquid Glass widgets are native `UIView`s composited under Flutter via hybrid
> composition. Without coordination, their drop shadow / soft-edge halo can bleed through
> any sheet or popup pushed over the page, and `CNTabBar` can render above modal content
> (e.g. making a `TextField` inside a sheet invisible)."

**[V]** — [pub.dev/packages/cupertino_native_better](https://pub.dev/packages/cupertino_native_better)
(v1.5.4, publisher gunumdogdu.com).

**The prescribed fix is a single app-wide `NavigatorObserver`:**

```dart
CupertinoApp(navigatorObservers: [CNTabBarRouteObserver()])
// or MaterialApp(navigatorObservers: [...])
// or GoRouter(observers: [CNTabBarRouteObserver()])
```

**[V]**. With it registered, `CNTabBar` auto-hides under a full-screen sheet (their Issue
#31), and glass widgets clamp their halo under any modal (Issues #29, #36).

**v1.5.1 escalates the fix to destroy-and-recreate:** when a bottom sheet covers a
CN-widget, the package "destroys the host-page widget's PlatformView (with a same-size
placeholder reserving the layout slot) while the sheet is up, then recreates it on
dismiss," and the sheet must publish its rect each frame (via `CNBottomSheet` wrappers or
`CNSheetGeometryProbe`) for this to be position-aware rather than route-wide. **[V]**
(their Issue #53.) Each widget carries `autoHideOnModal: bool = true` to opt out.

Note the significance: the fork's own answer to a z-order bug is **deliberate platform-view
destruction**, with a placeholder holding layout. That is §1.3's "placeholder texture"
advice, arrived at independently.

**Non-route overlays are a known blind spot.** `Scaffold.showBottomSheet` is anchored to
`ScaffoldState`, not pushed on the Navigator, so the observer never sees it; the package
exposes manual `markAnyModalActive` / `markAnyModalInactive` hooks. **[V]**

This repo already depends on that hook: `kit/ui_library/lib/utils/arxa_kit_native_overlay.dart`
runs a full-screen Flutter overlay with every CN platform view hidden, precisely because a
GetX snackbar is an `Overlay` entry rather than a route, so `CNTabBarRouteObserver` "never
fires on its own." **[R]**

### 2.4 `CNTabBar` vs `CNTabBarNative` — the fork's explicit warning

The fork ships two different tab bars and is emphatic about which one a normal app wants:

|  | `CNTabBar` (widget) | `CNTabBarNative` (native takeover) |
|---|---|---|
| Where it lives | In your Flutter widget tree | Presented natively over/instead of your app |
| Each tab's content | **Your Flutter screens** (you own navigation) | Native lists / native search / **one** root-mode Flutter surface |
| Platforms | iOS (Liquid Glass on 26) + Flutter fallback elsewhere | **iOS 26 only** (no-op otherwise) |
| Best for | **A normal app** — Flutter screens per tab | Showcasing iOS 26 chrome: minimize, native search, accessory |

> "⚠️ **Do _not_** use `CNTabBarNative` as a drop-in for a Flutter bottom nav — e.g. calling
> `enable()` in `initState` and driving an `IndexedStack` / `Scaffold.bottomNavigationBar`
> from `onTabSelected` → `setState`. That creates **two sources of truth** for the selected
> tab (the native bar _and_ your Flutter state), which causes the 'have to tap twice'
> behavior and screen rebuilds. For Flutter screens per tab, use **`CNTabBar`**."

**[V]** — both table and warning quoted from the fork's README.

This is the single most actionable finding in the whole document. It is a documented,
named failure mode ("tap twice" + spurious screen rebuilds) with a documented cause
(duplicated selection state) and a one-word fix (use the widget, not the takeover).

`CNTabBarNative` drives updates through an imperative method API — `setItems`,
`setSelectedIndex`, `setBadgeCounts`, `setBottomAccessory`, `setStyle`, `setBrightness`,
`setMinimizeBehavior` — with callbacks including `onTabSelected` and `onDismissed`. **[V]**
That API shape confirms the intended model across the whole package: **one long-lived
native view, mutated by messages.** Nothing in either package's API suggests recreation as
a state-sync mechanism.

---

## 3. Native tab bar + Flutter nested navigation

### 3.1 The structural rule: chrome above the Navigator, never inside it

The pitfall named in the brief is real and follows directly from §1.6's lifecycle bugs: if
the platform-view widget lives **inside** the route subtree, then every push/pop that
replaces that subtree destroys and recreates the native view. You pay view teardown +
construction on every navigation, and you get the flicker of §1.6 on every transition.

The correct shape is a persistent shell: native chrome mounted once at the root, with a
per-tab `Navigator` (or `StatefulShellRoute.indexedStack` under go_router) *below* it.
Routes push inside a branch; the chrome above never unmounts. **[S]** for the go_router
`StatefulShellRoute.indexedStack` pattern being the standard modern approach; the
structural reasoning is mine, grounded in [V] §1.1 and §2.2.

Upstream's own "overlay this at the bottom of your page" **[V]** is consistent with this:
the bar is a sibling of the content, not a child of the routed subtree.

### 3.2 The counter-pressure: keeping tabs alive keeps native views alive

The obvious implementation of a persistent shell — `IndexedStack` — has a documented cost
when platform views are involved. `IndexedStack` builds and retains hidden children
(**[S]**, flutter#57397), so a native view in an inactive tab stays alive off-screen, which
is the reported `IndexedStack` + `UiKitView` memory leak (**[S]**, flutter#148639).

This repo has already hit it and written the finding down.
`kit/ui_library/lib/widgets/arxa_kit_tab_switch_transition.dart` **[R]**:

> "**Platform-view caution:** prefer `fade: false` (the default) over tabs that mount
> platform views (`ArxaKitNative*` / UiKitView chrome). Opacity-animating a platform-view
> subtree forces per-frame native layer mutations, and the outgoing tab's UIViews linger
> frame-submit-gated (flutter#148639) — the ghosting P2 verified on the iOS 26 simulator.
> The slide is the smaller mutation surface; re-verify on device when the tabs carry native
> chrome."

`kit/ui_library/lib/widgets/arxa_kit_directional_tab_transition.dart:6` carries the
matching warning that "Fade/slide-animating a platform-view subtree forces" the same
per-frame native mutations. **[R]**

So the in-repo position is empirically established, not theoretical: **animating opacity
across a platform-view subtree is the expensive mistake**, and translation is the cheaper
one. That is a stronger, more specific claim than anything in the official docs, and it was
verified on the iOS 26 simulator.

### 3.3 Where the two pressures meet

There is a genuine tension, and it should be named rather than resolved by fiat:

- §3.1 says *keep the native view mounted* (avoid recreation flicker).
- §3.2 says *mounted-but-hidden native views leak and ghost*.

The reconciliation that both the docs (§1.3) and the vendored fork (§2.3) converge on:
keep **one** long-lived native chrome view at the root that never unmounts, and for native
views inside *swappable content*, destroy them deliberately with a placeholder holding the
layout slot rather than leaving them mounted-but-hidden. Persistent chrome and persistent
*content* platform views are different problems with different answers.

---

## 4. `FutureBuilder` futures built in `build()` — a confirmed platform-view teardown loop

This section was added after the initial pass, on a follow-up question. It is the most
actionable finding in the document, and both halves of it are **[V]** / **[R]** — not
inference.

### 4.1 The mechanism, from the official API docs

> "The `future` must have been obtained earlier, e.g. during `State.initState`,
> `State.didUpdateWidget`, or `State.didChangeDependencies`. **It must not be created during
> the `State.build` or `StatelessWidget.build` method call** when constructing the
> `FutureBuilder`. If the `future` is created at the same time as the `FutureBuilder`, then
> every time the `FutureBuilder`'s parent is rebuilt, the asynchronous task will be
> restarted."

> "**a side-effect of this is that providing a new but already-completed future to a
> `FutureBuilder` will result in a single frame in the `ConnectionState.waiting` state.**
> This is because there is no way to synchronously determine that a `Future` has already
> completed."

**[V]** — [`FutureBuilder` API docs](https://api.flutter.dev/flutter/widgets/FutureBuilder-class.html)
(emphasis added).

The second quote is the one that matters here, and it is worse than the usual "you restart
your network call" framing. **Caching does not save you.** Even when the future resolves
instantly from a warm cache, a *new* future instance yields one guaranteed frame in
`waiting`. If the builder's `waiting` branch returns a placeholder instead of the platform
view — which is the normal way to write it — then that one frame **unmounts the
`UiKitView`**. The next frame mounts a *new* one, with a new view id.

Net effect per parent rebuild: full native view teardown plus construction. This is exactly
the recreation-instead-of-messaging antipattern from Rule 1, arrived at by accident rather
than by a misused `key`. It also matches the docs' own warning that "every `build` method
could get called every frame."

### 4.2 The vendored package does this, in the components that render native views

**[R]**, read at HEAD `34c53b0` from
`kit/ui_library/vendor/cupertino_native_better/lib/components/`:

```dart
// button.dart:384 — future constructed inline in build()
return FutureBuilder<String>(
  future: resolveAssetPathForPixelRatio(widget.imageAsset!.assetPath),
  builder: (context, snapshot) {
    if (!snapshot.hasData) {
      return SizedBox(height: defaultHeight, width: ...);   // ← no platform view
    }
    return _buildNativeButton(context, imageAsset: resolvedImageAsset); // ← platform view
  },
);
```

Confirmed occurrences of the same shape:

| File | Lines | Branch |
|---|---|---|
| `button.dart` | 384, 412 | `imageAsset`, `customIcon` |
| `icon.dart` | 138, 167 | `imageAsset`, `customIcon` |
| `popup_menu_button.dart` | 362, 369, 385 | nested — three deep |
| `glass_button_group.dart` | 266 | list of param maps |

Scope caveat **[I]**: these are the `imageAsset` and `customIcon` branches. A plain
SF-Symbol (`CNSymbol`) button appears to take a synchronous path and should not be
affected. But arxa renders lucide SVG icons through the custom-icon path, so the
affected branch is plausibly this app's *hot* path — worth confirming against actual call
sites before sizing the fix.

### 4.3 The package already fixed this — in exactly one component

`tab_bar.dart` hoists all async work out of `build()` and stores the result, with a comment
naming the failure mode **[R]**:

> "All async work (icon rendering, asset path resolution) happens here, guarded by the
> generation token in the caller. The result is stored in `_creationParams` so that `build`
> can construct the platform view **synchronously — eliminating the nested-`FutureBuilder`
> race that caused duplicate platform-view creation attempts**."

So the correct pattern is established *inside the vendored package itself*: resolve async
inputs in `initState` / `didUpdateWidget`, store them in state, and let `build` construct
the `UiKitView` synchronously every time. `tab_bar.dart` got this treatment; `button.dart`,
`icon.dart`, `popup_menu_button.dart`, and `glass_button_group.dart` did not.

That asymmetry is the fix roadmap. It is a port of a pattern the upstream fork already
wrote, not new design work — and "duplicate platform-view creation attempts" in their own
words is the symptom to expect where it hasn't been ported.

### 4.4 Why this compounds with §3.2

A rebuild-triggered teardown/recreate on every parent rebuild is bad on its own. During a
*tab transition* it is much worse: §3.2 established that the outgoing tab's UIViews already
linger frame-submit-gated (flutter#148639, simulator-verified). Add a per-rebuild
teardown/recreate cycle on top of an animation that rebuilds every frame, and you get
native view churn at frame rate precisely when the compositor is most contended (§1.2, the
platform thread is doing the compositing). Fixing §4 is likely a prerequisite for §3.2's
transitions ever being smooth, not an independent cleanup.

---

## Rules for arxa

Each rule tagged with the strongest evidence backing it.

1. **Never force platform-view recreation via `key` to sync state.** Push updates into the
   live view over the method channel. `CNTabBar` already models this with `currentIndex` as
   a prop. — **[V]** §2.2, **[V]** §2.4 (imperative setter API), **[S]** flutter#48632.

2. **Never use `CNTabBarNative` as a Flutter bottom nav.** Use `CNTabBar` for
   Flutter-screens-per-tab. The takeover variant creates two sources of truth → documented
   "tap twice" + screen rebuilds. — **[V]** §2.4, quoted verbatim from the vendored fork.

3. **Do not opacity-animate any subtree containing a platform view.** Prefer translation.
   Fade forces per-frame native layer mutations and leaves ghosting UIViews. — **[R]**
   `arxa_kit_tab_switch_transition.dart` and `arxa_kit_directional_tab_transition.dart`,
   verified on the iOS 26 simulator; **[S]** flutter#148639.

4. **Mount native chrome once at the root, above the per-tab `Navigator`.** Upstream itself
   places the bar as a sibling of page content ("overlay this at the bottom of your page"),
   not as a child of the routed subtree — **[V]** §2.2. The further claim that a platform
   view inside a route subtree is destroyed and rebuilt on every push/pop is **[I]**: it
   follows from the widget being disposed with its subtree, but neither the Flutter docs
   nor either package states it. Worth measuring before it's load-bearing. **[S]** for the
   go_router `StatefulShellRoute.indexedStack` idiom.

5. **`ShaderMask` and `ColorFiltered` will not work over native chrome; `BackdropFilter` is
   constrained.** Design around it — do not budget time to make a blur sample native pixels.
   — **[V]** §1.4.

6. **Register `CNTabBarRouteObserver` once on the root navigator, and hand-drive the modal
   hooks for non-route overlays.** Snackbars and `Scaffold.showBottomSheet` are invisible to
   the observer. — **[V]** §2.3; **[R]** already implemented in
   `kit/ui_library/lib/utils/arxa_kit_native_overlay.dart`.

7. **Treat "does this screen have any platform view at all" as the real budget question.**
   Mounting the first one migrates Flutter compositing to the platform thread; there is no
   published per-screen count, and inventing one would be fabrication. — **[V]** §1.2
   (stated generally for hybrid composition, but the surrounding engine doc is
   Android-authored — not iOS-verified), **[V]** §1.5 (negative finding).

8. **When a native view must disappear, destroy it behind a same-size placeholder** rather
   than leaving it mounted and hidden. Both the Flutter docs' placeholder-texture advice and
   the fork's v1.5.1 sheet handling land here independently. — **[V]** §1.3, **[V]** §2.3.

9. **Do not treat upstream `cupertino_native` as hardened.** It self-describes as a proof of
   concept bridging to a future all-Flutter Cupertino library. Pin, vendor, and expect to
   patch — which this repo already does. — **[V]** §2.1, **[R]** vendored fork.

10. **Never construct a `Future` inside `build()` when the builder's result contains a
    platform view.** A new-but-already-completed future still costs one `waiting` frame,
    which unmounts and recreates the `UiKitView`. Resolve in `initState` /
    `didUpdateWidget`, store in state, build the platform view synchronously. — **[V]** §4.1
    (FutureBuilder API docs), **[R]** §4.2.

11. **Port `tab_bar.dart`'s `_prepareCreationParams` pattern to `button.dart`, `icon.dart`,
    `popup_menu_button.dart`, and `glass_button_group.dart`.** The vendored package already
    solved this in one component and named the symptom ("duplicate platform-view creation
    attempts"); the other four still construct futures in `build()`. — **[R]** §4.3.

12. **Before acting on any [S]-tagged issue above, open it.** The version-regression list in
    flutter#163498 in particular is an unverified search summary and must not be quoted as
    fact. — methodological.

---

## Open questions worth a follow-up pass

- Does flutter#163498's Impeller regression list actually hold for the Flutter version this
  repo pins? Unverified, and it would change transition strategy if true.
- Upstream lists "combining scroll views with native components" as unsolved **[S]**. This
  repo has `arxa_kit_scroll_occlusion_gate_test.dart` **[R]**, suggesting it has already
  been confronted — worth reconciling the in-repo solution against upstream's open problem.
- The engine's Performance section is Android-authored. An iOS-specific measurement of the
  platform-thread contention cost on this app's actual screens would beat inference.
