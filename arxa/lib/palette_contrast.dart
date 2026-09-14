/// The contrast engine (grilled + locked 2026-09-11): every palette the
/// plane ships renders its contracted pairs at WCAG 2.2 AA by construction
/// (4.5:1 body, 3:1 large/non-text), with APCA as an advisory readout —
/// never a gate. One home of the contrast math, mirroring the transplant
/// law (design_palettes.dart owns the transplant; this owns ratios,
/// OKLCH, and the solve). Self-contained by design: no imports from the
/// palette lib, so the two never cycle.
///
/// The solve order is the locked brand-fidelity law: the pair's
/// FOREGROUND moves first — in OKLCH lightness only, hue and chroma
/// preserved, the smallest step that clears the target — and the
/// background moves only when no lightness in [0,1] can. Every slot the
/// solver touches is a DERIVED output (transplant result); the pasted
/// anchors never enter the slot map, so they are inviolate by
/// construction. Decorative ghosts never ride the contract: the template
/// simply declares no pair for them.
library;

import 'dart:math' as math;

// ── hex ↔ rgb (tolerant: '#rrggbb' or bare) ─────────────────────────────

List<int> hexToRgb(String hex) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) {
    h = h.split('').map((c) => c + c).join();
  }
  if (h.length != 6) throw ArgumentError('not a hex color: $hex');
  return [
    int.parse(h.substring(0, 2), radix: 16),
    int.parse(h.substring(2, 4), radix: 16),
    int.parse(h.substring(4, 6), radix: 16),
  ];
}

String _hex(List<int> rgb) =>
    '#${rgb.map((v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';

/// Alpha-composite [fg] over [bg] at [alpha] — soft tokens (rgba forms)
/// are measured as what the visitor actually sees.
List<int> composite(List<int> fg, List<int> bg, double alpha) => [
      for (var i = 0; i < 3; i++) (fg[i] * alpha + bg[i] * (1 - alpha)).round(),
    ];

// ── WCAG 2.2 relative luminance + contrast ratio ────────────────────────

double _linearize(int channel) {
  final c = channel / 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double relativeLuminance(List<int> rgb) =>
    0.2126 * _linearize(rgb[0]) +
    0.7152 * _linearize(rgb[1]) +
    0.0722 * _linearize(rgb[2]);

/// WCAG 2.x contrast ratio, 1..21. Order-agnostic.
double contrastRatio(String a, String b) {
  final la = relativeLuminance(hexToRgb(a));
  final lb = relativeLuminance(hexToRgb(b));
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

// ── OKLCH (Björn Ottosson's OKLab, public matrices) ─────────────────────

class Oklch {
  const Oklch(this.l, this.c, this.h);
  final double l, c, h; // h in radians
}

double _srgbToF(int channel) {
  final c = channel / 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

int _fToSrgb(double v) {
  final c = v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;
  return (c * 255.0).round().clamp(0, 255);
}

Oklch toOklch(List<int> rgb) {
  final r = _srgbToF(rgb[0]), g = _srgbToF(rgb[1]), b = _srgbToF(rgb[2]);
  final l = math.pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1 / 3).toDouble();
  final m = math.pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1 / 3).toDouble();
  final s = math.pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1 / 3).toDouble();
  final L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  final a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  final bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  return Oklch(L, math.sqrt(a * a + bb * bb), math.atan2(bb, a));
}

/// Back to sRGB, gamut-mapped by chroma reduction (hue + lightness kept;
/// chroma decays until the color fits — the standard OKLCH practice).
List<int> fromOklch(Oklch o) {
  var c = o.c;
  for (var i = 0; i < 24; i++) {
    final l_ = o.l + 0.3963377774 * (c * math.cos(o.h)) + 0.2158037573 * (c * math.sin(o.h));
    final m_ = o.l - 0.1055613458 * (c * math.cos(o.h)) - 0.0638541728 * (c * math.sin(o.h));
    final s_ = o.l - 0.0894841775 * (c * math.cos(o.h)) - 1.2914855480 * (c * math.sin(o.h));
    final l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
    final r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    final g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    final b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
    if (r >= -0.001 && r <= 1.001 && g >= -0.001 && g <= 1.001 && b >= -0.001 && b <= 1.001) {
      return [_fToSrgb(r), _fToSrgb(g), _fToSrgb(b)];
    }
    c *= 0.92;
  }
  // Degenerate: neutral gray at the requested lightness.
  final v = _fToSrgb(o.l.clamp(0, 1).toDouble());
  return [v, v, v];
}

// ── APCA (advisory only — the WCAG 3 candidate, 0.1.9 constants) ───────

double _apcaY(List<int> rgb) {
  const trc = 2.4;
  double ch(int v) => math.pow(v / 255.0, trc).toDouble();
  return 0.2126729 * ch(rgb[0]) + 0.7151522 * ch(rgb[1]) + 0.0721750 * ch(rgb[2]);
}

/// Lightness contrast (Lc) for text-on-background. Positive = dark text
/// on light bg, negative = light text on dark bg; magnitude is the
/// strength. Advisory display only — never gates anything.
double apcaLc(String textHex, String bgHex) {
  const normBG = 0.56, normTXT = 0.57, revTXT = 0.62, revBG = 0.65;
  const blkThrs = 0.022, blkClmp = 1.414, scale = 1.14, offset = 0.027, loClip = 0.1;
  double softClamp(double y) => y >= blkThrs ? y : y + math.pow(blkThrs - y, blkClmp);
  var ytxt = softClamp(_apcaY(hexToRgb(textHex)));
  var ybg = softClamp(_apcaY(hexToRgb(bgHex)));
  if ((ytxt - ybg).abs() < 0.0005) return 0.0;
  final darkText = ytxt < ybg;
  double out;
  if (darkText) {
    ytxt = math.pow(ytxt, normTXT).toDouble();
    ybg = math.pow(ybg, normBG).toDouble();
    out = (ybg - ytxt) * scale;
  } else {
    ytxt = math.pow(ytxt, revTXT).toDouble();
    ybg = math.pow(ybg, revBG).toDouble();
    out = (ybg - ytxt) * scale;
  }
  if (out.abs() < loClip) return 0.0;
  // The published method: the low-contrast offset rides SAPC, and Lc is
  // the percentage (×100) — sign carries the polarity.
  return (out + (out > 0 ? -offset : offset)) * 100.0;
}

// ── the pair contract ───────────────────────────────────────────────────

/// One guaranteed pair. [fg]/[bg] name either a TOKEN ('--ink') or a
/// RULE KEY ('r14s0' implicit / a template-authored alias) declared in
/// the template. [level] picks the target: body 4.5:1, large/soft/
/// nontext 3:1 (WCAG 2.2 SC 1.4.3/1.4.11). [fgAlpha] composites a soft
/// foreground over its background before measuring — secondary text is
/// judged as what the visitor actually sees.
class ContrastPair {
  const ContrastPair({required this.fg, required this.bg, required this.level, this.fgAlpha});
  final String fg, bg, level;
  final double? fgAlpha;

  double get target => level == 'body' ? 4.5 : 3.0;

  Map<String, Object?> toJson() =>
      {'fg': fg, 'bg': bg, 'level': level, if (fgAlpha != null) 'alpha': fgAlpha};

  static ContrastPair? fromJson(Object? json) {
    if (json is! Map) return null;
    final fg = json['fg'], bg = json['bg'], level = json['level'];
    if (fg is! String || bg is! String || level is! String) return null;
    if (!const ['body', 'large', 'soft', 'nontext'].contains(level)) return null;
    final alpha = json['alpha'];
    return ContrastPair(
        fg: fg, bg: bg, level: level,
        fgAlpha: alpha is num ? alpha.toDouble() : null);
  }
}

/// The contract off a parsed _template.json ('pairs' array). A template
/// without pairs answers empty — the gate then notes the missing
/// contract instead of inventing one.
List<ContrastPair> contractFromTemplate(Object? templateJson) {
  if (templateJson is! Map) return const [];
  final raw = templateJson['pairs'];
  if (raw is! List) return const [];
  return [
    for (final p in raw)
      if (ContrastPair.fromJson(p) != null) ContrastPair.fromJson(p)!
  ];
}

// ── the solver ──────────────────────────────────────────────────────────

/// One recorded adjustment: what moved, why, from what to what.
class SolveMove {
  const SolveMove({
    required this.slot,
    required this.pairLabel,
    required this.was,
    required this.now,
    required this.before,
    required this.after,
    required this.movedSide,
  });
  final String slot, pairLabel, was, now, movedSide;
  final double before, after;

  @override
  String toString() =>
      'solve($movedSide $slot — $pairLabel, $was -> $now)';
}

/// Solve [slotHexes] (identity -> derived hex) until every [pair] clears
/// its target. The Radix law, mechanically: (1) a foreground slot carries
/// its WHOLE pair set — one lightness step must satisfy every pair at
/// once, so fix-and-break oscillation is impossible; (2) when no
/// lightness can (a mid-dark surface no dark text can read on), the slot
/// INVERTS POLARITY via [alt] — light text on the dark surface — because
/// surfaces are the palette's character and bleaching them is the one
/// move worse than flipping an ink; (3) only a genuinely stuck pair
/// moves its surface, least shift that satisfies everything the surface
/// carries. ~2% margin so rounding never lands on the line. Returns the
/// solved map, the per-slot move log, and any pairs that stayed below
/// target (the caller surfaces them as gate findings).
(Map<String, String>, List<SolveMove>, List<String>) solveContrast({
  required Map<String, String> slotHexes,
  required List<ContrastPair> pairs,
  String? Function(String slot)? alt,
}) {
  final hexes = Map<String, String>.of(slotHexes);
  final moves = <SolveMove>[];

  // The effective foreground actually measured: a soft (alpha) slot is
  // composited over its background — the visitor-visibility law.
  String effective(String fg, String bg, double? alpha) =>
      alpha == null ? fg : _hex(composite(hexToRgb(fg), hexToRgb(bg), alpha));

  bool pairPasses(ContrastPair pair, String fg, String bg) =>
      contrastRatio(effective(fg, bg, pair.fgAlpha), bg) >= pair.target;

  String worstLabel(List<ContrastPair> myPairs, String was, String now) {
    ContrastPair? worst;
    var worstRatio = 99.0;
    for (final pr in myPairs) {
      final r = contrastRatio(
          effective(was, hexes[pr.bg]!, pr.fgAlpha), hexes[pr.bg]!);
      if (r < worstRatio) {
        worstRatio = r;
        worst = pr;
      }
    }
    return worst == null
        ? ''
        : 'worst ${worst.fg} on ${worst.bg} (${worst.level}) '
            '${worstRatio.toStringAsFixed(2)}:1 -> '
            '${contrastRatio(effective(now, hexes[worst.bg]!, worst.fgAlpha), hexes[worst.bg]!).toStringAsFixed(2)}:1';
  }

  // Group the pairs each side must answer for TOGETHER.
  final fgPairs = <String, List<ContrastPair>>{};
  final bgPairs = <String, List<ContrastPair>>{};
  for (final pair in pairs) {
    if (slotHexes.containsKey(pair.fg) && slotHexes.containsKey(pair.bg)) {
      fgPairs.putIfAbsent(pair.fg, () => []).add(pair);
      bgPairs.putIfAbsent(pair.bg, () => []).add(pair);
    }
  }

  // The nearest passing lightness for [slot] against its whole pair set,
  // or null when no L in [0,1] satisfies every pair.
  String? nearestPassing(String slot, List<ContrastPair> myPairs) {
    final ok = toOklch(hexToRgb(hexes[slot]!));
    int? best;
    for (var i = 0; i <= 100; i++) {
      final cand = _hex(fromOklch(Oklch(i / 100.0, ok.c, ok.h)));
      if (myPairs.every((pr) => pairPasses(pr, cand, hexes[pr.bg]!))) {
        if (best == null ||
            (i / 100.0 - ok.l).abs() < (best / 100.0 - ok.l).abs()) {
          best = i;
        }
      }
    }
    return best == null ? null : _hex(fromOklch(Oklch(best / 100.0, ok.c, ok.h)));
  }

  // Two rounds: surfaces that move in round one let the foregrounds
  // re-answer in round two (the orchid knot: paper-on-accent pins the
  // accent, the hero text re-solves against the moved surface).
  for (var round = 0; round < 2; round++) {
  // PHASE 1 — lightness, all pairs at once.
  for (final entry in fgPairs.entries) {
    final base = hexes[entry.key]!;
    final myPairs = entry.value;
    if (myPairs.every((pr) => pairPasses(pr, base, hexes[pr.bg]!))) continue;
    final stepped = nearestPassing(entry.key, myPairs);
    if (stepped != null && stepped != base) {
      hexes[entry.key] = stepped;
      moves.add(SolveMove(
          slot: entry.key,
          pairLabel: '${myPairs.length} pair(s), '
              '${worstLabel(myPairs, base, stepped)}',
          was: base,
          now: stepped,
          before: 0,
          after: 0,
          movedSide: 'fg'));
    }
  }

  // PHASE 2 — polarity inversion: light text on the mid-dark surface.
  // Surfaces keep their character; the ink flips family.
  for (final entry in fgPairs.entries) {
    final base = hexes[entry.key]!;
    final myPairs = entry.value;
    if (myPairs.every((pr) => pairPasses(pr, base, hexes[pr.bg]!))) continue;
    final flipped = alt?.call(entry.key);
    if (flipped != null &&
        myPairs.every((pr) => pairPasses(pr, flipped, hexes[pr.bg]!))) {
      hexes[entry.key] = flipped;
      moves.add(SolveMove(
          slot: entry.key,
          pairLabel: 'polarity inverted — ${myPairs.length} pair(s), '
              '${worstLabel(myPairs, base, flipped)}',
          was: base,
          now: flipped,
          before: 0,
          after: 0,
          movedSide: 'flip'));
    }
  }

  // PHASE 3 — the genuinely stuck: the surface moves, least shift that
  // satisfies every pair it carries.
  for (final entry in bgPairs.entries) {
    final baseBg = hexes[entry.key]!;
    final myPairs = entry.value;
    if (myPairs.every((pr) => pairPasses(pr, hexes[pr.fg]!, baseBg))) continue;
    final ok = toOklch(hexToRgb(baseBg));
    int? best;
    for (var i = 0; i <= 100; i++) {
      final cand = _hex(fromOklch(Oklch(i / 100.0, ok.c, ok.h)));
      if (myPairs.every((pr) => pairPasses(pr, hexes[pr.fg]!, cand))) {
        if (best == null ||
            (i / 100.0 - ok.l).abs() < (best / 100.0 - ok.l).abs()) {
          best = i;
        }
      }
    }
    if (best != null) {
      final stepped = _hex(fromOklch(Oklch(best / 100.0, ok.c, ok.h)));
      if (stepped != baseBg) {
        hexes[entry.key] = stepped;
        moves.add(SolveMove(
            slot: entry.key,
            pairLabel: 'surface moved — ${myPairs.length} pair(s)',
            was: baseBg,
            now: stepped,
            before: 0,
            after: 0,
            movedSide: 'bg'));
      }
    }
  }
  } // round

  // What still fails after all three phases — the honest residue.
  final unsolved = <String>[];
  for (final pair in pairs) {
    final fg = hexes[pair.fg], bg = hexes[pair.bg];
    if (fg == null || bg == null) continue;
    if (!pairPasses(pair, fg, bg)) {
      final label = '${pair.fg} on ${pair.bg} (${pair.level})';
      if (!unsolved.contains(label)) unsolved.add(label);
    }
  }
  return (hexes, moves, unsolved);
}
