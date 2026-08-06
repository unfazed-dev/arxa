import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:appbox_kit_core/appbox_kit_core.dart';

void main() {
  group('AppBoxKitGlyphs.lucide', () {
    test('kit.core.glyphs — resolves Lucide design names (kebab-case) to the package glyph', () {
      expect(AppBoxKitGlyphs.lucide('play'), LucideIcons.play);
      expect(AppBoxKitGlyphs.lucide('pause'), LucideIcons.pause);
      expect(AppBoxKitGlyphs.lucide('refresh-cw'), LucideIcons.refreshCw);
      expect(AppBoxKitGlyphs.lucide('chevron-left'), LucideIcons.chevronLeft);
      expect(AppBoxKitGlyphs.lucide('chevron-right'), LucideIcons.chevronRight);
      expect(AppBoxKitGlyphs.lucide('pencil'), LucideIcons.pencil);
      expect(AppBoxKitGlyphs.lucide('check'), LucideIcons.check);
      expect(AppBoxKitGlyphs.lucide('volume-2'), LucideIcons.volume2);
      expect(AppBoxKitGlyphs.lucide('x'), LucideIcons.x);
      expect(AppBoxKitGlyphs.lucide('plus'), LucideIcons.plus);
      expect(AppBoxKitGlyphs.lucide('arrow-left'), LucideIcons.arrowLeft);
    });

    test('kit.core.glyphs — generated map covers the fallback glyph', () {
      // The unknown-name release fallback is 'circle' — it must always exist.
      expect(appBoxKitLucideGlyphMap['circle'], LucideIcons.circle);
    });

    test('kit.core.glyphs — unknown name asserts in debug (release falls back to circle)', () {
      // flutter_test runs with asserts enabled, so the debug half of the
      // policy is observable here; the release half is `?? map['circle']!`.
      expect(() => AppBoxKitGlyphs.lucide('no-such-icon'), throwsAssertionError);
    });
  });

  group('Material catalog (unchanged by the Lucide namespace)', () {
    test('kit.core.glyphs — paired glyph + sfSymbol entries are intact', () {
      expect(AppBoxKitGlyphs.play.icon, Icons.play_arrow);
      expect(AppBoxKitGlyphs.play.sfSymbol, 'play.fill');
      expect(AppBoxKitGlyphs.back.icon, Icons.arrow_back_ios_new);
      expect(AppBoxKitGlyphs.back.sfSymbol, 'chevron.backward');
    });
  });
}
