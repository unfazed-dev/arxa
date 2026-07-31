# branding

Reusable brand layer for `appbox_kit`-built apps. Depends **only on Flutter** —
the host's `ThemeData` styles it, so a kit-themed host and a custom-themed host
both render correctly.

## What it ships

| Path | Purpose |
|------|---------|
| `lib/src/startup_view.dart` | Presentational splash widget `BrandSplash`: centered brand mark + bottom progress bar (`Loading · N%`). Owns **no** routing or auth — the host view-model drives those. Named `BrandSplash` (not `StartupView`) to avoid colliding with every Stacked app's own `StartupView` route. exposes `static const double logoSize = 80` — the canonical brand-logo edge (dp), the pipeline SSOT for logo size. |
| `lib/branding.dart` | Barrel export (`BrandSplash`). |
| `templates/brand_colors.dart.tmpl` | Kit warm-neutral ramp as `BrandColors` / `BrandDarkColors`, with `{{ACCENT_ARGB}}` placeholder. |
| `templates/launcher_icons.yaml.tmpl` | `flutter_launcher_icons` config (`assets/icons/icon.png`). |
| `templates/splash.yaml.tmpl` | native splash whose background is the kit surface (`#F5F0E8` light / `#1C1814` dark, via `color_dark` for system-theme) — NOT the brand accent — and whose `image:` is a dedicated `splash_logo.png` (+ a padded `splash_logo_android12.png` for the Android 12+ path). |
| `tools/generate_branding.sh` | Idempotent codegen: reads the host's `kcPrimaryColor`, emits the three files above into the host. also rasterizes `assets/icons/splash_logo.png` at 4× logoSize (320px) and a padded `assets/icons/splash_logo_android12.png` (232px logo in a 960px canvas) from `icon.png` via macOS `sips` (non-mac falls back to a copy; the gate then fails on oversize). |

## The color contract (why a generated copy)

The host owns its brand colors locally (`generated/brand_colors.dart`) so host
views need no `appbox_kit` import for color values, and the brand accent comes
from the host's own `app_colors.dart` — not the kit default. The **theme builder**
(`kitLightTheme` / `kitDarkTheme`) is deliberately **not** copied: it stays
imported via `package:ui_library`, and the host passes its local accent in:

```dart
// host main.dart
theme: kitLightTheme(accent: BrandColors.accent),
darkTheme: kitDarkTheme(accent: BrandColors.accent),
```

Regenerating each pipeline run keeps the vendored ramp drift-free with
`kit_colors.dart`. `kit_colors.dart` itself is never modified.

## Usage (pipeline / manual)

```sh
# 1. emit configs + brand_colors into the host (pure bash, no Flutter needed)
appbox_kit/branding/tools/generate_branding.sh /path/to/host_app

# 2. host must declare (dev) deps, then generate assets:
cd /path/to/host_app
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

The native splash hands off to the in-Flutter `StartupView` via
`FlutterNativeSplash.preserve()` (host `main.dart`) → `FlutterNativeSplash.remove()`
(host startup view-model ASAP at the start of the startup logic (post-first-frame), so the in-Flutter loading shows immediately — NOT after the loading wait, which hid it behind the native splash). Because the host calls those runtime
APIs, `flutter_native_splash` is a **regular** dependency in the host (it remains
a `dev_dependency` here, used only for generation).

## Splash background, logo size & startup timing

**Splash background = app surface, not accent.** The native splash background is the kit theme's `scaffoldBackgroundColor` — `KitColors.surface` (`#F5F0E8`) light / `KitDarkColors.bone` (`#1C1814`) dark — emitted with `color` + `color_dark` so it follows the system theme and matches the in-Flutter `BrandSplash` (`colorScheme.surface`) with no seam. NOT the brand accent (an accent splash clashed with the warm surface and couldn't go dark).

**Logo size is a pipeline token.** `BrandSplash.logoSize = 80` (dp) is the SSOT — the host binds its logo `Image.asset` width/height to it. `flutter_native_splash` renders `image:` at its SOURCE pixel dimensions (no upscale), so pointing it at the full-res 1024px launcher `icon.png` made the OS splash logo enormous. `generate_branding.sh` therefore rasterizes a dedicated `assets/icons/splash_logo.png` at 4×80 = 320px (via macOS `sips`). **Android 12+ is different:** it renders the `android_12.image` inside a fixed ~240dp icon window, so the on-screen size is the logo's *fraction* of a 960px canvas, not raw px — the full-frame `icon.png` rendered the logo ~2.9× the iOS one. `generate_branding.sh` instead pads a small logo (~232px, ≈24% of canvas) into a 960px canvas (`assets/icons/splash_logo_android12.png`) so android_12 matches the iOS native-splash size. Matches the asko reference (`logoSize: 80`).

**Startup timing.** `FlutterNativeSplash.preserve()` (host `main.dart`) → `FlutterNativeSplash.remove()` is called FIRST in the startup view-model's `runStartupLogic` (it runs from `onViewModelReady`'s post-frame callback, so the `StartupView` has already painted — no blank frame), then the in-Flutter loading bar runs for `startupLoadingDuration` (2000ms) before routing. Calling `remove()` AFTER the loading wait (the old code) kept the native splash covering the logo + progress bar for the whole duration, so they were never seen.
