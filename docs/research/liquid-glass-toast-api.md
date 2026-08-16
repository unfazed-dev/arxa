# Apple Liquid Glass APIs & the "native glass toast" question (Aug 2026)

Web research, 2026-08-15. Primary sources: developer.apple.com (official doc-render
markdown endpoints at docs.developer.apple.com), pub.dev package pages, and the
fluttertoast GitHub source (via jsDelivr mirror). No blogs used as primary sources.

## Verdict

**PARTIALLY.** Liquid Glass itself IS public API since iOS 26 (SwiftUI `glassEffect`
family + UIKit `UIGlassEffect`), and a Flutter app CAN host real native Liquid Glass
controls by embedding UIKit/SwiftUI through platform views (pub package
`cupertino_native` and forks). But **Apple ships no first-party "toast"/transient
in-app notification API at all** — not in iOS 26, and nothing announced at WWDC26
("27" releases, June 2026) — so "the native Liquid Glass toast from Apple" is not a
turnkey thing anyone can call. A "native glass toast" can only exist as a
third-party-built container (SwiftUI/UIKit view, or a platform view from Flutter)
that the developer applies `glassEffect`/`UIGlassEffect` to themselves. The popular
`fluttertoast` package renders a plain `UIView`+`UILabel` overlay on the key window
and uses NO blur/glass effect whatsoever.

## 1. Liquid Glass public APIs (iOS 26.0+, verified on developer.apple.com)

SwiftUI (all verified available "iOS: 26.0.0 -"):
- `View/glassEffect(_:in:)` — apply glass to a custom view. Default is `Glass.regular`
  in a `Capsule`. https://developer.apple.com/documentation/SwiftUI/View/glassEffect(_:in:)
- `Glass` (struct) — variants `.regular`, `.tint(_)`, `.interactive()`.
  https://developer.apple.com/documentation/SwiftUI/Glass
- `GlassEffectContainer` — combines/morphs multiple glass shapes, better perf.
  https://developer.apple.com/documentation/SwiftUI/GlassEffectContainer
- `View/glassEffectID(_:in:)` — identity for morphing across containers.
  https://developer.apple.com/documentation/SwiftUI/View/glassEffectID(_:in:)
- `View/glassEffectUnion(id:namespace:)` — merge shapes into one glass capsule.
  https://developer.apple.com/documentation/SwiftUI/View/glassEffectUnion(id:namespace:)
- `View/glassEffectTransition(_:in:)` — glass morph transitions.
  https://developer.apple.com/documentation/SwiftUI/View/glassEffectTransition(_:in:)
- `PrimitiveButtonStyle.glass` — system glass button style.
  https://developer.apple.com/documentation/SwiftUI/PrimitiveButtonStyle/glass
- `View/backgroundExtensionEffect()` — mirror-and-blur background extension.
  https://developer.apple.com/documentation/SwiftUI/View/backgroundExtensionEffect()

UIKit:
- `UIGlassEffect` (Class, iOS 26+) — "A visual effect that renders a glass
  material"; attach to `UIVisualEffectView`.
  https://developer.apple.com/documentation/UIKit/UIGlassEffect
- `UIVisualEffectView` (iOS 8+) — the host view for visual effects.
  https://developer.apple.com/documentation/UIKit/UIVisualEffectView

Guides:
- Applying Liquid Glass to custom views —
  https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- Adopting Liquid Glass (overview) —
  https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- SF Symbols effects (Bounce, Wiggle, Rotate, Breathe, Magic Replace, Draw On/Off) —
  https://developer.apple.com/sf-symbols/ (page now describes iOS 27 availability)

## 2. Is there any first-party public toast API? NO.

- WWDC26 session list (136 sessions, https://developer.apple.com/videos/wwdc2026/):
  zero sessions about toasts or in-app transient messages. Confirms the "27"
  generation (Xcode 27, visionOS 27, Safari 27 sessions present).
- Official API-changes page "The 27 platform releases – June 2026"
  (https://developer.apple.com/documentation/updates): the words "toast" and
  "glass" appear nowhere. SwiftUI highlights = reorderable containers, State macro,
  document infra; UIKit highlights = compositional-layout observation, mandatory
  scene life cycle. (Page also states iOS 27 exists: "Starting in iOS 27, apps
  built with the latest SDK must use the scene-based life cycle".)
- `UNUserNotificationCenter` (iOS 10+) is the notification system, not an in-app
  toast API: authorization + system-delivered banners.
  https://developer.apple.com/documentation/UserNotifications/UNUserNotificationCenter
  `UNNotificationPresentationOptions.banner` = "Present the notification as a
  banner" (system presentation of a scheduled notification while app foregrounds —
  needs notification permission; not an app-UI toast).
  https://developer.apple.com/documentation/UserNotifications/UNNotificationPresentationOptions
- Volume HUD, AirDrop "sent" overlay, etc. are private system UI (no public API —
  verifiable by absence in the public UIKit/SwiftUI docs). `UISearchBar`'s results
  suggestion overlay is search-widget functionality, not a reusable toast API.

## 3. Flutter

- Flutter cannot render Apple's native Liquid Glass from Dart. Only routes:
  wrap SwiftUI/UIKit via platform views or method channels.
- pub.dev search "liquid glass" = 175 packages. The popular ones are Flutter-side
  SHADER IMITATIONS (several ship Android/Linux/web support, which proves they are
  not Apple's material): `liquid_glass` (iOS 18-style blur widget, all platforms),
  `liquid_glass_widgets` ("shader-based glassmorphism"), `liquid_glass_renderer`
  (882 likes, whynotmake.it, "raw renderer", experimental), `liquid_glass_easy`,
  `oc_liquid_glass` ("GPU-accelerated shaders").
  https://pub.dev/packages?q=liquid+glass
- NATIVE glass via platform views: `cupertino_native` (Serverpod; "hosts real
  UIKit/AppKit controls inside Flutter using Platform Views"; CNSlider, CNSwitch,
  CNSegmentedControl, CNButton, CNIcon, CNPopupMenuButton, CNTabBar — **no toast
  widget**; self-described proof of concept). Forks `cupertino_native_better` and
  `cupertino_native_plus` (adds CNGlassEffect, CNGlassEffectShape,
  CNGlassButtonGroup — still **no toast**). `native_glass_navbar` = nav bar only.
  https://pub.dev/packages/cupertino_native
- NO pub.dev package provides a NATIVE glass toast. Flutter-side glass-styled
  toasts exist as imitations: `simple_dialogs_flutter` ("context-less Liquid Glass
  dialog and toast system", Flutter overlay + physics animations);
  `glovex_liquid_ui`/`mjn_liquid_ui` expose a `LiquidGlassToast` class (Flutter
  UI kit, not native).
- `fluttertoast` (ponnamkarthik) — verified from source
  (`ios/fluttertoast/Sources/fluttertoast/FluttertoastPlugin.m`, `UIView+Toast.m`):
  method channel `PonnamKarthik/fluttertoast` → `[[weakSelf _readKeyWindow]
  makeToast:...]` → CSToast `UIView+Toast` ObjC category → a plain `UIView`
  wrapper (`layer.cornerRadius = style.cornerRadius`) containing `UILabel`
  (+optional title label/image), added via `addSubview` on the key window.
  Grep of `UIView+Toast.m`: UIVisualEffectView 0x, UIBlurEffect 0x, UIGlassEffect
  0x, UILabel 6x. So on iOS fluttertoast is a flat UILabel/UIView overlay — no
  blur, no Liquid Glass. (`native_toast_pro` likewise: "custom UIView
  implementation for iOS".)
  https://pub.dev/packages/fluttertoast
