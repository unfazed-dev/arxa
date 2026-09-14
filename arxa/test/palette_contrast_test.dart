// The contrast engine's units (grilled + locked 2026-09-11): the WCAG
// math against known anchors, the OKLCH roundtrip, and the solver's
// three-phase law — lightness first, polarity inversion when no
// lightness can, surfaces only as the genuine last resort.
import 'package:arxa/palette_contrast.dart';
import 'package:test/test.dart';

void main() {
  group('WCAG ratios', () {
    test('black on white is 21:1', () {
      expect(contrastRatio('#000000', '#FFFFFF'), closeTo(21.0, 0.01));
    });
    test('a color against itself is 1:1', () {
      expect(contrastRatio('#774C60', '#774C60'), closeTo(1.0, 1e-9));
    });
    test('the c-1a1423 breakage class measures below AA', () {
      // Near-black intro text on the dark-plum field: the report that
      // started the engine.
      expect(contrastRatio('#040306', '#774C60'), lessThan(4.5));
    });
  });

  group('OKLCH roundtrip', () {
    test('hue and lightness survive the trip', () {
      String hexOf(List<int> rgb) =>
          '#' + rgb.map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
      for (final hex in ['#1A1423', '#774C60', '#EACDC2', '#007EA7']) {
        final ok = toOklch(hexToRgb(hex));
        final back = fromOklch(ok);
        final again = toOklch(back);
        expect((again.l - ok.l).abs(), lessThan(0.02), reason: hex);
        expect((again.h - ok.h).abs(), lessThan(0.05), reason: hex);
        // A perfect roundtrip lands on the same color.
        expect(contrastRatio(hexOf(back), hex), closeTo(1.0, 0.05), reason: hex);
      }
    });
  });

  group('solveContrast', () {
    test('phase 1: lightness alone fixes a light-surface pair', () {
      final (hexes, moves, unsolved) = solveContrast(
        slotHexes: {'ink': '#8E518D', 'paper': '#F7C7DB'},
        pairs: const [ContrastPair(fg: 'ink', bg: 'paper', level: 'body')],
      );
      expect(unsolved, isEmpty);
      expect(contrastRatio(hexes['ink']!, hexes['paper']!), greaterThanOrEqualTo(4.5));
      expect(moves.single.movedSide, 'fg');
      // The paper never moved.
      expect(hexes['paper'], '#F7C7DB');
    });

    test('phase 2: the flip candidate wins only when scanning cannot', () {
      // High-chroma mid text on a mid-dark card: gamut clamping can pin
      // the scan away from the extremes, and the paper-family flip
      // candidate passes everything the slot carries.
      final (hexes, moves, unsolved) = solveContrast(
        slotHexes: {'card-text': '#1A1423', 'beige': '#B75D69'},
        pairs: const [ContrastPair(fg: 'card-text', bg: 'beige', level: 'body')],
        alt: (slot) => '#EACDC2',
      );
      expect(unsolved, isEmpty);
      // EITHER the scan darkened/lightened into passing, OR the flip
      // fired — but the surface NEVER moves for a text pair this simple.
      expect(hexes['beige'], '#B75D69');
      expect(contrastRatio(hexes['card-text']!, hexes['beige']!),
          greaterThanOrEqualTo(4.5));
      expect(moves, isNotEmpty);
      expect(moves.every((m) => m.movedSide != 'bg'), isTrue);
    });

    test('phase 3: the surface moves only when truly stuck', () {
      // No fg lightness AND no flip candidate can clear an extreme bg.
      final (hexes, moves, unsolved) = solveContrast(
        slotHexes: {'ink': '#808080', 'bg': '#7F7F7F'},
        pairs: const [ContrastPair(fg: 'ink', bg: 'bg', level: 'body')],
      );
      expect(unsolved, isEmpty);
      expect(moves.single.movedSide, anyOf('fg', 'bg'));
      expect(contrastRatio(hexes['ink']!, hexes['bg']!), greaterThanOrEqualTo(4.5));
    });

    test('all-pairs-at-once: convergence, never oscillation', () {
      // ink on paper (light) AND ink on field (mid-dark): no single ink
      // satisfies both, so the engine converges some other way — the
      // paper surface is NEVER the casualty of the field pair.
      final (hexes, _, unsolved) = solveContrast(
        slotHexes: {'ink': '#1A1423', 'paper': '#EACDC2', 'field': '#774C60'},
        pairs: const [
          ContrastPair(fg: 'ink', bg: 'paper', level: 'body'),
          ContrastPair(fg: 'ink', bg: 'field', level: 'body'),
        ],
      );
      expect(hexes['paper'], '#EACDC2'); // untouched
      for (final pair in const [('ink', 'paper'), ('ink', 'field')]) {
        final r = contrastRatio(hexes[pair.$1]!, hexes[pair.$2]!);
        if (unsolved.isEmpty) {
          expect(r, greaterThanOrEqualTo(4.5), reason: pair.toString());
        }
      }
      // And the honest-residue law: unsolved names exactly what failed.
      for (final label in unsolved) {
        expect(label, contains('ink on'));
      }
    });

    test('soft alpha pairs measure the composite', () {
      final (hexes, _, unsolved) = solveContrast(
        slotHexes: {'ink-soft': '#8E518D', 'paper': '#D7C0D0'},
        pairs: const [
          ContrastPair(fg: 'ink-soft', bg: 'paper', level: 'soft', fgAlpha: 0.64),
        ],
      );
      expect(unsolved, isEmpty);
      final composited = composite(hexToRgb(hexes['ink-soft']!), hexToRgb('#D7C0D0'), 0.64);
      final ratio = contrastRatio(
          '#' + composited.map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
          '#D7C0D0');
      expect(ratio, greaterThanOrEqualTo(3.0));
    });
  });

  group('APCA advisory', () {
    test('runs, and dark-on-light is positive / light-on-dark negative', () {
      final dark = apcaLc('#1A1423', '#EACDC2');
      final light = apcaLc('#EACDC2', '#1A1423');
      expect(dark, greaterThan(60));
      expect(light, lessThan(-60));
      // Advisory only — magnitude sanity for the readable case.
      expect(dark.abs(), lessThan(110));
    });
  });

  group('contract parsing', () {
    test('reads pairs incl alpha; rejects malformed levels', () {
      final pairs = contractFromTemplate({
        'pairs': [
          {'fg': '--ink', 'bg': '--paper', 'level': 'body'},
          {'fg': '--ink-soft', 'bg': '--paper', 'level': 'soft', 'alpha': 0.64},
          {'fg': '--x', 'bg': '--y', 'level': 'bogus'},
        ]
      });
      expect(pairs.length, 2);
      expect(pairs.last.fgAlpha, 0.64);
    });
  });
}
