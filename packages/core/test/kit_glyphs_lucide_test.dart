import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:appbox_kit_core/appbox_kit_core.dart';

void main() {
  group('KitGlyphs.lucide', () {
    test('resolves Lucide design names (kebab-case) to the package glyph', () {
      expect(KitGlyphs.lucide('play'), LucideIcons.play);
      expect(KitGlyphs.lucide('pause'), LucideIcons.pause);
      expect(KitGlyphs.lucide('refresh-cw'), LucideIcons.refreshCw);
      expect(KitGlyphs.lucide('chevron-left'), LucideIcons.chevronLeft);
      expect(KitGlyphs.lucide('chevron-right'), LucideIcons.chevronRight);
      expect(KitGlyphs.lucide('pencil'), LucideIcons.pencil);
      expect(KitGlyphs.lucide('check'), LucideIcons.check);
      expect(KitGlyphs.lucide('volume-2'), LucideIcons.volume2);
      expect(KitGlyphs.lucide('x'), LucideIcons.x);
      expect(KitGlyphs.lucide('plus'), LucideIcons.plus);
      expect(KitGlyphs.lucide('arrow-left'), LucideIcons.arrowLeft);
    });

    test('generated map covers the fallback glyph', () {
      // The unknown-name release fallback is 'circle' — it must always exist.
      expect(kitLucideGlyphMap['circle'], LucideIcons.circle);
    });

    test('unknown name asserts in debug (release falls back to circle)', () {
      // flutter_test runs with asserts enabled, so the debug half of the
      // policy is observable here; the release half is `?? map['circle']!`.
      expect(() => KitGlyphs.lucide('no-such-icon'), throwsAssertionError);
    });
  });

  group('Material catalog (unchanged by the Lucide namespace)', () {
    test('paired glyph + sfSymbol entries are intact', () {
      expect(KitGlyphs.play.icon, Icons.play_arrow);
      expect(KitGlyphs.play.sfSymbol, 'play.fill');
      expect(KitGlyphs.back.icon, Icons.arrow_back_ios_new);
      expect(KitGlyphs.back.sfSymbol, 'chevron.backward');
    });
  });
}
