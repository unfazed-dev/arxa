// Port of palette.py's 10 self-test assertion groups.

import 'dart:convert';

import 'package:arxa/palette.dart';
import 'package:test/test.dart';

void main() {
  const seed = '#C04A1A'; // the rust seed palette.py self-tests against
  const tones = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100];

  // 1. round-trip: the 500 anchor IS the seed
  test('tonal ramp 500 anchor = seed (round-trip)', () {
    final ramp = tonalRamp(seed);
    expect(ramp[500], '#c04a1a');
  });

  // 2. monotonicity: tone 0 darkest, tone 100 lightest, each step lighter
  test('tonal ramp is monotonic (tone 0 darkest → tone 100 lightest)', () {
    final ramp = tonalRamp(seed);
    final ls = [for (final t in tones) lStar(ramp[t]!)];
    expect(lStar(ramp[0]!), lessThan(lStar(ramp[100]!)),
        reason: 'tone 0 should be darker than tone 100');
    for (var i = 0; i < ls.length - 1; i++) {
      expect(ls[i], lessThanOrEqualTo(ls[i + 1] + 0.5),
          reason: 'non-monotonic at tone ${tones[i]}→${tones[i + 1]}');
    }
  });

  // 3. contrast: on-accent vs seed clears the body-text floor (|Lc| ≥ 75)
  test('on-accent contrast ≥ Lc75', () {
    final doc = generate(seed);
    final onAccent =
        (doc['color'] as Map)['fg'] as Map;
    final onAccentValue = (onAccent['on-accent'] as Map)[r'$value'] as String;
    final lc = apcaLc(onAccentValue, '#c04a1a').abs();
    expect(lc, greaterThanOrEqualTo(75),
        reason: 'on-accent |Lc${lc.toStringAsFixed(0)}| < Lc75');
  });

  // 4. DTCG shape: the 3 platform $extensions are on the seed's 500
  test('seed 500 carries all 3 platform \$extensions', () {
    final doc = generate(seed);
    final brand = (doc['color'] as Map)['brand'] as Map;
    final ext = (brand['500'] as Map)[r'$extensions'] as Map;
    expect(ext, contains('com.apple.liquid-glass'));
    expect(ext, contains('com.google.material3'));
    expect(ext, contains('io.shadcn'));
  });

  // 5. determinism: same seed → same bytes
  test('deterministic (same seed → same bytes)', () {
    expect(jsonEncode(generate(seed)), jsonEncode(generate(seed)));
  });

  // 6. extreme seeds — pure black (degenerate hue), pure white, neon green
  //    (convergence stress), grayscale (chroma ≈ 0). None may crash.
  for (final extreme in [
    ['#000000', 'black-degenerate-hue'],
    ['#FFFFFF', 'white'],
    ['#00FF00', 'neon-convergence'],
    ['#808080', 'grayscale-low-chroma'],
  ]) {
    final s = extreme[0];
    final tag = extreme[1];
    test('extreme seed $s ($tag) — monotonic, 500 round-trips, deterministic', () {
      final ramp = tonalRamp(s);
      expect(ramp[500], canonHex(s), reason: '$tag: 500 anchor ≠ canon seed');
      final ls = [for (final t in tones) lStar(ramp[t]!)];
      for (var i = 0; i < ls.length - 1; i++) {
        expect(ls[i], lessThanOrEqualTo(ls[i + 1] + 0.6),
            reason: '$tag: non-monotonic at ${tones[i]}→${tones[i + 1]}');
      }
      expect(jsonEncode(generate(s)), jsonEncode(generate(s)),
          reason: '$tag: not deterministic');
    });
  }

  // 7. canonHex normalization (3-digit expand, case fold, #-add)
  test('canonHex normalization (3-digit expand, case fold, #-add)', () {
    expect(canonHex('#F00'), '#ff0000', reason: '3-digit should expand to 6');
    expect(canonHex('#FF0000'), '#ff0000', reason: 'uppercase should lowercase');
    expect(canonHex('ff0000'), '#ff0000', reason: 'missing # should be added');
    expect(canonHex('#0E7c66'), '#0e7c66', reason: 'mixed case');
  });

  // 8. negatives — malformed seeds must raise (not silently produce garbage).
  test('malformed seeds raise (not silent garbage)', () {
    for (final bad in ['#GGG', 'red', '', '#12345']) {
      expect(() => generate(bad), throwsA(isA<FormatException>()),
          reason: "generate('$bad') should raise");
    }
    // null → runtime type error (non-nullable String param via dynamic dispatch).
    dynamic badNull;
    expect(() => generate(badNull), throwsA(isA<Object>()));
  });

  // 9. apca boundary — fg==bg is the degenerate equal-contrast case (must be
  //    0.0, not a division error); and the sign convention (dark-on-light < 0).
  test('apca boundary (fg==bg→0, sign convention, safe-wrapper no-raise)', () {
    expect(apcaLc('#000000', '#000000'), 0.0, reason: 'fg==bg must be 0.0');
    expect(apcaLc('#FFFFFF', '#000000'), greaterThan(0),
        reason: 'white-on-black should be positive');
    expect(apcaLc('#000000', '#FFFFFF'), lessThan(0),
        reason: 'black-on-white should be negative (sign convention)');
    expect(apciLcSafe('#000000', '#000000'), 0.0,
        reason: 'safe wrapper: fg==bg → 0.0');
    expect(apciLcSafe('not-a-color', '#000000'), 0.0,
        reason: 'safe wrapper: invalid input → 0.0 (no raise)');
  });

  // 10. _hctToRgb is bounded (20-iter binary search) — returns a value close to
  //     the target tone for a well-behaved seed.
  test('_hctToRgb bounded + converges within tolerance (tones 10/50/90)', () {
    final ramp = tonalRamp(seed);
    for (final target in [10, 50, 90]) {
      final got = lStar(ramp[target]!);
      expect((got - target).abs(), lessThan(6.0),
          reason:
              '_hctToRgb(tone=$target) → L*${got.toStringAsFixed(1)}, drift > 6');
    }
  });
}
