// palette_derive — the derivation engine (docs/plans/arxa-palette-plane-universal.md).
//
// One deterministic engine behind every palette birth (Q3/Q10): four source
// adapters — coolors (the slug IS the palette), url (lens token clusters),
// image (lens pixel clusters), hexes (verbatim client lists, intake
// brandColors) — the variable-width law (Q5: 1..7 in, five fixed roles out),
// role-hint pinning (Q6: the client's word beats lightness rank, first-wins
// arbitration recorded), and the slot-fill reseed law (Q7). Pure cores take
// no I/O; url/image ride an injected ClusterSource so tests stay hermetic.
// The math reuses design_palettes.dart (the plane's HSL law) and
// palette.dart (the HCT ramp) — never duplicated.
library;

import 'dart:math' as math;

import 'package:arxa/design_palettes.dart'
    show anchorsFor, hexToRgb, hslToRgb, parseCoolorsSlug, rgbToHex, rgbToHsl,
        PaletteEntry, PaletteManifest;
import 'package:arxa/lens/tokens.dart' show ColorCluster;
import 'package:arxa/palette.dart' show tonalRamp;

/// The five fixed roles, positional (the transplant template families).
const paletteRoles = ['dark', 'accent', 'field', 'beige', 'paper'];

enum DeriveKind { coolors, url, image, hexes }

/// A Q6 role hint: pin [hex] to [role]. Statement order is the client's
/// priority — two claims on one role are first-wins, arbitrated into the
/// evidence, never a refusal (a Map cannot carry the client's duplicates).
typedef RoleHint = ({String role, String hex});

/// One derived palette: the declared swatch (verbatim source for N>=3, the
/// five normalized anchors for N<3 — the schema floor), the five role
/// anchors, a suggested name, and the evidence trail (clusters, pinnings,
/// arbitrations, source) the moodboarder saves verbatim.
class DerivedPalette {
  const DerivedPalette({
    required this.swatch,
    required this.anchors,
    required this.suggestedName,
    required this.evidence,
  });

  final List<String> swatch;
  final Map<String, String> anchors;
  final String suggestedName;
  final Map<String, Object?> evidence;

  Map<String, Object?> toJson() => {
        'swatch': swatch,
        'anchors': anchors,
        'suggestedName': suggestedName,
        'evidence': evidence,
      };
}

/// The I/O seam: url → lens extractTokens clusters, image → lens
/// extractPixelClusters. coolors/hexes never touch it.
abstract class ClusterSource {
  Future<List<ColorCluster>> clusters(DeriveKind kind, String input);
}

// ── small helpers over the plane's math ──────────────────────────────────

double _lightness(String hex) {
  final rgb = hexToRgb(hex);
  return rgbToHsl(rgb[0], rgb[1], rgb[2])[2];
}

double _saturation(String hex) {
  final rgb = hexToRgb(hex);
  return rgbToHsl(rgb[0], rgb[1], rgb[2])[1];
}

/// '#'-prefixed lowercase 6-digit, or FormatException. Intake carries hexes
/// verbatim; normalization lives HERE (Q10's one home).
String normHex(String h) {
  var s = h.trim();
  while (s.startsWith('#')) { s = s.substring(1); }
  s = s.toLowerCase();
  if (!RegExp(r'^[0-9a-f]{6}$').hasMatch(s)) {
    throw FormatException('bad hex color "$h": expected 6 hex digits');
  }
  return '#$s';
}

/// HSL-space lerp, hue by shortest arc, s/l linear — the plane's own color
/// science (Q5: no new math).
String hslMix(String aHex, String bHex, double t) {
  final a = hexToRgb(aHex), b = hexToRgb(bHex);
  final ha = rgbToHsl(a[0], a[1], a[2]);
  final hb = rgbToHsl(b[0], b[1], b[2]);
  var dh = hb[0] - ha[0];
  if (dh > 180) dh -= 360;
  if (dh < -180) dh += 360;
  final h = ha[0] + dh * t;
  final s = ha[1] + (hb[1] - ha[1]) * t;
  final l = ha[2] + (hb[2] - ha[2]) * t;
  final rgb = hslToRgb(h, s, l);
  return rgbToHex(rgb[0], rgb[1], rgb[2]);
}

// ── the variable-width anchor law (Q5 + the 2026-09-10 N=1/N=2 ruling) ──

Map<String, String> _anchorsNoHints(List<String> hexes) {
  final sorted = [...hexes]..sort((a, b) => _lightness(a).compareTo(_lightness(b)));
  switch (sorted.length) {
    case 1:
      // N=1: accent = the seed; the rest ride its HCT ramp (tones 10/50/90/99).
      final ramp = tonalRamp(sorted[0]);
      return {
        'dark': ramp[10]!,
        'accent': sorted[0],
        'field': ramp[50]!,
        'beige': ramp[90]!,
        'paper': ramp[99]!,
      };
    case 2:
      // N=2: dark/paper at the ends, accent = the more saturated (ties
      // break darker). Mid-roles interpolate DARK→PAPER — interpolating
      // accent→paper collapses whenever the accent IS an endpoint
      // (measured: the light hex can win saturation by a hair).
      final accent = _saturation(sorted[0]) >= _saturation(sorted[1])
          ? sorted[0]
          : sorted[1];
      return {
        'dark': sorted[0],
        'accent': accent,
        'field': hslMix(sorted[0], sorted[1], 1 / 3),
        'beige': hslMix(sorted[0], sorted[1], 2 / 3),
        'paper': sorted[1],
      };
    case 3:
      return {
        'dark': sorted[0],
        'accent': sorted[1],
        'field': hslMix(sorted[1], sorted[2], 1 / 3),
        'beige': hslMix(sorted[1], sorted[2], 2 / 3),
        'paper': sorted[2],
      };
    case 4:
      return {
        'dark': sorted[0],
        'accent': sorted[1],
        'field': sorted[2],
        'beige': hslMix(sorted[2], sorted[3], 1 / 2),
        'paper': sorted[3],
      };
    case 5:
      // The verified lightness-rank law, byte-for-byte (design_palettes).
      return anchorsFor(sorted);
    case 6:
      return {
        'dark': sorted[0],
        'accent': sorted[1],
        'field': sorted[2],
        'beige': sorted[3],
        'paper': sorted[5],
      };
    case 7:
      return {
        'dark': sorted[0],
        'accent': sorted[1],
        'field': sorted[3],
        'beige': sorted[4],
        'paper': sorted[6],
      };
    default:
      throw ArgumentError('1..7 hexes, got ${sorted.length}');
  }
}

/// The Q5 law with Q6 pinning: 1..7 hexes → the five role anchors. A role
/// hint PINS its hex to that role (the client's word beats rank); pins on
/// one role are first-wins (statement order), hints naming absent hexes are
/// ignored. The unpinned roles rank-fill from the unpinned pool by the same
/// N-law, so a hint never strands a role.
Map<String, String> anchorsForN(List<String> hexes,
    {List<RoleHint>? roleHints}) {
  final norm = [for (final h in hexes) normHex(h)];
  final unique = <String>[...norm.toSet()];
  if (unique.isEmpty || unique.length > 7) {
    throw ArgumentError('1..7 distinct hexes, got ${unique.length}');
  }
  final anchors = <String, String>{};
  final pinned = <String>{};
  if (roleHints != null) {
    // First-wins in statement order (Q6): the first claim on a role
    // holds it; hints naming absent hexes are ignored — never a refusal.
    for (final e in roleHints) {
      if (!paletteRoles.contains(e.role) || anchors.containsKey(e.role)) {
        continue;
      }
      final h = normHex(e.hex);
      if (!unique.contains(h)) continue;
      anchors[e.role] = h;
      pinned.add(h);
    }
  }
  final want = [for (final r in paletteRoles) if (!anchors.containsKey(r)) r];
  if (want.isEmpty) return anchors;
  final pool = [for (final h in unique) if (!pinned.contains(h)) h];
  final poolLaw = pool.isEmpty
      ? _anchorsNoHints([anchors.values.first])
      : _anchorsNoHints(pool);
  for (final r in want) {
    anchors[r] = poolLaw[r]!;
  }
  return anchors;
}

// ── the url/image salience selection (Q3: deliberately dumb) ─────────────

class _Bucket {
  _Bucket(this.r, this.g, this.b, this.count);
  final int r, g, b, count;
  String get hex => rgbToHex(r, g, b);
}

/// Clusters → exactly five hexes (light→dark, the seeded-swatch convention):
/// merge within RGB euclidean ≤ 12 keeping the heavier count; rank by count
/// desc, take the top 8; sort by lightness; decimate to five. Taste
/// correction is the dial editor's role (Q5).
List<String> selectSalient(List<ColorCluster> clusters) {
  if (clusters.isEmpty) {
    throw ArgumentError('no clusters to select from');
  }
  final sorted = [...clusters]..sort((a, b) => b.count.compareTo(a.count));
  final kept = <_Bucket>[];
  for (final c in sorted) {
    var merged = false;
    for (final k in kept) {
      final d = math.sqrt(math.pow(c.r - k.r, 2) +
          math.pow(c.g - k.g, 2) +
          math.pow(c.b - k.b, 2));
      if (d <= 12) {
        // The heavier cluster represents the pair — counts do not sum
        // (sorted count-desc, the kept bucket already holds the max).
        merged = true;
        break;
      }
    }
    if (!merged) kept.add(_Bucket(c.r, c.g, c.b, c.count));
  }
  kept.sort((a, b) => b.count.compareTo(a.count));
  final top = kept.take(8).toList()
    ..sort((a, b) => _lightness(a.hex).compareTo(_lightness(b.hex)));
  final n = top.length;
  final picked = <String>[
    for (var i = 0; i < 5; i++) top[((i * (n - 1)) / 4).floor()].hex
  ];
  return picked.reversed.toList();
}

// ── the orchestrator ─────────────────────────────────────────────────────

/// Derive one palette from one source. roleHints ride the brandColors path
/// (Q6). The declared swatch is the verbatim source for N>=3; for N<3 it is
/// the five normalized anchors (the manifest's 3-floor).
Future<DerivedPalette> derive(DeriveKind kind, String input,
    {List<RoleHint>? roleHints, ClusterSource? clusters}) async {
  List<String> source;
  final notes = <String>[];
  Map<String, Object?> clusterEvidence = const {};
  switch (kind) {
    case DeriveKind.coolors:
      final parsed = parseCoolorsSlug(input);
      if (parsed == null) {
        throw ArgumentError('not a Coolors link — expected coolors.co/<5 hexes>');
      }
      source = [for (final h in parsed) '#$h'];
    case DeriveKind.hexes:
      source = [
        for (final h in input.split(RegExp(r'[,\s]+')))
          if (h.trim().isNotEmpty) normHex(h)
      ];
      if (source.isEmpty || source.length > 7) {
        throw ArgumentError('1..7 hexes, got ${source.length}');
      }
    case DeriveKind.url:
    case DeriveKind.image:
      final src = clusters;
      if (src == null) {
        throw ArgumentError('$kind derivation needs a ClusterSource');
      }
      final cls = await src.clusters(kind, input);
      source = selectSalient(cls);
      clusterEvidence = {
        'clusters': [for (final c in cls) c.toJson()],
        'selected': source,
      };
  }
  final anchors = anchorsForN(source, roleHints: roleHints);
  if (roleHints != null) {
    final seenRoles = <String>{};
    for (final e in roleHints) {
      if (!paletteRoles.contains(e.role)) continue;
      if (seenRoles.contains(e.role)) {
        notes.add('role ${e.role}: first-wins kept ${anchors[e.role]}, '
            'ignored ${e.hex} (arbitration, Q6)');
        continue;
      }
      seenRoles.add(e.role);
      if (anchors[e.role] == normHex(e.hex)) {
        notes.add('pinned ${e.role} = ${normHex(e.hex)} (client hint, Q6)');
      }
    }
  }
  final declared = source.length < 3
      ? [for (final r in paletteRoles) anchors[r]!]
      : source;
  if (source.length < 3) {
    notes.add('swatch normalized to the five anchors (N<3, the 3-floor law)');
  }
  return DerivedPalette(
    swatch: declared,
    anchors: anchors,
    suggestedName: 'Palette ${anchors['dark']!.substring(1).toUpperCase()}',
    evidence: {
      'source': '$kind:$input',
      ...clusterEvidence,
      if (notes.isNotEmpty) 'notes': notes,
    },
  );
}

// ── the slot-fill reseed law (Q7) ────────────────────────────────────────

class ReseedPlan {
  const ReseedPlan({
    required this.entries,
    required this.defaultId,
    required this.notes,
  });

  /// Exactly five manifest entries, default first.
  final List<PaletteEntry> entries;
  final String defaultId;

  /// Human-readable slot provenance (what filled each slot and why).
  final List<String> notes;
}

/// The seeded five for a design: brand → suitors (winner first, remix
/// applied) → references (score-ranked) → fallback (its own default first);
/// swatch-set dedup, first wins. The default entry carries NO sheet (it is
/// the base corpus, per the manifest law); the rest carry generated sheets.
ReseedPlan planReseed({
  required PaletteManifest fallback,
  List<DerivedPalette> brand = const [],
  List<DerivedPalette> suitors = const [],
  List<DerivedPalette> references = const [],
}) {
  String keyOf(List<String> swatch) =>
      ([...swatch.map((s) => s.toLowerCase())]..sort()).join('-');

  final seen = <String>{};
  final ids = <String>{};
  // Fallback ids are RESERVED from the first mint (Q7: fallback entries
  // keep their ids) — fresh mints disambiguate around them with -n.
  final reservedIds = {for (final e in fallback.palettes) e.id};
  final entries = <PaletteEntry>[];
  final notes = <String>[];

  void takeDerived(DerivedPalette d, String why) {
    if (entries.length == 5) return;
    final k = keyOf(d.swatch);
    if (seen.contains(k)) return;
    seen.add(k);
    var id = 'c-${d.anchors['dark']!.substring(1)}';
    var n = 2;
    while (ids.contains(id) || reservedIds.contains(id)) {
      id = 'c-${d.anchors['dark']!.substring(1)}-$n';
      n++;
    }
    ids.add(id);
    entries.add(PaletteEntry(
      id: id,
      name: d.suggestedName,
      swatch: d.swatch,
      themeColor: d.anchors['accent']!,
      seeded: true,
      source: d.evidence['source']?.toString(),
    ));
    notes.add('slot ${entries.length}: ${d.suggestedName} ($why)');
  }

  void takeFallback(PaletteEntry e, String why) {
    if (entries.length == 5) return;
    final k = keyOf(e.swatch);
    if (seen.contains(k) || ids.contains(e.id)) return;
    seen.add(k);
    ids.add(e.id);
    entries.add(e);
    notes.add('slot ${entries.length}: ${e.name} ($why)');
  }

  for (final b in brand) { takeDerived(b, 'client brandColors (Q6 priority)'); }
  for (var i = 0; i < suitors.length; i++) {
    takeDerived(suitors[i],
        i == 0 ? 'winning suitor, remix applied' : 'declined suitor ${String.fromCharCode(65 + i)}');
  }
  for (final r in references) { takeDerived(r, 'selected reference by score'); }
  final fb = [
    fallback.palettes.firstWhere((e) => e.id == fallback.defaultId),
    ...fallback.palettes.where((e) => e.id != fallback.defaultId),
  ];
  for (final e in fb) { takeFallback(e, 'fallback five backfill'); }

  // The sheet law: the default is the base corpus (no sheet); the rest get
  // a generated sheet path when they do not already carry one (fallback
  // entries keep theirs).
  final fixed = [
    for (var i = 0; i < entries.length; i++)
      i == 0 || entries[i].sheet != null
          ? entries[i]
          : PaletteEntry(
              id: entries[i].id,
              name: entries[i].name,
              swatch: entries[i].swatch,
              themeColor: entries[i].themeColor,
              seeded: entries[i].seeded,
              source: entries[i].source,
              sheet: '/assets/styles/palettes/palette-${entries[i].id}.css',
            ),
  ];
  return ReseedPlan(entries: fixed, defaultId: fixed.first.id, notes: notes);
}
