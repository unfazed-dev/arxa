/// Reusable brand layer for arxa_kit-built apps.
///
/// Ships:
/// - [ArxaKitBrandSplash] — a presentational splash/startup widget (logo +
///   progress).
/// - `tools/generate_branding.sh` + `templates/` — a codegen step that vendors
///   the kit warm-neutral color ramp into a host app as
///   `generated/brand_colors.dart`, with the brand accent seeded from the host's
///   `app_colors.dart` (kcPrimaryColor). The theme BUILDER (arxaKitLightTheme/
///   arxaKitDarkTheme) is never copied — only the color constants.
///
/// This package depends only on Flutter. A kit-themed host and a custom-themed
/// host both render correctly because [ArxaKitBrandSplash] reads
/// `Theme.of(context)`.
library;

export 'src/arxa_kit_startup_view.dart' show ArxaKitBrandSplash;
