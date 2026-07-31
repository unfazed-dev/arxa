// palette — Dart port of scripts/palette.py (HCT seed → W3C DTCG token set).
//
// A single brand seed hex → a full tonal scheme (13 tones, perceptually even via
// CIELAB L*) → a W3C DTCG `color.*` token group with platform `$extensions` (iOS
// Liquid Glass tint / Android M3 scheme role / Web shadcn oklch). Plus an APCA
// contrast check (WCAG 3, not the old 4.5:1 ratio).
//
// Pure stdlib (dart:math only). Deterministic: same seed → same bytes.

import 'dart:math' as math;

// ---------- sRGB <-> linear-RGB (the standard D65 transforms) ----------

double _srgbToLin(num c) {
  final v = c / 255.0;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

int _linToSrgb(double c) {
  if (c < 0) c = 0.0;
  final x = c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
  final clamped = x < 0 ? 0.0 : (x > 1 ? 1.0 : x);
  return (clamped * 255).round();
}

// ---------- hex <-> rgb ----------

List<int> _hexToRgb(String h) {
  var s = h;
  while (s.startsWith('#')) {
    s = s.substring(1); // Python str.lstrip("#"): strip all leading '#'
  }
  if (s.length == 3) {
    s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
  }
  if (s.length != 6) {
    throw FormatException(
        'bad hex color "$h": expected #rgb (3) or #rrggbb (6) digits');
  }
  return [
    int.parse(s.substring(0, 2), radix: 16),
    int.parse(s.substring(2, 4), radix: 16),
    int.parse(s.substring(4, 6), radix: 16),
  ];
}

String _rgbToHex(List<int> rgb) {
  final b = StringBuffer('#');
  for (final c in rgb) {
    final v = c < 0 ? 0 : (c > 255 ? 255 : c);
    b.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// Normalize a hex to canonical #rrggbb lowercase (the form _rgbToHex emits).
String canonHex(String h) => _rgbToHex(_hexToRgb(h));

// ---------- HCT: the HCT color space (Hue/Chroma/Tone) ----------
// HCT is the perceptual space material-color-utilities uses. Full CAM16-UCS HCT
// needs ~40 constants and a 200-line port; this implements the perceptual core
// via CIELAB L* (within ~2 ΔE for the mid-tones a palette uses) — monotonic in
// tone, which is the property the ramp depends on.
const _matrixRgbToXyz = [
  [0.41233895, 0.35762064, 0.18051042],
  [0.2126, 0.7152, 0.0722],
  [0.01932141, 0.11916382, 0.95034478],
];
const _refWhite = [95.047, 100.0, 108.883]; // D65, sRGB viewing conditions

/// XYZ (0..100 scale, D65 white = _refWhite) → CIELAB L*a*b*, reported as
/// (J=L*, C=chroma, h=hue).
(double, double, double) _xyzToLabCam(double x, double y, double z) {
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final fx = f(x / _refWhite[0]);
  final fy = f(y / _refWhite[1]);
  final fz = f(z / _refWhite[2]);
  final L = 116 * fy - 16;
  final a = 500 * (fx - fy);
  final b = 200 * (fy - fz);
  final J = L < 0 ? 0.0 : (L > 100 ? 100.0 : L);
  final C = math.sqrt(a * a + b * b);
  var h = (math.atan2(b, a) * 180 / math.pi) % 360;
  if (h < 0) h += 360; // Dart % can be negative on doubles; force non-negative
  return (J, C, h);
}

(double, double, double) _rgbToHct(List<int> rgb) {
  final r = _srgbToLin(rgb[0]);
  final g = _srgbToLin(rgb[1]);
  final b = _srgbToLin(rgb[2]);
  // linear RGB → XYZ (D65)
  final x = _matrixRgbToXyz[0][0] * r +
      _matrixRgbToXyz[0][1] * g +
      _matrixRgbToXyz[0][2] * b;
  final y = _matrixRgbToXyz[1][0] * r +
      _matrixRgbToXyz[1][1] * g +
      _matrixRgbToXyz[1][2] * b;
  final z = _matrixRgbToXyz[2][0] * r +
      _matrixRgbToXyz[2][1] * g +
      _matrixRgbToXyz[2][2] * b;
  return _xyzToLabCam(x * 100, y * 100, z * 100);
}

/// Perceptual-ish linear blend in sRGB-linear space (gamma-correct, not naive).
List<int> _mix(List<int> seed, List<int> toward, double t) {
  int channel(int i) => _linToSrgb(
      _srgbToLin(seed[i]) * (1 - t) + _srgbToLin(toward[i]) * t);
  return [channel(0), channel(1), channel(2)];
}

/// Render a target HCT tone. Hold the SEED's hue by blending toward black (low
/// tones) or white (high tones) in linear sRGB, binary-searched so the result's
/// measured L* lands near `targetTone`.
List<int> _hctToRgb(double targetTone, List<int> seedRgb) {
  final seedTone = _rgbToHct(seedRgb).$1;
  if ((targetTone - seedTone).abs() < 1.0) return seedRgb;
  final toward = targetTone < seedTone ? const [0, 0, 0] : const [255, 255, 255];
  var lo = 0.0;
  var hi = 1.0;
  var cand = seedRgb;
  for (var i = 0; i < 20; i++) {
    final mid = (lo + hi) / 2;
    cand = _mix(seedRgb, toward, mid);
    final cl = _rgbToHct(cand).$1;
    if ((cl - targetTone).abs() < 0.8) return cand;
    if (targetTone < seedTone) {
      // toward black: more blend = lower L*. If too dark, blend less.
      if (cl < targetTone) {
        hi = mid;
      } else {
        lo = mid;
      }
    } else {
      // toward white: more blend = higher L*. If too light, blend less.
      if (cl > targetTone) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
  }
  return cand;
}

// ---------- the tonal ramp (HCT, perceptually even) ----------

const _tones = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100];

/// Seed hex → {tone: hex} ramp. The seed fixes the hue; tone is the target L*.
/// `ramp[500]` is the seed anchor.
Map<int, String> tonalRamp(String seedHex) {
  final canon = canonHex(seedHex);
  final seedRgb = _hexToRgb(canon);
  final ramp = <int, String>{};
  for (final t in _tones) {
    ramp[t] = _rgbToHex(_hctToRgb(t.toDouble(), seedRgb));
  }
  ramp[500] = canon; // the seed is the 500 anchor
  return ramp;
}

/// The CIELAB L* (HCT tone) of a hex.
double lStar(String hex) => _rgbToHct(_hexToRgb(hex)).$1;

String _oklch(String hex) {
  final t = _rgbToHct(_hexToRgb(hex));
  final l = (t.$1 / 100).toStringAsFixed(3);
  final c = (t.$2 / 100).toStringAsFixed(3);
  final h = t.$3.toStringAsFixed(1);
  return 'oklch($l $c $h)';
}

// ---------- APCA contrast (WCAG 3, perceptual) ----------

/// APCA Lc contrast (-108..+106; negative = dark-on-light). Body ≥ |Lc75|.
double apcaLc(String fgHex, String bgHex) {
  double pcl(String hex) {
    final rgb = _hexToRgb(hex);
    final rs = math.pow(_srgbToLin(rgb[0]), 0.59).toDouble();
    final gs = math.pow(_srgbToLin(rgb[1]), 0.59).toDouble();
    final bs = math.pow(_srgbToLin(rgb[2]), 0.59).toDouble();
    return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs;
  }

  final fg = pcl(fgHex);
  final bg = pcl(bgHex);
  double c;
  if (fg >= bg) {
    c = math.pow(fg - bg, 0.55).toDouble() * 1.14;
  } else {
    c = math.pow(bg - fg, 0.57).toDouble() * 0.96;
  }
  c *= c.abs() < 7.5 ? 1.34 : 1.0;
  if ((fg - bg).abs() > 0.025) {
    return fg >= bg ? c * 100 : -c * 100;
  }
  return 0.0;
}

/// Safe wrapper: returns |Lc|, or 0.0 on bad input (no raise).
double apciLcSafe(String fg, String bg) {
  try {
    return apcaLc(fg, bg).abs();
  } catch (_) {
    return 0.0;
  }
}

// ---------- DTCG emission ----------

/// Seed hex → a W3C DTCG `color.*` token group with platform `$extensions`
/// and curated semantic roles (bg.surface, bg.status-bar-bg, fg.primary,
/// fg.on-accent). Deterministic.
Map<String, dynamic> generate(String seedHex, {String name = 'brand'}) {
  final canon = canonHex(seedHex);
  final ramp = tonalRamp(canon);

  final brand = <String, dynamic>{};
  final sortedKeys = ramp.keys.toList()..sort();
  for (final tone in sortedKeys) {
    final hex = ramp[tone]!;
    brand[tone.toString()] = <String, dynamic>{
      r'$type': 'color',
      r'$value': hex,
      r'$extensions': <String, dynamic>{
        'io.shadcn': <String, dynamic>{'oklch': _oklch(hex)},
      },
    };
  }
  // 500 carries the platform scheme roles (the seed = the primary tint).
  final ext500 = (brand['500'] as Map<String, dynamic>)[r'$extensions']
      as Map<String, dynamic>;
  ext500['org.w3c.dtcg'] = <String, dynamic>{
    'description': '$name primary (the seed)'
  };
  ext500['com.apple.liquid-glass'] = <String, dynamic>{
    'tint': canon,
    'variant': 'regular'
  };
  ext500['com.google.material3'] = <String, dynamic>{'scheme': 'primary'};

  // Semantic roles curated from the ramp (anti-slop: single accent).
  final bg = ramp.containsKey(99) ? ramp[99]! : ramp[95]!;
  final ink = ramp[10]!;
  final onAccent =
      apciLcSafe('#FFFFFF', canon) >= 75 ? '#FFFFFF' : ramp[99]!;
  // status-bar-bg defaults to the darkest tone — a safe value the Designer
  // overrides per-screen. Emitting a default keeps the palette gate-passable.
  final statusBarBg = ramp[10]!;

  return <String, dynamic>{
    r'$schema': 'https://www.designtokens.org/TR/2025.10/format/',
    r'$description': '$name palette generated from seed $canon (HCT tonal scheme).',
    'color': <String, dynamic>{
      name: brand,
      'bg': <String, dynamic>{
        'surface': <String, dynamic>{r'$type': 'color', r'$value': bg},
        'status-bar-bg': <String, dynamic>{
          r'$type': 'color',
          r'$value': statusBarBg,
          r'$description': 'default = darkest tone; override per-screen (a dark screen '
              'needs the bar to match — see references/tokens.md)',
        },
      },
      'fg': <String, dynamic>{
        'primary': <String, dynamic>{r'$type': 'color', r'$value': ink},
        'on-accent': <String, dynamic>{r'$type': 'color', r'$value': onAccent},
      },
    },
  };
}
