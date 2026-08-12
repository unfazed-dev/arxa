# Overview
- This project is a Flutter plugin which displays native iOS and MacOS widgets in Flutter using platform channels.
- The Flutter widgets are in the lib/components directory.
- Look at previous widgets when creating a new one to match the style.
- Each widget should have:
  - A separate file and class.
  - An example page in the example/demos directory
  - Corresponding Swift code for iOS and MacOS.
- Follow Flutter conventions for the Flutter widgets.
- After writing code, always check the Dart code with `flutter analyze`

## Liquid glass theme handling (iOS 26) — read before touching the native tier

Hybrid platform views do NOT re-sample glass on trait/config mutation; every
native view type carries the cure in its `setBrightness` handler, and every
new native view type MUST implement the same stack or it will lag on theme
flips (evidence per component, clip by clip:
`docs/plans/native-glass-theme-lag-measured.md` in the app-box repo):

1. Scope `overrideUserInterfaceStyle` to the view (container AND hosting
   controller) — never window-level, never `.preferredColorScheme` (both pin
   the window and break `ThemeMode.system`).
2. Force recreation, not mutation: SwiftUI tier = `@Published isDark` + epoch
   `.id` + rootView re-root; UIKit tier = configuration teardown + hierarchy
   re-attach. Wrap in `CNAppearance.applyInstantly` (no animation).
3. End every `setBrightness` handler with a `CNAppearanceSettleReplay.poke`
   replaying the same apply — rapid flip storms coalesce in the render
   server and strand views on the previous theme without it.
4. Popup triggers (SwiftUI `Menu`): custom glass hoisted onto the Menu,
   `.menuStyle(.borderlessButton)`. The dismiss flash is a known Apple bug
   (accepted) — do NOT "fix" it with `.buttonStyle(.glass)`; that was tried
   (rounds 10–12) and rejected: undocumented style padding breaks the
   configured 44/56pt geometry.
5. Run `tool/check_theme_wiring.sh` — it fails if any brightness-handling
   view (Swift or Dart) is under-wired or a banned pattern reappears.
