# Liquid Glass Theme Propagation: Flutter → iOS 26 Platform Views

Research summary for the symptom: after flipping Flutter's `MaterialApp.themeMode`, embedded native "Liquid Glass" platform views (each setting `container.overrideUserInterfaceStyle` from a Dart creation parameter) keep the OLD appearance for seconds, converging one-by-one.

---

## 1. Correct way to react to an appearance change on iOS 17+/26

`traitCollectionDidChange(_:)` was deprecated in iOS 17.0. Xcode 15 emits: *"'traitCollectionDidChange:' is deprecated: first deprecated in iOS 17.0 - Use the trait change registration APIs declared in the UITraitChangeObservable protocol."* The rationale (from an Apple engineer on the developer forums and WWDC23 session 10057, "Unleash the UIKit trait system"): the old method fires for **every** trait change, forcing you to filter manually, and doesn't scale as custom traits are added. The registration APIs let the system call you back only for the specific traits you declare.

### Replacement: `UITraitChangeObservable` / `registerForTraitChanges`

Three overloads, all callable on `UIView`, `UIViewController`, `UIWindowScene`, `UIPresentationController`, `UIScreen`:

- `registerForTraitChanges(_:handler:)` — closure-based
- `registerForTraitChanges(_:target:action:)` — target-action
- `registerForTraitChanges(_:action:)` — self target-action

**Closure form (minimal sample):**

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    registerForTraitChanges(
        [UITraitUserInterfaceStyle.self]
    ) { (self: Self, previousTraitCollection: UITraitCollection) in
        self.configureGlassAppearance()
    }
}
```

**Target-action form:**

```swift
registerForTraitChanges(
    [UITraitUserInterfaceStyle.self],
    action: #selector(configureGlassAppearance)
)
```

**Common compile-time gotcha:** the parameter is `[UITrait]` — an array of trait *types* (`Class<UITraitDefinition>` in Objective-C), not trait *values*. `[UIUserInterfaceStyle.light, .dark]` will not compile; use `[UITraitUserInterfaceStyle.self]`.

**Overrides moved too:** since `traitCollection` is read-only, setting an override now goes through the `traitOverrides` property on `UIWindowScene`/`UIWindow`/`UIViewController`/`UIPresentationController`/`UIView` rather than direct trait mutation (this is a separate mechanism from `overrideUserInterfaceStyle`, which still exists and still works on iOS 26).

**Caveats found in the wild:**
- Prior to iOS 13 and still relevant conceptually: there's no guarantee the system calls the change handler when a view is first added to the hierarchy — set the initial appearance explicitly in `viewDidLoad`/at construction, don't rely on the callback firing once for free.
- One forum report: setting `overrideUserInterfaceStyle` back to `.unspecified` does not reliably trigger the change callback — don't depend on it firing for every possible transition.
- Flutter itself has an open, low-priority tech-debt issue for this exact deprecation warning in `FlutterViewController` (flutter/flutter#128735, filed June 2023, labeled P3/tech-debt, still open/unresolved) — meaning the *Flutter engine's own* base view controller has not migrated off the deprecated API. This doesn't block a custom `PlatformView`'s native class from adopting `registerForTraitChanges` itself, but it means you can't assume the Flutter engine is setting a good example here.

---

## 2. Does a `UIVisualEffectView` / `UIGlassEffect` auto re-resolve when `overrideUserInterfaceStyle` changes?

**No — this is very likely the direct cause of your bug.** Changing `overrideUserInterfaceStyle` updates the trait collection, but the *already-assigned* `effect` object on a `UIVisualEffectView` does not automatically re-render. The effect is resolved once at assignment time; you must reassign it (or otherwise force invalidation) after the trait change.

**Directly on-point evidence — `expo-glass-effect` issue #43743** (opened Mar 2026, accepted by the Expo team): `GlassView`'s `colorScheme` prop correctly sets `overrideUserInterfaceStyle` on the native view, but the `UIGlassEffect` visual doesn't update, because `setColorScheme()` doesn't call `updateEffect()`. Meanwhile `setTintColor`/`setInteractive` *do* call `updateEffect()` and update immediately. The fix pattern:

```swift
func setColorScheme(_ scheme: String) {
    overrideUserInterfaceStyle = scheme == "dark" ? .dark : .light
    updateEffect()          // <-- the missing call; without it the glass stays stale
}

private func updateEffect() {
    let effect = UIGlassEffect(style: glassStyle)
    effect.isInteractive = glassIsInteractive
    effect.tintColor = glassTintColor
    glassEffectView.effect = effect   // re-assignment forces UIVisualEffectView to re-render
}
```

This is the same pattern that already applies to plain `UIBlurEffect`/`UIVibrancyEffect`: adaptive blur *styles* (`.systemMaterial`, `.systemThinMaterial`, etc.) do repaint automatically on a genuine system appearance change (the OS re-renders its own compositor layer), but an `overrideUserInterfaceStyle` set programmatically on a subtree is a narrower signal that doesn't always propagate through already-materialized effect objects — reassigning `effect` is the documented workaround across every report found (Expo, and general `UIVisualEffectView` blur/vibrancy discussions). If you nest a `UIVibrancyEffect` inside the blur/glass content view, that inner effect must be rebuilt and reassigned too — it's derived from the outer effect at construction time, not live-linked to it.

**iOS 26-specific regressions worth knowing about (not just your bug, corroborating the pattern):**
- Apple Developer Forums / FB19023069: since iOS 26 beta 3, dynamic colors (`UIColor.label`, etc.) inside a glass `UIVisualEffectView`'s content view stop updating on light/dark switches in some configurations.
- `react-native-screens` issue #4081 (`[iOS 26] Stack header Liquid Glass blur lost in inactive tabs after Appearance.setColorScheme`): calling a scheme-change API while a tab is *inactive* leaves that tab's nav-bar glass broken until the user manually revisits the tab — i.e., the glass effect needs the view to actually go through a layout/appear cycle to pick up the change, not just receive the trait mutation. This matches your "converging one by one" symptom: each native view only re-resolves once it next becomes active/laid-out, not synchronously when the Dart-side flag flips.
- Known opacity 0→1 regression on iOS 26.1/26.2 (not 26.0) where a glass `UIVisualEffectView` added at opacity 0 never reappears when opacity returns to 1, reproducible with `UIGlassEffect` but not `UIBlurEffect` — a further data point that iOS 26 glass invalidation is less reliable than ordinary blur.

**Recommendation:** on every native creation-param/theme update, explicitly reassign `.effect` (rebuild the `UIGlassEffect`/`UIBlurEffect` object) rather than relying on `overrideUserInterfaceStyle` alone, and additionally call `setNeedsLayout()`/`setNeedsDisplay()` so a genuinely inactive/off-screen view still repaints promptly when it becomes active.

---

## 3. `UIHostingController` — correct way to push a light/dark override down

Three distinct mechanisms exist and they are **not interchangeable**:

| Mechanism | Scope | Notes |
|---|---|---|
| `.environment(\.colorScheme, .dark)` | Applies to the view and descendants only (environment value) | Only accepts `.light`/`.dark` — no "auto"/system option. Deprecated `.colorScheme(_:)` modifier behaves the same way, locally. |
| `.preferredColorScheme(_:)` | Propagates *upward* to the nearest enclosing presentation (a "preference", not environment) | Accepts optional `ColorScheme?`; conflicting non-nil preferences from parallel view-hierarchy branches are resolved by view order (first non-nil wins), per Apple DTS. Historically buggy: on iOS 18, setting `.dark` then back to `nil` while the device is in light mode can leave the UI stuck dark until app relaunch. |
| `overrideUserInterfaceStyle` on the `UIHostingController` (or its `view`) | UIKit trait-level override, affects all UIKit-backed chrome the hosting controller owns | Three-state (`.unspecified`/`.light`/`.dark`) unlike `.preferredColorScheme`'s awkward nil handling. Reaches UIKit materials (nav bars, glass) that pure SwiftUI preferences may not touch. |

**Known ordering bug:** setting `.preferredColorScheme` *and* `overrideUserInterfaceStyle` at the same time causes the SwiftUI preference to win, silently breaking toggle behavior inside `.sheet`/`.fullScreenCover` presentations. **Do not set both** — pick `overrideUserInterfaceStyle` on the hosting controller when embedding in Flutter/UIKit (since it's the one that reliably reaches native glass materials), and avoid layering `.preferredColorScheme` on top of it in the hosted SwiftUI tree.

None of these three, by themselves, are documented to force a `UIGlassEffect`/`UIVisualEffectView` re-render — the re-render still depends on the trait/effect-reassignment mechanics from section 2. `overrideUserInterfaceStyle` on the hosting controller is necessary but likely not sufficient on its own for glass materials specifically.

---

## 4. Official/idiomatic pattern for propagating Flutter-side theme into platform views

**There is no first-party, app-wide broadcast mechanism in Flutter for this.** The official iOS platform-views doc (docs.flutter.dev/platform-integration/ios/platform-views) only demonstrates one-shot `creationParams` passed at `UiKitView` construction time (`StandardMessageCodec`) — it does not cover post-creation updates at all. The idiomatic *post-creation* update pattern (seen consistently across Flutter's own Android platform-views docs and community examples, and applicable identically on iOS) is:

- **Per-view `MethodChannel` keyed by the platform view's id.** The native `PlatformView` implementation also conforms to `FlutterPlugin`/`MethodCallHandler` and owns a `MethodChannel(messenger, "my_view/\(viewId)")`. Dart holds a matching `MethodChannel` created in `onPlatformViewCreated` and calls `invokeMethod('setColorScheme', ...)` on it whenever the app theme changes.
- This is **per-view, not app-wide** — every embedded platform view needs its own channel call. If you have N glass views on screen, a theme flip requires N separate `invokeMethod` round-trips (each async, each independently scheduled), which is the most likely mechanical explanation for "converging one by one" rather than updating atomically in a single frame.
- `cupertino_native` (pub.dev, by Serverpod, MIT/BSD — explicitly described by its own maintainers as *"a vibe-coded Frankenstein's monster patched together with duct tape"* and *"a proof of concept for bringing Liquid Glass to Flutter"*) follows the ambient-`CupertinoTheme`-down-to-each-widget pattern: the Flutter `CupertinoApp`'s `theme: CupertinoThemeData(brightness: ...)` is read by each individual native-backed widget, which forwards it to its own platform view instance over its own channel — i.e., still per-widget propagation, not a single broadcast. The maintainers' own roadmap lists theming as unfinished/rough. There's a fork, `cupertino_native_plus`, that advertises "automatic theme synchronization with system preferences" as an explicit improvement — implying the base package's per-widget approach was found lacking.
- No evidence was found of any mature package using a single app-wide `EventChannel` broadcast for theme; the one broadcast pattern found in the wider platform-views literature (KINTO Tech blog, Android-side) is for native→Dart event streams, not Dart→native theme fan-out.

**Practical implication for your bug:** if each glass view independently receives and applies its own `overrideUserInterfaceStyle` update via its own channel call, the "one-by-one convergence" you're seeing is architecturally expected — each channel call is scheduled and processed independently, and (per section 2) each view's glass effect still needs an explicit re-render on top of that. Fixing only the re-render bug (section 2) will make each view converge *faster*, but won't make them converge *simultaneously* unless you also batch/synchronize the channel calls (e.g., fire all `invokeMethod` calls within the same Dart microtask/frame, and have each native side apply+repaint synchronously rather than deferring to next layout).

---

## 5. Known Flutter platform-view issue: method-channel call applied but not visually reflected until next layout/frame

Several distinct, real mechanisms compound here — no single issue is a perfect match, but together they explain the delay:

- **flutter/flutter#150802** ("Add callback when a PlatformView is added to native view hierarchy," open, P2, team-ios/triaged-ios) — `UiKitView`'s `onPlatformViewCreated`/`PlatformViewCreatedCallback` fires when the native view is *created*, not when it's actually attached to the view hierarchy. Code that mutates appearance immediately in the creation callback can run before the view is laid out/visible, so the mutation has no visible effect until the next layout pass picks it up. Workarounds cited in the issue are just artificial delays — there is no official "view is now attached and laid out" callback.
- **flutter/flutter#67514 / #67393** — historical reports that the `frame` passed into the iOS factory's `create(withFrame:...)` can be `CGRect.zero` at creation time; any appearance/layout logic keyed off bounds at creation is unreliable until a real layout pass happens.
- **Async channel round-trip inherent delay** — `invokeMethod` is asynchronous; its result/any dependent `setState()` lands on the *next* frame/vsync, not the current one (this is normal Flutter scheduling, `PlatformDispatcher.scheduleFrame`/`handleBeginFrame`), so a single call is expected to take at least one extra frame even in the best case.
- **Native-side invalidation requirement** — general platform-views guidance (not iOS-specific to this bug, but applicable): after mutating a `PlatformView`'s native state from a method-channel handler, you must explicitly trigger a repaint (`setNeedsDisplay()`/`setNeedsLayout()` on iOS) — mutating a property alone does not guarantee an immediate redraw, especially for effect/material-backed views per section 2.
- **`react-native-screens` #4081** (cross-framework corroboration, not Flutter, but same OS-level mechanism): a scheme change applied while a native view is inactive/off-screen does not visually apply until that view is revisited/re-laid-out — supporting the "converges one by one, as each view is next touched by the layout system" symptom you're seeing, independent of which cross-platform framework is used.

No issue found states this exact "seconds-long staggered convergence across multiple simultaneous platform views" symptom verbatim — this report's synthesis (sections 2, 4, 5 combined: missing effect-reassignment + per-view independent channel calls + creation/layout-timing gaps) is the most defensible root-cause chain from available sources.

---

## Sources

1. [registerForTraitChanges(_:handler:) — Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uitraitchangeobservable-67e94/registerfortraitchanges(_:handler:))
2. [registerForTraitChanges(_:target:action:) — Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uitraitchangeobservable-67e94/registerfortraitchanges(_:target:action:))
3. [registerForTraitChanges(_:action:) — Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uitraitchangeobservable-67e94/registerfortraitchanges(_:action:))
4. [Registering For Trait Changes — Use Your Loaf](https://useyourloaf.com/blog/registering-for-trait-changes/)
5. [Unleash the UIKit trait system — WWDC23 session 10057](https://developer.apple.com/videos/play/wwdc2023/10057/)
6. [traitCollectionDidChange deprecated in Xcode 15 — Apple Developer Forums](https://developer.apple.com/forums/thread/738836)
7. [Handling trait changes (for dark mode) — Apple Developer Forums](https://developer.apple.com/forums/thread/734320)
8. [flutter/flutter#128735 — 'traitCollectionDidChange' is deprecated in iOS 17.0](https://github.com/flutter/flutter/issues/128735)
9. [expo/expo#43743 — expo-glass-effect: setColorScheme does not call updateEffect()](https://github.com/expo/expo/issues/43743)
10. [software-mansion/react-native-screens#4081 — Stack header Liquid Glass blur lost in inactive tabs after Appearance.setColorScheme](https://github.com/software-mansion/react-native-screens/issues/4081)
11. [Apple Developer Forums — dynamic colors not updating in dark mode since iOS 26 beta 3 (FB19023069 context)](https://developer.apple.com/forums/thread/794234)
12. [Apple Developer Forums — UIKit Glass Effect opacity 0→1 change does not work](https://developer.apple.com/forums/thread/808410)
13. [Apple Developer Forums — In iOS 26, the background glass effect of the navigation bar...](https://discussions.apple.com/thread/256175602)
14. [Liquid Glass — A Field Guide to UIKit Compatibility Pitfalls — fatbobman.com](https://fatbobman.com/en/posts/liquid-glass-a-field-guide-to-uikit-compatibility-pitfalls/)
15. [SwiftUI's colorScheme vs preferredColorScheme — Apple Developer Forums](https://developer.apple.com/forums/thread/810792)
16. [preferredColorScheme Broken in iOS 18 — Apple Developer Forums](https://developer.apple.com/forums/thread/763251)
17. [Host native iOS views in your Flutter app with platform views — docs.flutter.dev](https://docs.flutter.dev/platform-integration/ios/platform-views)
18. [Hosting native Android views in your Flutter app with Platform Views — docs.flutter.dev](https://docs.flutter.dev/platform-integration/android/platform-views)
19. [flutter/flutter#150802 — Add callback when a PlatformView is added to native view hierarchy](https://github.com/flutter/flutter/issues/150802)
20. [flutter/flutter#67514 — Parameter frame always ZERO when Using PlatformView on iOS with Swift](https://github.com/flutter/flutter/issues/67514)
21. [flutter/flutter#67393 — Platform Views UiKitView not rendering on iOS](https://github.com/flutter/flutter/issues/67393)
22. [cupertino_native — pub.dev](https://pub.dev/packages/cupertino_native)
23. [cupertino_native_plus — Dart API docs](https://pub.dev/documentation/cupertino_native_plus/latest/)
24. [Is it time for Flutter to leave the uncanny valley? — Serverpod blog](https://medium.com/serverpod/is-it-time-for-flutter-to-leave-the-uncanny-valley-b7f2cdb834ae)
