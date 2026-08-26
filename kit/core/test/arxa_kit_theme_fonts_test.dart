import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/arxa_kit_core.dart';

/// Increment 6's kit-side API: the 5-role accent bundles and the font
/// catalogue + family param the pipeline emits against.
///
/// Deliberately hermetic — no repo file I/O. Drift between the authored SSOTs
/// (`models/theme.json`, and `models/fonts.json` once Increment 4 lands it) and
/// `structure.json` is the gate's job (gate_structure.dart S1c), not a unit
/// test's. What is checked here is the API contract a generated app compiles
/// against.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('font catalogue', () {
    test('kit.core.fonts — declares the approved faces, in order, with their css names', () {
      expect(arxaKitFontOptions.map((f) => f.id).toList(),
          ['lexend', 'grotesk', 'lora', 'mono']);
      expect(arxaKitFontOptions.map((f) => f.cssName).toList(),
          ['Lexend', 'Space Grotesk', 'Lora', 'JetBrains Mono']);
    });

    test('kit.core.fonts — every face carries an OFL licence id', () {
      for (final f in arxaKitFontOptions) {
        expect(f.license, 'OFL-1.1', reason: '${f.id} must ship its licence');
      }
    });

    test('kit.core.fonts — the default names a face that exists', () {
      expect(arxaKitDefaultFont, 'lexend');
      expect(arxaKitFontOptions.any((f) => f.id == arxaKitDefaultFont), isTrue);
    });

    test('kit.core.fonts — arxaKitFontById resolves a known id', () {
      expect(arxaKitFontById('mono').cssName, 'JetBrains Mono');
    });

    test('kit.core.fonts — arxaKitFontById falls back rather than crashing on a removed face', () {
      // A host may have persisted an id that later left the catalogue.
      expect(arxaKitFontById('no-such-face').id, arxaKitDefaultFont);
    });

    test('kit.core.fonts — arxaKitFontForRole picks the first face declared for the slot', () {
      expect(arxaKitFontForRole(ArxaKitFontRole.ui)!.id, 'lexend');
      expect(arxaKitFontForRole(ArxaKitFontRole.display)!.id, 'grotesk');
      expect(arxaKitFontForRole(ArxaKitFontRole.mono)!.id, 'mono');
    });

    test('kit.core.fonts — no face is bundled yet — the catalogue is inert until a host '
        'declares the binaries in its pubspec', () async {
      // This is the honest state, not an aspiration: nothing under
      // packages/arxa_kit_core/fonts/ exists. When a host bundles the ttfs
      // this test is what tells you the wiring took.
      for (final f in arxaKitFontOptions) {
        expect(await arxaKitFontIsBundled(f), isFalse, reason: f.id);
      }
    });
  });

  group('theme family param', () {
    test('kit.core.theme — fontFamily applies across the whole ramp, light and dark', () {
      final light = arxaKitLightTheme(fontFamily: 'Lexend');
      expect(light.textTheme.bodyMedium!.fontFamily, 'Lexend');
      expect(light.textTheme.displayLarge!.fontFamily, 'Lexend');
      expect(light.primaryTextTheme.bodyMedium!.fontFamily, 'Lexend');

      final dark = arxaKitDarkTheme(fontFamily: 'Lexend');
      expect(dark.textTheme.bodyMedium!.fontFamily, 'Lexend');
      expect(dark.primaryTextTheme.bodyMedium!.fontFamily, 'Lexend');
    });

    test('kit.core.theme — omitting it leaves the platform default untouched', () {
      // Not `isNull` — Flutter's base theme names a platform face (Roboto on
      // the test host). The contract is that the kit does not impose one.
      expect(arxaKitLightTheme().textTheme.bodyMedium!.fontFamily,
          ThemeData.light().textTheme.bodyMedium!.fontFamily);
      expect(arxaKitDarkTheme().textTheme.bodyMedium!.fontFamily,
          ThemeData.dark().textTheme.bodyMedium!.fontFamily);
    });

    test('kit.core.theme — brightness is still correct with a family applied', () {
      expect(arxaKitLightTheme(fontFamily: 'Lora').brightness, Brightness.light);
      expect(arxaKitDarkTheme(fontFamily: 'Lora').brightness, Brightness.dark);
    });
  });

  group('accent swatches (the designer five)', () {
    test('kit.core.accents — five swatches in the authored order', () {
      expect(arxaKitAccentOptions.map((s) => s.name).toList(),
          ['cyan', 'violet', 'blue', 'ember', 'moss']);
    });

    test('kit.core.accents — the default names a swatch that exists', () {
      expect(arxaKitDefaultAccent, 'cyan');
      expect(arxaKitAccentOptions.any((s) => s.name == arxaKitDefaultAccent), isTrue);
    });

    test('kit.core.accents — arxaKitAccentByName falls back rather than crashing', () {
      expect(arxaKitAccentByName('violet').name, 'violet');
      expect(arxaKitAccentByName('removed-swatch').name, arxaKitDefaultAccent);
    });

    test('kit.core.accents — forBrightness is the only correct read and differs per mode', () {
      for (final s in arxaKitAccentOptions) {
        final light = s.forBrightness(Brightness.light);
        final dark = s.forBrightness(Brightness.dark);
        expect(identical(light, s.light), isTrue, reason: s.name);
        expect(identical(dark, s.dark), isTrue, reason: s.name);
        // Roles 3-5 are derived against opposite ramps, so they must not
        // collapse to the same value across modes.
        expect(light.surface, isNot(dark.surface), reason: s.name);
        expect(light.text, isNot(dark.text), reason: s.name);
      }
    });

    test('kit.core.accents — all five roles resolve to opaque-enough, distinct values', () {
      for (final s in arxaKitAccentOptions) {
        for (final r in [s.light, s.dark]) {
          expect(r.surface, isNot(r.accent), reason: s.name);
          expect(r.text, isNot(r.muted), reason: s.name);
          // The soft wash is translucent by contract; the solid is not.
          expect(r.accent.a, 1.0, reason: s.name);
          expect(r.soft.a, lessThan(1.0), reason: s.name);
        }
      }
    });
  });
}
