import 'package:flutter/foundation.dart'
    show immutable, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart' show GoogleFonts;

/// The kit's selectable text faces.
///
/// Font law v2 (ratified): type families are **Google Fonts by name** on both
/// sides of the pipeline. The designer emits a css2 stylesheet link from the
/// Google Fonts CDN (no vendored `.woff2`); a scaffolded Flutter app resolves
/// families through the `google_fonts` package, driven by
/// `assets.manifest.json` font roles. Nobody vendors binaries — the sole
/// exception is a custom brand font uploaded at intake (manifest
/// `"source": "file"`), which ships in the app's `assets/fonts/` with a real
/// pubspec `fonts:` block.
///
/// -- What this file does and does not give you ----------------------------
/// It gives you the CATALOGUE: ids, labels, the family name a renderer
/// resolves (`cssName` — also the name handed to `google_fonts`), role slots
/// and licences. It does NOT bundle font binaries. [appBoxKitFontIsBundled]
/// probes the kit-bundled `.ttf` path and is therefore false for every face
/// under the law's default path (google_fonts resolves at runtime instead);
/// it only turns true for the "source": "file" exception, and
/// [registerAppBoxKitFontLicenses] is what a host calls in that case — OFL
/// requires the licence travel with a bundled binary.

/// The role slots declared by fonts.json `roles`.
enum AppBoxKitFontRole {
  /// body copy, controls, everything unmarked
  ui,

  /// headings and the shell's large type
  display,

  /// code, log timestamps, tabular figures
  mono,
}

/// One selectable text face.
@immutable
class AppBoxKitFontFamily {
  /// Stable identifier — matches fonts.json `families[].id` and is the value a
  /// host persists. NOT [label]: a menu label may be renamed freely.
  final String id;

  /// Human label for a picker.
  final String label;

  /// The family name a renderer resolves — fonts.json `cssName`, and the
  /// string to hand to Flutter's `fontFamily:` once the face is bundled.
  final String cssName;

  /// Which slot this face is authored for.
  final AppBoxKitFontRole role;

  /// SPDX licence id, carried so a host can honour attribution.
  final String license;

  const AppBoxKitFontFamily({
    required this.id,
    required this.label,
    required this.cssName,
    required this.role,
    required this.license,
  });
}

/// Mirrors fonts.json `families`, in the same order.
const List<AppBoxKitFontFamily> appBoxKitFontOptions = [
  AppBoxKitFontFamily(
    id: 'lexend',
    label: 'Lexend',
    cssName: 'Lexend',
    role: AppBoxKitFontRole.ui,
    license: 'OFL-1.1',
  ),
  AppBoxKitFontFamily(
    id: 'grotesk',
    label: 'Space Grotesk',
    cssName: 'Space Grotesk',
    role: AppBoxKitFontRole.display,
    license: 'OFL-1.1',
  ),
  AppBoxKitFontFamily(
    id: 'lora',
    label: 'Lora',
    cssName: 'Lora',
    role: AppBoxKitFontRole.ui,
    license: 'OFL-1.1',
  ),
  AppBoxKitFontFamily(
    id: 'mono',
    label: 'JetBrains Mono',
    cssName: 'JetBrains Mono',
    role: AppBoxKitFontRole.mono,
    license: 'OFL-1.1',
  ),
];

/// Mirrors fonts.json `default`.
const String appBoxKitDefaultFont = 'lexend';

/// The face with [id], or the [appBoxKitDefaultFont] one when unknown — a persisted
/// setting naming a removed face must not crash a host.
AppBoxKitFontFamily appBoxKitFontById(String id) {
  for (final f in appBoxKitFontOptions) {
    if (f.id == id) return f;
  }
  for (final f in appBoxKitFontOptions) {
    if (f.id == appBoxKitDefaultFont) return f;
  }
  return appBoxKitFontOptions.first;
}

/// The first face declared for [role], or null when none is.
AppBoxKitFontFamily? appBoxKitFontForRole(AppBoxKitFontRole role) {
  for (final f in appBoxKitFontOptions) {
    if (f.role == role) return f;
  }
  return null;
}

/// Whether [family]'s binary is actually bundled and resolvable.
///
/// Flutter gives no way to ask "is this family registered?", so this probes the
/// asset path the kit expects a host to bundle at. Use it to fail loudly in a
/// host's own test rather than shipping a silent platform-default fallback.
Future<bool> appBoxKitFontIsBundled(AppBoxKitFontFamily family) async {
  try {
    await rootBundle.load('packages/appbox_kit_core/fonts/${family.id}.ttf');
    return true;
  } catch (_) {
    return false;
  }
}

/// Registers the OFL text for every bundled face. Call once at startup, before
/// `runApp`, in any host that bundles the binaries — OFL-1.1 requires the
/// licence travel with the font.
void registerAppBoxKitFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final f in appBoxKitFontOptions) {
      if (!await appBoxKitFontIsBundled(f)) continue;
      final text = await rootBundle
          .loadString('packages/appbox_kit_core/fonts/${f.id}.LICENSE');
      yield LicenseEntryWithLineBreaks(
          <String>['appbox_kit_core', f.cssName], text);
    }
  });
}

// --- Runtime resolution through `google_fonts` (font law v2 default path) ---

/// Resolves [face] through `google_fonts`: registers the face's runtime loader
/// with Flutter's font registry and returns the fontFamily string that
/// `ThemeData`/`TextStyle.fontFamily:` will actually resolve — this is what
/// makes an unbundled catalogue face render instead of falling back to the
/// platform default silently (see [appBoxKitFontIsBundled]).
///
/// The scaffolder emits exactly this wiring into generated apps, driven by
/// `assets.manifest.json` font roles; the showcase app demos it in `main.dart`
/// by passing [appBoxKitDefaultGoogleFontFamily] to `appBoxKitLightTheme` /
/// `appBoxKitDarkTheme`.
///
/// Throws for a family name unknown to `google_fonts` — the catalogue only
/// lists Google Fonts faces, so an unknown name is a catalogue bug, not a
/// runtime condition. The sole non-Google exception ("source": "file" custom
/// brand fonts) bundles binaries under a pubspec `fonts:` block and never
/// reaches this resolver.
String appBoxKitGoogleFontFamily(AppBoxKitFontFamily face) =>
    GoogleFonts.getFont(face.cssName).fontFamily ?? face.cssName;

/// The [appBoxKitDefaultFont] face (`fonts.json` `default`), resolved and
/// registered through `google_fonts` — the app-wide `ui`-role family a host
/// passes to the kit theme builders.
String appBoxKitDefaultGoogleFontFamily() =>
    appBoxKitGoogleFontFamily(appBoxKitFontById(appBoxKitDefaultFont));
