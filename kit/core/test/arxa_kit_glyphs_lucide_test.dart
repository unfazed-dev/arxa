import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:arxa_kit_core/arxa_kit_core.dart';

void main() {
  group('ArxaKitGlyphs.lucide', () {
    test('kit.core.glyphs — resolves Lucide design names (kebab-case) to the package glyph', () {
      expect(ArxaKitGlyphs.lucide('play'), LucideIcons.play);
      expect(ArxaKitGlyphs.lucide('pause'), LucideIcons.pause);
      expect(ArxaKitGlyphs.lucide('refresh-cw'), LucideIcons.refreshCw);
      expect(ArxaKitGlyphs.lucide('chevron-left'), LucideIcons.chevronLeft);
      expect(ArxaKitGlyphs.lucide('chevron-right'), LucideIcons.chevronRight);
      expect(ArxaKitGlyphs.lucide('pencil'), LucideIcons.pencil);
      expect(ArxaKitGlyphs.lucide('check'), LucideIcons.check);
      expect(ArxaKitGlyphs.lucide('volume-2'), LucideIcons.volume2);
      expect(ArxaKitGlyphs.lucide('x'), LucideIcons.x);
      expect(ArxaKitGlyphs.lucide('plus'), LucideIcons.plus);
      expect(ArxaKitGlyphs.lucide('arrow-left'), LucideIcons.arrowLeft);
    });

    test('kit.core.glyphs — generated map covers the fallback glyph', () {
      // The unknown-name release fallback is 'circle' — it must always exist.
      expect(arxaKitLucideGlyphMap['circle'], LucideIcons.circle);
    });

    test('kit.core.glyphs — unknown name asserts in debug (release falls back to circle)', () {
      // flutter_test runs with asserts enabled, so the debug half of the
      // policy is observable here; the release half is `?? map['circle']!`.
      expect(() => ArxaKitGlyphs.lucide('no-such-icon'), throwsAssertionError);
    });
  });

  group('Material catalog (unchanged by the Lucide namespace)', () {
    test('kit.core.glyphs — paired glyph + sfSymbol entries are intact', () {
      expect(ArxaKitGlyphs.play.icon, Icons.play_arrow);
      expect(ArxaKitGlyphs.play.sfSymbol, 'play.fill');
      expect(ArxaKitGlyphs.back.icon, Icons.arrow_back_ios_new);
      expect(ArxaKitGlyphs.back.sfSymbol, 'chevron.backward');
    });
  });
}
