// Design-token extraction (ports probe-runner web_tokens): computed-style
// sweep in the page, pure-Dart clustering into semantic palette / type /
// spacing scales. Observation JSON — the lens records, consumers assert.
library;

import 'dart:convert';
import 'dart:io';

import '../cdp.dart';

/// The computed-style probe injected into the page. Returns flat samples:
/// every element's colour, background, font size, padding/margin/radius.
/// Kept as one evaluate() round-trip (probe-runner's _web_eval shape).
const String tokenProbeJs = r'''
(() => {
  const out = {colors: [], backgrounds: [], fontSizes: [], spaces: [], radii: []};
  for (const el of document.querySelectorAll('body, body *')) {
    const cs = getComputedStyle(el);
    if (cs.color) out.colors.push(cs.color);
    if (cs.backgroundColor && cs.backgroundColor !== 'rgba(0, 0, 0, 0)')
      out.backgrounds.push(cs.backgroundColor);
    out.fontSizes.push(parseFloat(cs.fontSize));
    for (const p of ['paddingTop','paddingRight','paddingBottom','paddingLeft',
                     'marginTop','marginRight','marginBottom','marginLeft']) {
      const v = parseFloat(cs[p]);
      if (v > 0) out.spaces.push(v);
    }
    const r = parseFloat(cs.borderRadius);
    if (r > 0) out.radii.push(r);
  }
  return out;
})()
''';

/// One colour occurrence: rgb + hit count.
class ColorCluster {
  ColorCluster(this.r, this.g, this.b, this.count);
  final int r, g, b, count;
  String get hex =>
      '#${[r, g, b].map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
  Map<String, dynamic> toJson() => {'hex': hex, 'count': count};
}

/// Parse 'rgb(r, g, b)' / 'rgba(r, g, b, a)' -> [r,g,b]; null on miss.
List<int>? parseCssColor(String s) {
  final m = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)').firstMatch(s);
  if (m == null) return null;
  return [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)];
}

/// Frequency-cluster raw css colours: exact-rgb grouping, sorted by
/// count desc. (probe-runner merged near-duplicates via numpy; exact
/// grouping over getComputedStyle output is deterministic and sufficient
/// because the browser already quantises to integers.)
// kimitail: exact-group only; ΔE-merge pass belongs here if palettes
// ever arrive from canvas/gradient sources with float noise.
List<ColorCluster> clusterColors(Iterable<String> cssColors) {
  final counts = <String, int>{};
  for (final c in cssColors) {
    counts[c] = (counts[c] ?? 0) + 1;
  }
  final out = <ColorCluster>[];
  for (final e in counts.entries) {
    final rgb = parseCssColor(e.key);
    if (rgb != null) out.add(ColorCluster(rgb[0], rgb[1], rgb[2], e.value));
  }
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

/// Frequency-cluster a numeric scale, dropping zeros, sorted ascending
/// with counts. Values within 0.5px are merged to their rounded int.
List<Map<String, dynamic>> clusterScale(Iterable<num> values) {
  final counts = <int, int>{};
  for (final v in values) {
    if (v <= 0) continue;
    final k = v.round();
    counts[k] = (counts[k] ?? 0) + 1;
  }
  final keys = counts.keys.toList()..sort();
  return [for (final k in keys) {'value': k, 'count': counts[k]}];
}

/// Extract the token scales of [url] at [width]x[height]. Console/page
/// errors fail the extraction (lens doctrine): they are returned in the
/// result and the caller treats non-empty as a failure.
Future<Map<String, dynamic>> extractTokens(String url, int width, int height,
    {int settleMs = 1500}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);
    final raw = await tab.evaluate(tokenProbeJs) as Map;
    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    return {
      'url': url,
      'viewport': [width, height],
      'palette': [
        for (final c in clusterColors([
          ...?(raw['colors'] as List?)?.cast<String>(),
          ...?(raw['backgrounds'] as List?)?.cast<String>(),
        ]))
          c.toJson(),
      ],
      'type': clusterScale((raw['fontSizes'] as List).cast<num>()),
      'spacing': clusterScale((raw['spaces'] as List).cast<num>()),
      'radii': clusterScale((raw['radii'] as List).cast<num>()),
      'consoleErrors': errors,
      'certified': errors.isEmpty,
    };
  } finally {
    await client.close();
  }
}

/// Write evidence JSON with parent dirs, lens convention.
///
/// The plan placed this helper in lib/lens.dart (the facade), but Task 3
/// is forbidden from editing lens.dart — re-exports are wired in Task 7.
/// Defined here (the exemplar module) so tokensToJson stays faithful to
/// the plan; Task 7 can lift it into the facade when it wires CLI wiring.
void writeLensJson(String path, String json) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('$json\n');
}

/// CLI helper: extract and print/write JSON.
Future<void> tokensToJson(String url, int width, int height, String? outPath,
    {int settleMs = 1500}) async {
  final result = await extractTokens(url, width, height, settleMs: settleMs);
  final json = const JsonEncoder.withIndent('  ').convert(result);
  if (outPath == null) {
    print(json);
  } else {
    writeLensJson(outPath, json);
  }
}
