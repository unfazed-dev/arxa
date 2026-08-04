import 'package:flutter/foundation.dart'
    show immutable, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;

/// The kit's selectable text faces.
///
/// MIRRORS `designs/appbox-studio/models/fonts.json` — the designer-side
/// catalogue. That file is NOT in the repo yet: authoring it (and vendoring the
/// woff2) is Increment 4's deliverable. This list is the approved decision —
/// Lexend default plus Space Grotesk, Lora and JetBrains Mono, all OFL — written
/// down so the pipeline and the kit name the same faces by the same ids. When
/// fonts.json lands, `emit_structure` lifts it into structure@2 as a `fonts`
/// block and this list must be reconciled against it.
///
/// -- What this file does and does not give you ----------------------------
/// It gives you the CATALOGUE: ids, labels, the family name a renderer
/// resolves, role slots and licences. It does NOT bundle font binaries.
/// The designer side vendors `.woff2` (web); Flutter needs `.ttf`/`.otf`
/// declared under `flutter: fonts:` in a pubspec. No host bundles them yet, so
/// [kitFontIsBundled] is false for every face today and [KitFontFamily.cssName]
/// passed to Flutter's `fontFamily:` resolves to nothing — Flutter SILENTLY
/// falls back to the platform default: no error, just the wrong face.
/// [kitFontIsBundled] is the honest test, and [registerKitFontLicenses] is what
/// a host calls once it has bundled them.

/// The role slots declared by fonts.json `roles`.
enum KitFontRole {
  /// body copy, controls, everything unmarked
  ui,

  /// headings and the shell's large type
  display,

  /// code, log timestamps, tabular figures
  mono,
}

/// One selectable text face.
@immutable
class KitFontFamily {
  /// Stable identifier — matches fonts.json `families[].id` and is the value a
  /// host persists. NOT [label]: a menu label may be renamed freely.
  final String id;

  /// Human label for a picker.
  final String label;

  /// The family name a renderer resolves — fonts.json `cssName`, and the
  /// string to hand to Flutter's `fontFamily:` once the face is bundled.
  final String cssName;

  /// Which slot this face is authored for.
  final KitFontRole role;

  /// SPDX licence id, carried so a host can honour attribution.
  final String license;

  const KitFontFamily({
    required this.id,
    required this.label,
    required this.cssName,
    required this.role,
    required this.license,
  });
}

/// Mirrors fonts.json `families`, in the same order.
const List<KitFontFamily> kitFontOptions = [
  KitFontFamily(
    id: 'lexend',
    label: 'Lexend',
    cssName: 'Lexend',
    role: KitFontRole.ui,
    license: 'OFL-1.1',
  ),
  KitFontFamily(
    id: 'grotesk',
    label: 'Space Grotesk',
    cssName: 'Space Grotesk',
    role: KitFontRole.display,
    license: 'OFL-1.1',
  ),
  KitFontFamily(
    id: 'lora',
    label: 'Lora',
    cssName: 'Lora',
    role: KitFontRole.ui,
    license: 'OFL-1.1',
  ),
  KitFontFamily(
    id: 'mono',
    label: 'JetBrains Mono',
    cssName: 'JetBrains Mono',
    role: KitFontRole.mono,
    license: 'OFL-1.1',
  ),
];

/// Mirrors fonts.json `default`.
const String kitDefaultFont = 'lexend';

/// The face with [id], or the [kitDefaultFont] one when unknown — a persisted
/// setting naming a removed face must not crash a host.
KitFontFamily kitFontById(String id) {
  for (final f in kitFontOptions) {
    if (f.id == id) return f;
  }
  for (final f in kitFontOptions) {
    if (f.id == kitDefaultFont) return f;
  }
  return kitFontOptions.first;
}

/// The first face declared for [role], or null when none is.
KitFontFamily? kitFontForRole(KitFontRole role) {
  for (final f in kitFontOptions) {
    if (f.role == role) return f;
  }
  return null;
}

/// Whether [family]'s binary is actually bundled and resolvable.
///
/// Flutter gives no way to ask "is this family registered?", so this probes the
/// asset path the kit expects a host to bundle at. Use it to fail loudly in a
/// host's own test rather than shipping a silent platform-default fallback.
Future<bool> kitFontIsBundled(KitFontFamily family) async {
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
void registerKitFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final f in kitFontOptions) {
      if (!await kitFontIsBundled(f)) continue;
      final text =
          await rootBundle.loadString('packages/appbox_kit_core/fonts/${f.id}.LICENSE');
      yield LicenseEntryWithLineBreaks(<String>['appbox_kit_core', f.cssName], text);
    }
  });
}
