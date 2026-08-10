# Native iOS bottom sheet vs. Flutter-drawn imitation — research

Compiled 2026-08-11. Confidence key: 🔥 official docs/source confirm · 🌡️ strong community consensus · ❄️ speculation / unverified.

---

## 1. What IS the native iOS bottom sheet?

**UIKit — `UISheetPresentationController` (iOS 15+)**
Accessed via `viewController.sheetPresentationController` on any modally-presented `UIViewController`. 🔥 (Apple docs: https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller — page confirmed reachable but rendered client-side so exact wording pulled from corroborating technical write-ups below)

- `detents: [UISheetPresentationController.Detent]` — `.medium()`, `.large()`, and since **iOS 16** `.custom(identifier:resolver:)` for an arbitrary fixed height. 🔥 https://www.avanderlee.com/swift/presenting-sheets-uikit-uisheetpresentationcontroller/ , https://nemecek.be/blog/159/how-to-configure-uikit-bottom-sheet-with-custom-size
- `prefersGrabberVisible: Bool` (default `false`) — shows the drag-grabber pill. 🔥
- `preferredCornerRadius: CGFloat?` — corner radius the sheet attempts to present with. 🔥 https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller/3801904-preferredcornerradius
- `largestUndimmedDetentIdentifier` — the largest detent at which the system's automatic dimming view is suppressed, enabling interaction with the view underneath (Maps-style non-modal sheet). 🔥
- `prefersScrollingExpandsWhenScrolledToEdge: Bool` (default `true`) — governs whether scrolling up on an at-top scroll view expands the sheet to the next detent vs. just scrolling content. 🔥 https://sarunw.com/posts/bottom-sheet-in-ios-15-with-uisheetpresentationcontroller/
- `prefersEdgeAttachedInCompactHeight: Bool` — in landscape/compact-height, attaches the sheet to the bottom edge with insets instead of going full-screen; paired with `widthFollowsPreferredContentSizeWhenEdgeAttached`. 🔥 https://medium.com/@batrakov.vitaly/how-to-create-bottom-sheet-with-uikit-b1d7e979b70c

**SwiftUI equivalents (layered on the same UIKit machinery)**

- `.presentationDetents([.medium, .large])` — iOS 16+. 🔥 https://sarunw.com/posts/swiftui-bottom-sheet/
- `.presentationDragIndicator(.visible)` — iOS 16+. 🔥
- `.presentationBackground(_:)` / `.presentationCornerRadius(_:)` — iOS **16.4+** (later than the base detents API). 🔥 https://www.appcoda.com/swiftui-bottom-sheet-background/
- `.presentationBackgroundInteraction(.enabled(upThrough:))` — iOS 16.4+, lets the user interact with content behind the sheet at a given detent (the Maps pattern). 🔥

Known SwiftUI bugs worth noting for anyone diagnosing weird behavior: `.presentationBackground` + a detent-selection binding can cause a visible "square in the middle of the screen" glitch on detent change, and `.presentationBackground` doesn't render correctly combined with the new zoom-transition API. 🌡️ https://developer.apple.com/forums/thread/742830 , https://developer.apple.com/forums/thread/762825

---

## 2. What did iOS 26 / Liquid Glass change about sheets?

Per WWDC25 session **"Build a SwiftUI app with the new design"** (https://developer.apple.com/videos/play/wwdc2025/323/) and community write-ups of it: 🔥 (primary source is the official WWDC video; the summaries below are 🌡️ secondary paraphrase since the video wasn't transcribed directly)

- Partial-height sheets are now **inset from the screen edges by default** and get a **Liquid Glass background**. At smaller detents the sheet's bottom corners pull inward, nesting into the display's curved edges (rounded-corner awareness of the actual device geometry).
- Transitioning toward the full-height detent, the glass background **gradually becomes opaque** and anchors flush to the screen edge — the glass effect is detent-dependent, not static.
- Apple explicitly recommends **removing custom `.presentationBackground(...)` modifiers** so the system's Liquid Glass material shows through — the old "translucent material" pattern from iOS 16.4 is now discouraged. Same guidance applies in UIKit per "Build a UIKit app with the new design" (custom background content should be removed).
- To get the effect at all, the sheet must declare **detents including at least one partial-height option** (`.medium` or a custom height) — a `.large()`-only sheet doesn't get the inset/glass treatment.
- **Gotcha:** `Form`/`List` content inside a sheet paints its own opaque background, hiding the glass — needs `.scrollContentBackground(.hidden)` in addition to the partial detent.
- Sheets can also morph directly out of the presenting button via the navigation-zoom-transition API.

Sources: https://nilcoalescing.com/blog/PresentingLiquidGlassSheetsInSwiftUI/ , https://nilcoalescing.com/blog/LiquidGlassSheetsWithNavigationStackAndForm/ (🌡️, both consistent with and citing the WWDC session)

**Practical implication for diagnosis:** on iOS 26, a real native sheet at a partial detent should show a frosted/glassy, edge-inset panel with rounded corners that don't reach the screen edges — a Flutter-drawn sheet reproducing the *pre-26* flat/opaque full-width look would now look conspicuously dated next to a real one, which is an additional discriminator specific to iOS 26 devices.

---

## 3. THE DISCRIMINATOR — observable tells

These are things a Flutter-drawn widget (running entirely inside the single `FlutterView`/Metal surface) structurally cannot produce, because they require system compositor / window-server level control Flutter doesn't have:

1. **Presenting screen scales down and grows rounded corners while the sheet is up** (the "stacked card" look). This is driven by a private UIKit class, `UITransitionView`, which applies a transform to the view *behind* the sheet at the window level — outside any single view controller's drawable surface. 🌡️ https://dilloncodes.hashnode.dev/native-ios-half-sheets , https://mackuba.eu/notes/wwdc21/customize-and-resize-sheets-uikit/
   - Note: this only reliably triggers at the `.large()` detent and only affects the *immediately* preceding view controller — `preferredCornerRadius` propagation to the parent is inconsistent. 🌡️
2. **System dimming view** — a real, non-interactive scrim inserted by UIKit between the presenter and the sheet, tap-to-dismiss by default, controllable only via `largestUndimmedDetentIdentifier`. A Flutter-drawn overlay can fake a scrim color but can't replicate the exact system compositing (it's drawn inside Flutter's own layer, so it always sits *inside* the app's render tree, never as a true separate system layer). 🔥 (documented API — https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller)
3. **Continuous spring physics across gesture + rubber-band + detent-settle.** Real iOS sheets use one interruptible spring simulation: drag velocity carries through into the settle animation and into overscroll rubber-banding at the sheet's own edges. Flutter's `DraggableScrollableSheet` is fraction-based (`initialChildSize`/`minChildSize`/`maxChildSize`) and driven by a curve/tween `AnimationController`; its `snap`/`snapSizes` **interpolate** rather than preserve velocity, so fling-to-dismiss and fling-between-detents feel discontinuous by comparison. This is one of the most reliable tells in a screen recording: watch what happens when you flick and immediately lift your finger mid-gesture — native settles with visible momentum overshoot-and-settle, Flutter tween-based sheets snap on a fixed curve. 🌡️ https://github.com/flutter/flutter/issues/138690 , https://occasionalflutter.substack.com/p/cool-flutter-packages-flutter_physics
4. **Scroll-to-expand handoff is automatic and edge-aware.** `prefersScrollingExpandsWhenScrolledToEdge` (default `true`) means: swipe up on a scrollable list at rest (`contentOffset.y == 0`) and the *sheet* expands; once expanded/not at top, the same gesture scrolls the *list*. This handoff is native and precise. Flutter has no built-in equivalent primitive that ships in the framework — `DraggableScrollableSheet`'s handoff between drag-resize and inner scroll is a known rough edge (community bug reports of the scroll view "always behaving as if expanded," jumping, or fighting the sheet drag). 🌡️ https://developer.apple.com/forums/thread/744162 , https://github.com/flutter/flutter/issues/116427
5. **Home indicator / status bar style responds to the transition.** The home indicator's appearance is sampled from the window/transition hierarchy (including the private transition views), not purely from the visible view controller — e.g., a light indicator can get "stuck" dark after a system view briefly passes underneath. `prefersHomeIndicatorAutoHidden` on the *child* view controller controls hide/show. This is genuine system-chrome interaction; Flutter cannot touch the home indicator or status bar style from inside its own render surface without a platform channel round-trip, and even then it's coarse (whole-app override, not per-transition). 🌡️ https://medium.com/@nathangitter/reverse-engineering-the-iphone-x-home-indicator-color-a4c112f84d34
6. **iOS 26 Liquid Glass edge-inset behavior at partial detents** (see §2) — glass material, edge nesting into the device's actual corner curvature, opacity ramp tied to detent position. Reproducing this in Flutter would require re-implementing Apple's glass material (index of refraction / blur / specular highlight response to content behind it) purely in Skia/Impeller — not currently done by any Dart-only package found in this research. ❄️→🌡️ (glass material generally is very hard to fake pixel-for-pixel; no direct comparison test was run)
7. **Rotation / compact-height behavior.** `prefersEdgeAttachedInCompactHeight` — real sheets in landscape automatically re-flow to an edge-attached, inset presentation. A Flutter-drawn sheet needs bespoke `MediaQuery`/orientation logic to replicate this and is very unlikely to match Apple's exact insets. 🔥 (documented API, behavior widely reproduced in tutorials)
8. **Dynamic Island / notch clipping** — no direct source found confirming special-case sheet behavior around the Dynamic Island beyond the general iOS 26 edge-curvature nesting in §2/#6 above. Not separately verified. ❄️

**Quick screen-recording checklist** (ordered by how hard each is to fake):
- [ ] Does the *presenting screen* itself visibly shrink/round its corners behind the sheet at full height? (native only, #1)
- [ ] Does flinging the sheet mid-drag show momentum/overshoot-then-settle rather than a fixed-duration ease curve? (native only, #3)
- [ ] Does scrolling a list inside the sheet at rest expand the sheet, then scroll normally once expanded, without any visible "fight" or jump? (native only, #4)
- [ ] On iOS 26 hardware, does a partial-height sheet show a frosted glass panel inset from the screen edges rather than a flat, edge-to-edge card? (native + iOS26, #2/#6)
- [ ] Does the dimmed background actually block taps (unless `largestUndimmedDetentIdentifier` is set) with a true system scrim, not an app-drawn `Container` color? (native only, #2)

---

## 4. Flutter APIs — native vs. drawn

| API / package | Native or drawn? | Notes |
|---|---|---|
| `showCupertinoModalPopup` + `CupertinoActionSheet` | **Drawn** 🔥 | Pure `StatefulWidget`, part of the normal widget tree (inheritance: `Object → DiagnosticableTree → Widget → StatefulWidget → CupertinoActionSheet`). No platform channel involved. Also note: `showCupertinoModalPopup` is a generic popup route, not the iOS page-sheet presentation style at all. https://api.flutter.dev/flutter/cupertino/CupertinoActionSheet-class.html |
| `showModalBottomSheet` (Material) | **Drawn** 🔥 | Well-established; Material widget, not iOS-styled by default. |
| `CupertinoSheetRoute` / `showCupertinoSheet` | **Drawn (Dart re-implementation)** 🔥 | Added in **Flutter 3.29** (PR landed ~Feb 2025) to visually mimic the iOS page-sheet look (drag-to-dismiss, rounded top corners). Enhanced in **Flutter 3.44** with scrolling+dragging coordination (`scrollableBuilder`, `CupertinoSheetDragArea`, PR #177337) and a March-2025 fix (PR #163700) that pulls the device corner radius from `MediaQuery` instead of hardcoding it — i.e. it *mimics* device geometry but still never calls into `UISheetPresentationController`. There is **no** system dimming view, no `UITransitionView`-driven parent scaling, and (per this research) no Liquid Glass treatment — it's Flutter drawing an iOS-styled card. Sources: https://medium.com/flutter/whats-new-in-flutter-3-29-f90c380c2317 , https://github.com/flutter/flutter/pull/177337 , https://github.com/flutter/flutter/pull/163700 , https://api.flutter.dev/flutter/cupertino/CupertinoSheetRoute-class.html |
| `modal_bottom_sheet` (pub.dev) | **Drawn** 🌡️ | `CupertinoModalBottomSheetRoute` imitates iOS 13-style modal navigation (bounce, blur, dark mode) entirely in Dart. |
| `sheet` (pub.dev) | **Drawn** 🌡️ | Fully Dart-side draggable sheet widget/route. |
| `family_bottom_sheet` (pub.dev) | **Drawn** 🌡️ | Dart-side, `showModalBottomSheet`-like API with internal navigation support. |
| `cupertino_native` (serverpod.dev, pub.dev) | **Real platform-view bridge** 🌡️ | Hosts actual UIKit/AppKit controls inside Flutter via Platform Views + method channels. Author explicitly describes it as **"more of a proof of concept than a full package"** — included components work but coverage/polish is limited. ~316 likes, 150 pub points at time of research. https://pub.dev/packages/cupertino_native |
| `cupertino_native_better` (fork) | **Real platform-view bridge** 🌡️ | MIT-licensed fork targeting iOS 26+ Liquid Glass widgets via hybrid composition; ships a `NavigatorObserver` (`CNTabBarRouteObserver`) to work around native-UIView compositing bugs (drop-shadow bleed through sheets/popups, tab bar rendering above modals) — itself evidence that mixing native platform views with Flutter's own sheet/modal system is fragile. ~75 likes, 6.6k downloads. https://pub.dev/packages/cupertino_native_better |
| `cupertino_native_plus` (fork) | **Real platform-view bridge** 🌡️ | Another continuation fork; adds icon system, claims performance improvements. |
| `base_plus` (pub.dev) | **Claims native bridge, not independently verified** ❄️ | Advertises a `BaseNativeSheet.show()` API wrapping `UISheetPresentationController` with resizable detents, depending on `cupertino_native_extra`. Found only via search summary, not read directly — treat as a lead to verify, not a confirmed fact. |

**Bottom line on §4:** if the app in question is using `CupertinoSheetRoute`, `showCupertinoModalPopup`, `showModalBottomSheet`, or any of `modal_bottom_sheet`/`sheet`/`family_bottom_sheet`, it is **Flutter-drawn**, full stop — none of these touch `UISheetPresentationController`. Only `cupertino_native` and its forks (and possibly `base_plus`, unverified) are genuine platform bridges, and even those are young/experimental packages with known compositing rough edges.

---

## 5. Correct architecture for a genuinely native sheet from Flutter

**No official first-party Flutter widget wraps `UISheetPresentationController`.** The only Apple/Flutter-sanctioned path to real native presentation is the general **add-to-app** pattern, repurposed for "native chrome wrapping a Flutter view":

1. A `MethodChannel` call from Dart triggers native Swift/ObjC code (typically registered in `AppDelegate` or a plugin). 🔥 https://docs.flutter.dev/add-to-app/ios/add-flutter-screen
2. The native side grabs the existing `FlutterViewController` (commonly `window?.rootViewController as? FlutterViewController`) or — for content that must render *Flutter widgets inside the sheet* — constructs a **second** `FlutterViewController` attached to a shared, pre-warmed `FlutterEngine`: `FlutterViewController(engine: sharedEngine, nibName: nil, bundle: nil)`.
3. That view controller (native-only chrome, or a Flutter-backed one) is configured via `.sheetPresentationController` (detents, grabber, corner radius, etc.) and presented with `present(vc, animated: true)` from the true root/presenting view controller. 🔥
4. Dismissal and data flow back to Dart go through the same `MethodChannel`, or a `NotificationCenter` post that the presenting side observes to call `dismiss(animated:)`. 🔥

**Why pre-warm/share the `FlutterEngine`:** faster first frame, Dart state persists across multiple presentations, and plugins/Dart logic can run before the view even appears. Creating a fresh engine per-presentation is possible but adds visible latency and is only recommended for very infrequent, stateless sheets. 🔥 https://docs.flutter.dev/add-to-app

**Known problems, confirmed via a real Flutter issue:**
- **Cold-engine race:** the very first `MethodChannel` call made right before/around the first `FlutterViewController` presentation can fail because the engine isn't warm yet (flutter/flutter#34826). Workaround is to move the channel call into the `present(...)` completion handler, which introduces a visible flicker (data arrives after `viewDidAppear`). 🔥 https://github.com/flutter/flutter/issues/34826
- **No full engine teardown:** you can release `FlutterViewController` instances, but the `FlutterEngine` itself has no full shutdown path — it stays warmed up in memory even when nothing is rendering. Relevant if a native sheet is presented/dismissed repeatedly. 🔥 (Flutter docs)
- **SwiftUI hosting needs an extra wrapper:** a `UIViewControllerRepresentable`/`FlutterViewControllerRepresentable` bridge is required to host a pre-warmed engine's view controller inside a SwiftUI-first app. 🌡️
- **Touch/gesture routing:** not flagged as broken in current docs, but is the classic risk area whenever a `UIViewController` boundary sits between the presenting chrome and Flutter's own gesture arena — no specific bug found in this research, flagged as a thing to verify empirically rather than assumed safe. ❄️

**Practical verdict:** yes, it's achievable — present a real `UIViewController` (configured via `UISheetPresentationController`) that hosts a `FlutterViewController` for its content — but it is bespoke native (Swift) engineering via a plugin/method channel, not something available off the shelf from a single pub.dev package with full confidence, except possibly `cupertino_native`/forks for sheet-only cases (unverified for the "Flutter content inside the native sheet" case specifically — those packages focus on native *controls* like buttons/switches/tab bars, not on hosting arbitrary Flutter subtrees inside a `UISheetPresentationController`).

---

## Sources index

- Apple: https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller (official; page confirmed live, content corroborated via secondary sources since it renders client-side)
- Apple: https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller/3801904-preferredcornerradius (official)
- Apple WWDC25: https://developer.apple.com/videos/play/wwdc2025/323/ ("Build a SwiftUI app with the new design")
- Apple Forums: https://developer.apple.com/forums/thread/742830 , https://developer.apple.com/forums/thread/762825 , https://developer.apple.com/forums/thread/744162
- Flutter official: https://docs.flutter.dev/add-to-app , https://docs.flutter.dev/add-to-app/ios/add-flutter-screen
- Flutter repo: https://github.com/flutter/flutter/issues/34826 , https://github.com/flutter/flutter/pull/177337 , https://github.com/flutter/flutter/pull/163700 , https://github.com/flutter/flutter/issues/116427 , https://github.com/flutter/flutter/issues/138690
- Flutter API docs: https://api.flutter.dev/flutter/cupertino/CupertinoActionSheet-class.html , https://api.flutter.dev/flutter/cupertino/CupertinoSheetRoute-class.html
- pub.dev: https://pub.dev/packages/cupertino_native , https://pub.dev/packages/cupertino_native_better
- Community technical write-ups: nilcoalescing.com (Liquid Glass sheets), sarunw.com, avanderlee.com, mackuba.eu, dilloncodes.hashnode.dev, nathangitter (home indicator reverse-engineering)

---

## Correction (2026-08-11) — §3 tell #1 is wrong about Flutter's limits

This doc states that the presenting-screen scale-down-and-round is "native only"
because it is driven by a private `UITransitionView` "outside any single app's
render surface", and that "Flutter can't touch the presenting screen from inside
its own render surface".

**The mechanism claim is right; the capability conclusion is wrong.** Verified
against the Flutter SDK on disk (`packages/flutter/lib/src/cupertino/sheet.dart`,
3.44.9):

- `:84` — "Amount the sheet in the background scales down. Found by measuring
  the width ... iPhone 16 pro running iOS 18.0"
- `:260` — "it will slide slightly up and scale down to appear"
- `:341`, `:373` — a `scaleAnimation` applied through `Transform.scale`
- `:331-338` — border radius tweened from the device corner radius to 12
- `:819-823` — `delegatedTransition => CupertinoSheetTransition.delegateTransition`

`CupertinoSheetRoute` **does** scale and round the route behind it. The error is
a conflation: Flutter cannot transform a *native `UIViewController`* presenting
it, but the "presenting screen" under a Cupertino sheet is another **Flutter
route inside Flutter's own tree**, which it transforms freely via
`delegatedTransition`.

This matters because the tell is listed first and "hardest to fake" — it would
lead a reader to conclude a stacked-card presentation proves a native sheet. It
does not.

The doc's headline conclusion stands and was acted on: `showCupertinoSheet` is
Dart-drawn and never calls `UISheetPresentationController`. The remaining tells
(system dimming view, continuous spring physics, `prefersScrollingExpands…`,
real detents) are unchallenged. The kit routes iOS here **knowingly** — see
`docs/plans/sheet-and-theme-propagation-fixes.md`; the user chose it over a
bespoke bridge with the Dart-drawn caveat stated explicitly.
