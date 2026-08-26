# branding

Reusable brand layer for `arxa_kit`-built apps. Depends **only on Flutter** —
the host's `ThemeData` styles it, so a kit-themed host and a custom-themed host
both render correctly.

## What it ships

| Path | Purpose |
|------|---------|
| `lib/src/arxa_kit_startup_view.dart` | Presentational splash widget `ArxaKitBrandSplash`: centered brand mark + bottom progress bar (`Loading · N%`). Owns **no** routing or auth — the host view-model drives those. Named `ArxaKitBrandSplash` (not `StartupView`) to avoid colliding with every Stacked app's own `StartupView` route. exposes `static const double logoSize = 80` — the canonical brand-logo edge (dp), the pipeline SSOT for logo size. |
| `lib/arxa_kit_branding.dart` | Barrel export (`ArxaKitBrandSplash`). |
| `templates/brand_colors.dart.tmpl` | Kit warm-neutral ramp as `BrandColors` / `BrandDarkColors`, with `{{ACCENT_ARGB}}` placeholder. |
| `templates/launcher_icons.yaml.tmpl` | `flutter_launcher_icons` config per the brand-icons law (2026-08-09): master + adaptive foreground + Android 13+ theme-adaptive monochrome layer + iOS 18 dark/tinted variants + web icons, all from the app's own `assets/brand-icons/` master (mirrors `assets.manifest.json` `brandIcon`). |
| `templates/splash.yaml.tmpl` | native splash whose background is the kit surface (`#F5F0E8` light / `#1C1814` dark, via `color_dark` for system-theme) — NOT the brand accent — and whose `image:` is a dedicated `<base>-splash.png` (+ a transparent padded `<base>-splash-android12.png` with theme-reactive `icon_background_color(_dark)` for the Android 12+ path). |
| `tools/generate_branding.sh` | Idempotent codegen: resolves the brand master from `assets.manifest.json` `brandIcon` (or infers it in `assets/brand-icons/`), emits both configs into the host, and rasterizes `assets/brand-icons/<base>-splash.png` at 4× logoSize (320px, macOS `sips`) plus `<base>-splash-android12.png` (334px logo centered on a transparent 960px canvas, PIL). Legacy hosts with `lib/ui/common/app_colors.dart` additionally get `generated/brand_colors.dart` from their `kcPrimaryColor`; kit-native hosts skip it (colors come from `arxa_kit_core`). |

## The color contract (why a generated copy — LEGACY hosts only)

Kit-native hosts (anything scaffolded on `arxa_kit_core`) take their colors
from the kit directly — no vendored copy is emitted. For legacy hosts that
carry `lib/ui/common/app_colors.dart`: the host owns its brand colors locally
(`generated/brand_colors.dart`) so host views need no `arxa_kit` import for
color values, and the brand accent comes from the host's own `app_colors.dart`
— not the kit default. The **theme builder**
(`kitLightTheme` / `kitDarkTheme`) is deliberately **not** copied: it stays
imported via `package:ui_library`, and the host passes its local accent in:

```dart
// host main.dart
theme: kitLightTheme(accent: BrandColors.accent),
darkTheme: kitDarkTheme(accent: BrandColors.accent),
```

Regenerating each pipeline run keeps the vendored ramp drift-free with
`arxa_kit_colors.dart`. `arxa_kit_colors.dart` itself is never modified.

## Usage (pipeline / manual)

```sh
# 1. emit configs + brand_colors into the host (pure bash, no Flutter needed)
arxa_kit/branding/tools/generate_branding.sh /path/to/host_app

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

**Splash background = app surface, not accent.** The native splash background is the kit theme's `scaffoldBackgroundColor` — `ArxaKitColors.surface` (`#F5F0E8`) light / `ArxaKitDarkColors.bone` (`#1C1814`) dark — emitted with `color` + `color_dark` so it follows the system theme and matches the in-Flutter `ArxaKitBrandSplash` (`colorScheme.surface`) with no seam. NOT the brand accent (an accent splash clashed with the warm surface and couldn't go dark). **Web is part of the same contract:** `web/index.html` must stay normalized to the reference (`kit/showcase_app/web/index.html`, law: scaffolder SKILL.md "Web entrypoint") — the `flutter_native_splash` web output keeps the same surface pair via `prefers-color-scheme`, and the head carries the font-law preconnect pair (`fonts.googleapis.com` + `fonts.gstatic.com` crossorigin) with no css2 stylesheet and no font binaries (`google_fonts` fetches at runtime). `scripts/branding_gate.sh` asserts all of it when `web/` exists.

**Logo size is a pipeline token.** `ArxaKitBrandSplash.logoSize = 80` (dp) is the SSOT — the host binds its logo `Image.asset` width/height to it. `flutter_native_splash` renders `image:` at its SOURCE pixel dimensions (no upscale), so pointing it at the full-res 1024px brand master made the OS splash logo enormous. `generate_branding.sh` therefore rasterizes a dedicated `assets/brand-icons/<base>-splash.png` at 4×80 = 320px (via macOS `sips`). **Android 12+ is different:** it renders the `android_12.image` inside a fixed ~240dp icon window, so the on-screen size is the logo's *fraction* of a 960px canvas, not raw px — a full-frame master rendered the logo ~2.9× the iOS one. `generate_branding.sh` instead centers a 334px logo on a **transparent** 960px canvas (`<base>-splash-android12.png`) so android_12 matches the iOS native-splash size, and `icon_background_color` / `icon_background_color_dark` supply the theme-reactive backdrop behind the transparent canvas. Matches the asko reference (`logoSize: 80`).

**Startup timing.** `FlutterNativeSplash.preserve()` (host `main.dart`) → `FlutterNativeSplash.remove()` is called FIRST in the startup view-model's `runStartupLogic` (it runs from `onViewModelReady`'s post-frame callback, so the `StartupView` has already painted — no blank frame), then the in-Flutter loading bar runs for `startupLoadingDuration` (2000ms) before routing. Calling `remove()` AFTER the loading wait (the old code) kept the native splash covering the logo + progress bar for the whole duration, so they were never seen.
