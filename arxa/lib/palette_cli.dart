// palette — the palette engine's CLI (docs/plans/arxa-palette-plane-universal.md, Q10).
//
//   arxa palette derive --from <input> [--kind coolors|url|image|hexes] [--out <path>]
//   arxa palette reseed --design <design-dir> [--intake <intake-dir>] [--apply]
//
// derive prints the DerivedPalette JSON (swatch/anchors/suggestedName/
// evidence — the shape the moodboarder saves verbatim as palette evidence);
// kind is inferred when omitted (a Coolors slug -> coolors, http(s) -> url,
// an existing file -> image, else a raw hex list). url/image ride the lens
// (extractTokens / extractPixelClusters) through the engine's ClusterSource
// seam. reseed composes the Q7 slot-fill law from the intake chain
// (brandcolors.json -> moodboard.json's suitors -> selected references ->
// fallback five) and prints the plan; --apply writes palettes.json (run
// "arxa design palette-index" afterwards to regenerate sheets + tokens).
import 'dart:convert';
import 'dart:io';

import 'package:arxa/design_palettes.dart' show PaletteManifest, parseCoolorsSlug;
import 'package:arxa/lens/pixels.dart' show extractPixelClusters;
import 'package:arxa/lens/tokens.dart' show ColorCluster, extractTokens;
import 'package:arxa/palette_derive.dart';

class _LensClusters implements ClusterSource {
  @override
  Future<List<ColorCluster>> clusters(DeriveKind kind, String input) async {
    if (kind == DeriveKind.url) {
      final r = await extractTokens(input, 1280, 900);
      final errs = (r['consoleErrors'] as List? ?? const []);
      if (errs.isNotEmpty) {
        throw StateError('lens tokens extraction failed: ${errs.first}');
      }
      return [
        for (final c in (r['palette'] as List? ?? const []))
          _clusterFromJson(c as Map),
      ];
    }
    return extractPixelClusters(input);
  }
}

ColorCluster _clusterFromJson(Map c) {
  final hex = (c['hex'] ?? '#000000').toString().replaceAll('#', '');
  return ColorCluster(
    int.parse(hex.substring(0, 2), radix: 16),
    int.parse(hex.substring(2, 4), radix: 16),
    int.parse(hex.substring(4, 6), radix: 16),
    (c['count'] as num? ?? 0).toInt(),
  );
}

DeriveKind _inferKind(String input) {
  if (parseCoolorsSlug(input) != null) return DeriveKind.coolors;
  if (input.startsWith('http://') || input.startsWith('https://')) {
    return DeriveKind.url;
  }
  if (File(input).existsSync()) return DeriveKind.image;
  return DeriveKind.hexes;
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

Future<int> _derive(List<String> args) async {
  final from = _flag(args, '--from');
  if (from == null) {
    stderr.writeln('arxa palette derive: needs --from <coolors-url|url|image|hexes>');
    return 2;
  }
  final kindName = _flag(args, '--kind');
  final kind = kindName != null
      ? DeriveKind.values.where((k) => k.name == kindName).firstOrNull
      : _inferKind(from);
  if (kind == null) {
    stderr.writeln('arxa palette derive: unknown --kind "$kindName" (coolors|url|image|hexes)');
    return 2;
  }
  try {
    final result = await derive(kind, from, clusters: _LensClusters());
    final json = const JsonEncoder.withIndent('  ').convert(result.toJson());
    final out = _flag(args, '--out');
    if (out != null) {
      File(out).parent.createSync(recursive: true);
      File(out).writeAsStringSync('$json\n');
      stdout.writeln('palette derive: wrote $out');
    } else {
      stdout.writeln(json);
    }
    return 0;
  } catch (e) {
    stderr.writeln('arxa palette derive: $e');
    return 1;
  }
}

// ── reseed: the Q7 slot-fill law over the intake chain ──────────────────

Map<String, dynamic>? _readJson(String path) {
  final f = File(path);
  if (!f.existsSync()) return null;
  try {
    final v = jsonDecode(f.readAsStringSync());
    return v is Map ? v.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

/// The winner's palette, remix-applied: a remix clause on the palette
/// attribute swaps the winner's palette object for the named sibling's.
Map<String, dynamic> _winnerFirst(Map<String, dynamic> rec,
    List<Map<String, dynamic>> suitors) {
  final choice = rec['suitorChoice'];
  if (choice is! Map) return suitors.first;
  final primary = choice['primary']?.toString();
  var winner = suitors.where((s) => s['id'] == primary).firstOrNull ?? suitors.first;
  for (final r in (choice['remix'] as List? ?? const []).whereType<Map>()) {
    if (r['attribute'] == 'palette') {
      final from =
          suitors.where((s) => s['id'] == r['from']?.toString()).firstOrNull;
      if (from != null) winner = from;
    }
  }
  return winner;
}

DerivedPalette? _suitorDerived(Map<String, dynamic> suitor) {
  final tokens = suitor['tokens'];
  if (tokens is! Map) return null;
  final palette = tokens['palette'];
  if (palette is! Map) return null;
  final swatch = palette['swatch'];
  final anchors = palette['anchors'];
  if (swatch is! List || anchors is! Map) return null;
  return DerivedPalette(
    swatch: [for (final h in swatch) h.toString()],
    anchors: {
      for (final e in anchors.entries) e.key.toString(): e.value.toString()
    },
    suggestedName:
        (palette['name'] ?? suitor['name'] ?? 'Suitor palette').toString(),
    evidence: {'source': 'moodboard:suitor-${suitor['id']}'},
  );
}

final _hexInText = RegExp(r'#?[0-9a-fA-F]{6}');

/// A selected reference's recorded palette (a hex string in tokens.palette)
/// becomes a candidate; prose-only legacy records contribute nothing.
DerivedPalette? _referenceDerived(Map<String, dynamic> ref) {
  final tokens = ref['tokens'];
  if (tokens is! Map) return null;
  final palette = tokens['palette'];
  if (palette is! String || palette.isEmpty) return null;
  final hexes = [for (final m in _hexInText.allMatches(palette)) m.group(0)!];
  if (hexes.isEmpty) return null;
  final capped = hexes.length > 7 ? hexes.sublist(0, 7) : hexes;
  final anchors = anchorsForN(capped);
  return DerivedPalette(
    swatch: capped.length < 3
        ? [for (final r in paletteRoles) anchors[r]!]
        : [for (final h in capped) normHex(h)],
    anchors: anchors,
    suggestedName: (ref['name'] ?? 'Reference palette').toString(),
    evidence: {'source': 'moodboard:reference-${ref['name']}'},
  );
}

Future<int> _reseed(List<String> args) async {
  final design = _flag(args, '--design');
  if (design == null) {
    stderr.writeln('arxa palette reseed: needs --design <design-dir> '
        '[--intake <intake-dir>] [--apply]');
    return 2;
  }
  final intake = _flag(args, '--intake') ??
      (Directory('$design/../intake').existsSync() ? '$design/../intake' : null);
  final fallback = PaletteManifest.load(design);
  if (fallback == null) {
    stderr.writeln('arxa palette reseed: $design declares no palette plane '
        '(palettes.json missing or malformed)');
    return 1;
  }

  // brand first (Q6 priority) — intake/brandcolors.json, a bare array.
  final brand = <DerivedPalette>[];
  if (intake != null) {
    final brandFile = File('$intake/brandcolors.json');
    if (brandFile.existsSync()) {
      try {
        final list = jsonDecode(brandFile.readAsStringSync());
        if (list is List && list.isNotEmpty) {
          final entries = list.whereType<Map>().toList();
          final hexes = [for (final e in entries) e['hex'].toString()];
          final hints = [
            for (final e in entries)
              if (e['role'] is String)
                (role: e['role'].toString(), hex: e['hex'].toString()),
          ];
          brand.add(await derive(DeriveKind.hexes, hexes.join(','),
              roleHints: hints.isEmpty ? null : hints));
        }
      } catch (e) {
        stderr.writeln('arxa palette reseed: brandcolors.json unreadable ($e)');
        return 1;
      }
    }
  }

  // suitors: winner first (remix applied), then the declined in id order.
  final suitorPalettes = <DerivedPalette>[];
  // references: selected, palette-carrying, score-ranked.
  final refPalettes = <DerivedPalette>[];
  final rec = intake == null ? null : _readJson('$intake/moodboard.json');
  if (rec != null) {
    final suitors = [
      for (final s in (rec['suitors'] as List? ?? const []).whereType<Map>())
        s.cast<String, dynamic>()
    ];
    if (suitors.isNotEmpty) {
      final winner = _winnerFirst(rec, suitors);
      final declined = suitors.where((s) => s != winner).toList()
        ..sort((a, b) => (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString()));
      for (final s in [winner, ...declined]) {
        final d = _suitorDerived(s);
        if (d != null) suitorPalettes.add(d);
      }
    }
    final refs = <Map<String, dynamic>>[];
    for (final b in (rec['boards'] as List? ?? const []).whereType<Map>()) {
      for (final r in (b['references'] as List? ?? const []).whereType<Map>()) {
        if (r['selected'] == true) refs.add(r.cast<String, dynamic>());
      }
    }
    refs.sort((a, b) =>
        ((b['total'] as num?) ?? 0).compareTo((a['total'] as num?) ?? 0));
    for (final r in refs) {
      final d = _referenceDerived(r);
      if (d != null) refPalettes.add(d);
    }
  }

  final plan = planReseed(
    fallback: fallback,
    brand: brand,
    suitors: suitorPalettes,
    references: refPalettes,
  );
  for (final n in plan.notes) {
    stdout.writeln(n);
  }
  stdout.writeln('default: ${plan.defaultId}');
  if (!args.contains('--apply')) {
    stdout.writeln('(dry run — pass --apply to write palettes.json, then run '
        '"arxa design palette-index $design")');
    return 0;
  }
  PaletteManifest(defaultId: plan.defaultId, palettes: plan.entries)
      .save(design);
  stdout.writeln('palette reseed: wrote $design/palettes.json — run '
      '"arxa design palette-index $design" to regenerate sheets + tokens');
  return 0;
}

Future<int> paletteCliMain(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: arxa palette <derive|reseed> ...');
    return 2;
  }
  switch (args.first) {
    case 'derive':
      return _derive(args.sublist(1));
    case 'reseed':
      return _reseed(args.sublist(1));
    default:
      stderr.writeln('arxa palette: unknown subcommand "${args.first}" (derive|reseed)');
      return 2;
  }
}
