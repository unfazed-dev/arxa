# Research: native glass views stuck in dark mode after a Flutter-side theme switch

Scope: iOS 26 UIKit/SwiftUI glass (`UIVisualEffectView`, Liquid Glass) embedded in a Flutter
app via hybrid-composition platform views. Symptom: after switching the Flutter app theme
between light/dark, some native glass views update, some lag, some stay dark permanently
until an unrelated navigation event. Researched 2026-08-11 via web search + indexed fetches
(WebFetch/curl are blocked in this environment; `ctx_fetch_and_index`/`ctx_search` used
instead). Confidence grades: 🔥 official docs/source, 🌡️ strong community consensus, ❄️
speculation/single-report.

Related in-repo context found while researching (not this doc's scope, flagged for the
owning agents): the app's glass/blur views live in
`kit/ui_library/vendor/cupertino_native_better/ios/cupertino_native_better/Sources/cupertino_native_better/Views/`
(`LiquidGlassContainerView.swift`, `GlassButtonSwiftUI.swift`, `CNNativeTabBar.swift`, etc.),
and the task board already has task #9 "Bug B: theme change never reaches native glass
views" — this doc is the external-evidence input to that task, not its fix.

---

## 1. How does a UIKit view learn about a light/dark appearance change?

**🔥 `traitCollectionDidChange(_:)` is deprecated as of iOS 17.0** (`API_DEPRECATED(...,
ios(8.0, 17.0)...)` in `UITraitCollection.h`). Apple's deprecation message: "Use the trait
change registration APIs declared in the UITraitChangeObservable protocol." Confirmed both
in Apple's header comment and independently in Flutter's own engine issue tracker, where
`FlutterViewController`'s override of `traitCollectionDidChange:` triggers the exact same
`-Werror,-Wdeprecated-declarations` warning.
[flutter/flutter#128735](https://github.com/flutter/flutter/issues/128735)

**🔥 Current recommended API (iOS 17+): `UITraitChangeObservable` protocol.** Adopted by
`UIView`, `UIViewController`, `UIPresentationController`, `UIScreen`, `UIWindowScene` (i.e.
everything that used to adopt `UITraitEnvironment`). Three registration methods:
- `registerForTraitChanges(_:handler:)` — closure-based, receives `(observedObject,
  previousTraitCollection)`.
- `registerForTraitChanges(_:action:)` / `registerForTraitChanges(_:target:action:)` —
  selector-based.

Example (from Apple docs / Use Your Loaf, called once, typically in `viewDidLoad` /
`init`/`didMoveToWindow` — no per-callback re-registration needed):
```swift
registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previous: UITraitCollection) in
    self.configureView()
}
```
[Apple Developer Docs](https://developer.apple.com/documentation/uikit/uitraitchangeobservable-67e94/registerfortraitchanges(_:handler:))
· [Use Your Loaf](https://useyourloaf.com/blog/registering-for-trait-changes/)

**🔥 Gotcha confirmed by an Apple engineer on the dev forums:** you must pass the *trait
type*, not an enum value — `registerForTraitChanges([UITraitUserInterfaceStyle.self])`, not
`[UIUserInterfaceStyle.light, .dark]`. The latter fails to compile because `UITrait` is
`Class<UITraitDefinition>`. [Apple Forums #738836](https://developer.apple.com/forums/thread/738836)

**🌡️ Practical note:** the deprecated method still fires on iOS 18/26 in some scenarios
(e.g. background/foreground), so it isn't broken, only deprecated — a codebase can run both
paths during migration, but new code should use `registerForTraitChanges`.

**🔥 A raw `UIView` not owned by a `UIViewController` needs a layout pass to pick up a
trait change** — several sources independently describe a pattern where setting
`overrideUserInterfaceStyle` and adding a view to the hierarchy do not fire the callback
until `setNeedsLayout()`/`layoutIfNeeded()` is explicitly called. This is directly relevant
to platform views, which are typically bare `UIView`/`FlutterPlatformView`-wrapped views,
not view-controller-owned.

---

## 2. Does `overrideUserInterfaceStyle` on a child isolate it from the parent's appearance?

**🔥 Yes — and this is very likely the mechanism behind "some glass views stuck."**
`overrideUserInterfaceStyle` defaults to `.unspecified` on both `UIView` and
`UIViewController`, which means "inherit from parent." Once you assign any explicit value
(`.light`/`.dark`) to a view or VC, **that subtree stops inheriting** the window's/parent's
interface style and instead uses the fixed value you set — the whole point of the API is to
isolate a subtree. If the platform-view code (or a vendored wrapper like
`cupertino_native_better`) sets `overrideUserInterfaceStyle = .dark` once at construction
time to force a particular initial appearance, and nothing re-touches it later, the view
will *permanently* diverge from the app/window trait collection no matter how many times the
window's style changes — this matches "some views stay dark and don't react to navigation."
[Apple Docs](https://developer.apple.com/documentation/uikit/uiviewcontroller/overrideuserinterfacestyle) ·
[Sarunw – Adopting Dark Mode](https://sarunw.com/posts/adopting-ios-dark-mode/)

**🔥 iOS 17 changed the propagation rule.** Before iOS 17: child view controllers inherited
traits from the *parent view controller* only, ignoring the parent's *views*. From iOS 17
on: traits flow down through the view hierarchy *and* the view-controller hierarchy
together, so a child VC now inherits from its superview inside the parent VC too. This is a
behavior change worth checking against target iOS version — code written pre-iOS 17 that
relied on the old isolation semantics between a view's trait and its embedded child VC may
now behave differently (or vice versa, if the app still supports older OS versions and
branches on version).

**🌡️ Isolating a subtree deliberately:** `setOverrideTraitCollection(_:forChild:)` (VC-level)
and the iOS 17+ `traitOverrides` mutable container are the sanctioned ways to scope an
override to one branch of the hierarchy — as opposed to setting
`overrideUserInterfaceStyle` directly on a leaf view, which is easy to leave in place by
accident.

**🔥 Confirmed interaction with blur/glass:** if `overrideUserInterfaceStyle` is set anywhere
up the responder/view chain from a `UIVisualEffectView`, the blur honors that override, not
the system/window setting — i.e. this isn't just theoretical, it directly explains
per-view "stuck" appearance for glass specifically.

---

## 3. Do `UIVisualEffectView`/`UIBlurEffect` and iOS 26 Liquid Glass respond to appearance changes automatically?

**🔥 Depends entirely on which style constant was used — this is the single most likely
direct cause of "some glass views stuck."**
- **Adaptive/semantic styles** (`.systemThinMaterial`, `.systemMaterial`,
  `.systemThickMaterial`, `.systemUltraThinMaterial`, `.systemChromeMaterial`, and the
  unsuffixed forms generally) resolve from the current trait environment
  (`userInterfaceStyle`) and **do** flip automatically when the trait changes.
- **Fixed-appearance styles** (the explicit `...Light` / `...Dark` suffixed variants, e.g.
  `.systemThinMaterialDark`, `.systemUltraThinMaterialDark`, plus the legacy pre-iOS-13
  `.light`/`.dark`/`.extraLight`) are, per Apple's own doc wording, "always dark" (or
  always light) — **they never adapt**, by design, regardless of trait changes. If any glass
  view in this codebase was built with a `...Dark` constant (common when someone wanted "the
  dark glass look" and picked the fixed constant instead of overriding
  `overrideUserInterfaceStyle` + using the adaptive constant), it will *always* render dark,
  which matches "remained in the DARK appearance even though the app theme is now LIGHT."
  [Apple Docs – systemUltraThinMaterialDark](https://developer.apple.com/documentation/uikit/uiblureffect/style/systemultrathinmaterialdark) ·
  [Apple Docs – systemThinMaterial](https://developer.apple.com/documentation/uikit/uiblureffect/style/systemthinmaterial)

**🔥 Known reassignment bug even for adaptive styles:** UIKit compares effect objects and
can no-op an assignment that "looks the same," so the safe, widely-repeated pattern when you
must manually force a re-resolve is to null it first:
```swift
blurView.effect = nil
blurView.effect = UIBlurEffect(style: .systemMaterial)
```
This pattern shows up independently across several sources as the fix for visual-effect
views that don't visually refresh even though the trait technically changed underneath them.

**❄️/🌡️ iOS 26 Liquid Glass (`UIGlassEffect`, `.glassEffect()`, `GlassEffectContainer`):**
Apple's marketing/reference material describes glass as adapting automatically to the
*luminance of content behind it* (turns light over dark content, dark over light content) —
this is a *content-based* adaptation, separate from and in addition to system
light/dark-mode trait adaptation. I could **not find an official Apple document that
explicitly states whether `UIGlassEffect`/`.glassEffect()` re-resolves on a
`userInterfaceStyle` trait change the same way `.systemThinMaterial` does** — this is
inferred from it being built on the same trait-resolution system, not confirmed by a
direct source. Treat as ❄️ until confirmed against WWDC26 session material or the
`UIGlassEffect` reference page directly.

**🔥 UIKit vs. SwiftUI-only API surface:** `GlassEffectContainer` and `.glassEffect()` are
SwiftUI-only APis (iOS/iPadOS/macOS/watchOS/tvOS 26+, Xcode 26+). The UIKit-side equivalent
is `UIVisualEffectView` configured with `UIGlassEffect`, which does **not** provide the
SwiftUI container's morphing/blending behavior between multiple glass shapes — a developer
forum thread flags this gap explicitly and raises embedding SwiftUI via
`UIHostingController` as the workaround if morphing is required.
[Apple Forums #791540](https://developer.apple.com/forums/thread/791540)

---

## 4. Do cached/resolved `UIColor`s and `CGColor` fail to update on appearance change?

**🔥 Yes, confirmed as a fundamental, expected limitation — not a bug, a documented
constraint of Core Graphics.** `CGColor` (and `CALayer` properties that take a `CGColor`,
e.g. `layer.borderColor`, `layer.backgroundColor` when set via `.cgColor`) has no concept of
dynamic/semantic color — that's a UIKit-level abstraction. When `.cgColor` is read off a
dynamic `UIColor`, it is resolved *once*, against whatever `UITraitCollection.current` is at
that call site, and baked into a static value. It will not re-resolve on its own when the
trait collection later changes.

**🔥 `UITraitCollection.current` is only guaranteed correct inside certain UIKit-managed
callbacks** (layout, drawing, trait-change callbacks). Reading/resolving colors in `init`,
lazy-var initializers, or arbitrary async contexts is exactly where this bug tends to get
introduced, because `UITraitCollection.current` may not reflect the eventual host
environment at that point.

**🔥 Three documented resolution approaches**, all from Apple's own guidance:
1. `UIColor.label.resolvedColor(with: traitCollection).cgColor` — explicit, one color at a
   time.
2. `traitCollection.performAsCurrent { layer.borderColor = UIColor.label.cgColor }` —
   temporarily swaps `UITraitCollection.current`, safe from any thread, auto-restores after.
3. Manual save/restore of `UITraitCollection.current` (what `performAsCurrent` does for you).

**🔥 The fix requires action on every trait change, not once:** you must re-run one of the
above **inside** a `registerForTraitChanges`/`traitCollectionDidChange` handler each time the
trait changes — resolving once at creation is the root bug pattern.

**🌡️ Modern caveat (community-reported, unconfirmed by Apple):** at least one developer
reports `UITraitCollection.current` intermittently reporting `.unspecified` instead of the
expected style since the iOS 17 `traitCollectionDidChange` deprecation, and a related, more
concrete Apple Forums report describes a **regression since iPadOS 26.1** where, for view
controllers presented as popovers, `traitCollectionDidChange()`/the registration-API handler
still fires (sometimes with a long delay) but `traitCollection.userInterfaceStyle` reports a
*stale* value inside that very callback. This is directly relevant if this codebase is
seeing "eventually fires, but reads the wrong value" symptoms on iOS 26.
[Apple Forums #806665](https://developer.apple.com/forums/thread/806665) ·
[Apple Forums #799161 – iOS 26 Beta 9 dark/light traits behaviour](https://developer.apple.com/forums/thread/799161)

---

## 5. Flutter-specific: does a Flutter-side theme change reach the native platform-view trait collection at all?

**🔥 No — not automatically, and this is architecturally by design, not a bug to "fix" on
the Flutter side.** Two separate signal paths exist and they do not talk to each other:

- **`MediaQuery.platformBrightness` / `PlatformDispatcher.platformBrightness` is a pure
  OS-level signal** (Settings ▸ Display & Brightness, or Control Center). It reports what
  the *system* thinks the brightness is and is completely unaware of and unaffected by a
  Flutter app's own `ThemeMode`/in-app theme toggle. If a user picks "dark" inside the app's
  own theme picker while the OS is set to light, `platformBrightness` still reports `.light`.
  This is documented, intentional Flutter behavior, not a bug.
  [flutter/flutter#28284](https://github.com/flutter/flutter/issues/28284)
- **A Flutter-side `ThemeMode.light`/`ThemeMode.dark` override changes what `Theme.of(context)`
  resolves to inside the Flutter widget tree ONLY.** It does not, by itself, touch
  `UIWindow.overrideUserInterfaceStyle`, `UIViewController.overrideUserInterfaceStyle`, or
  any native trait collection. Native platform views are outside the Flutter widget tree —
  they are real `UIView`s composited alongside the Flutter surface — so they follow UIKit's
  own trait-inheritance rules from the window/view-controller hierarchy, and nothing in
  stock Flutter pushes the in-app `ThemeMode` choice into that hierarchy.

**🌡️ Practical consequence, confirmed by multiple independent sources describing the same
pattern (Google Maps plugin, generic platform-view guidance):** plugin/embedded native
views are a "known weak spot" for exactly this reason — they don't automatically re-theme
when the Flutter-side theme changes; the app has to explicitly push brightness into them.

**🔥 The correct wiring, per the pattern that recurs across every source touching this
(not a single official "Flutter platform view theming" doc exists, but the mechanism is
consistent everywhere it's described):**
1. Keep a single Dart-side effective-brightness source of truth (already present in this
   codebase per the Theme service found while researching: it derives `Brightness` from
   `ThemeMode` + `platformDispatcher.platformBrightness` for the `system` case).
2. On every change to that effective brightness — not just OS brightness changes — push it
   across a `MethodChannel` to the native side.
3. On the native side, set `overrideUserInterfaceStyle` explicitly (on the platform view's
   root `UIView`, its owning `UIViewController`, or the `FlutterViewController`/window,
   depending on how broadly it should apply) in response to that channel message.
4. Do **not** rely on `didChangePlatformBrightness`/`platformBrightness` alone to drive
   native glass appearance, since it only fires for OS-level changes and is blind to
   `ThemeMode.light`/`ThemeMode.dark` app overrides — this is the single most likely
   explanation for "switching the in-app theme doesn't reach native glass" as opposed to
   "switching the OS theme doesn't reach it."

**🌡️ Timing/backgrounding caveat, independently reported:** even the OS-brightness signal
that Flutter *does* forward can lag — one Flutter engine issue describes brightness changes
from Control Center not reaching the Flutter build pipeline until the app returns to
foreground (`didChangePlatformBrightness` fires immediately, but the rebuild doesn't get
scheduled while inactive), with reported delays up to ~1400ms, while native UIKit chrome
updates immediately in the same window. This is a plausible contributor to "SOME glass
views take a long time to update" even where the wiring is otherwise correct.
[flutter/flutter#60027](https://github.com/flutter/flutter/issues/60027)

**Could not verify:** I found no engine source location (searched `FlutterViewController.mm`
headers/sources via api.flutter.dev and GitHub) where the Flutter iOS embedder itself sets
or reads `overrideUserInterfaceStyle` — the property isn't referenced in what's indexed by
Flutter's own doc site or turned up in the engine source I could reach. This suggests stock
Flutter does **not** do any of this automatically and it is entirely the embedding app's
(or the vendored `cupertino_native_better` package's) responsibility to wire it — but I
could not positively confirm this by reading the actual current `FlutterViewController.mm`
source (only older/mirrored snapshots surfaced in search).

---

## 6. Does a `UIHostingController`'s SwiftUI content fail to re-render on appearance change without explicit `\.colorScheme`?

**🌡️ Generally not required for the common case, but there are confirmed exceptions, and
one directly relevant iOS 26 report.** SwiftUI's environment/trait propagation is designed
to flow `colorScheme` down automatically from the hosting `UITraitCollection` — you do not
normally need to set `.environment(\.colorScheme, ...)` manually just for a
`UIHostingController` to pick up a system/window appearance change, *provided* the trait
change actually reaches the hosting controller's view (see §1/§2 above — this is
conditional on nothing upstream isolating the subtree via `overrideUserInterfaceStyle` or a
stale cached trait collection).

**🌡️ Confirmed failure modes that look like "SwiftUI ignores colorScheme":**
- Values baked once via UIKit appearance proxies (`UITabBar.appearance().barTintColor` etc.)
  at launch time do not re-resolve — this isn't a SwiftUI bug, it's the same static-resolve
  problem as §4, just via the appearance-proxy API instead of `CGColor`.
- `preferredColorScheme(_:)` driven by `@AppStorage` has been reported to lag — the
  environment value updates, but dependent view state doesn't always invalidate promptly;
  workaround reported is keying directly off the stored value rather than the environment
  read.
- At least one specific SwiftUI control (`SignInWithAppleButton` +
  `.signInWithAppleButtonStyle`) is reported to **not** respond to `colorScheme` changes at
  all without forcing view identity invalidation via `.id(colorScheme)` — evidence that
  "the environment updates but the view doesn't re-render" is a real, if control-specific,
  category of bug in SwiftUI, not purely theoretical.

**❄️ iOS 26-specific, single unconfirmed report:** a developer forum post describes a
`UIHostingController`-backed tab bar where, when the tab bar's *content* becomes
predominantly dark and its trait scope shifts, `traitCollectionDidChange()`/the equivalent
handler fires for that hosting controller but the poster explicitly asks whether this is
expected — i.e. this is an open question on Apple's own forums, not a resolved fact. Flagged
as ❄️ / unverified; do not treat as confirmed iOS 26 behavior.
[Apple Forums #799161](https://developer.apple.com/forums/thread/799161)

**Could not verify:** no official Apple document was found that states outright "a
`UIHostingController` requires explicit `\.colorScheme` injection to respond to trait
changes" — the weight of evidence says automatic propagation is the expected default
behavior, and the failure reports found are about specific controls or specific stale-cache
patterns, not a blanket SwiftUI/UIHostingController defect.

---

## Sources index

- [flutter/flutter#128735 – traitCollectionDidChange deprecated in iOS 17.0](https://github.com/flutter/flutter/issues/128735)
- [flutter/flutter#28284 – Manually changing PlatformBrightness](https://github.com/flutter/flutter/issues/28284)
- [flutter/flutter#60027 – App does not react to theme changes when in background](https://github.com/flutter/flutter/issues/60027)
- [Use Your Loaf – Registering For Trait Changes](https://useyourloaf.com/blog/registering-for-trait-changes/)
- [Apple Developer Forums #738836 – traitCollectionDidChange deprecated in Xcode 15](https://developer.apple.com/forums/thread/738836)
- [Apple Developer Forums #799161 – iOS 26 Beta 9 dark/light traits behaviour](https://developer.apple.com/forums/thread/799161)
- [Apple Developer Forums #806665 – iPadOS 26.1 traitCollection regression on popovers](https://developer.apple.com/forums/thread/806665)
- [Apple Developer Forums #791540 – Using GlassEffectContainer with UIKit](https://developer.apple.com/forums/thread/791540)
- [Apple Docs – overrideUserInterfaceStyle](https://developer.apple.com/documentation/uikit/uiviewcontroller/overrideuserinterfacestyle)
- [Apple Docs – registerForTraitChanges(_:handler:)](https://developer.apple.com/documentation/uikit/uitraitchangeobservable-67e94/registerfortraitchanges(_:handler:))
- [Apple Docs – UIBlurEffect.Style.systemThinMaterial](https://developer.apple.com/documentation/uikit/uiblureffect/style/systemthinmaterial)
- [Apple Docs – UIBlurEffect.Style.systemUltraThinMaterialDark](https://developer.apple.com/documentation/uikit/uiblureffect/style/systemultrathinmaterialdark)
- [Sarunw – Adopting iOS Dark Mode](https://sarunw.com/posts/adopting-ios-dark-mode/)
- [mixable Blog – Flutter on iOS: themeMode does not change to dark mode](https://mixable.blog/flutter-on-ios-thememode-does-not-change-to-dark-mode-if-thememode-system-is-used/)
