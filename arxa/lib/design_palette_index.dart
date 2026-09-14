// design_palette_index — the template indexer (the universal palette plane,
// docs/plans/arxa-palette-plane-universal.md, Q9/Q10). The ONE home of the
// corpus index: walks the artifact's stylesheets, indexes every color-bearing
// rule into assets/styles/palettes/_template.json (the format the dial server
// derives palettes from — design_palettes.dart's PaletteTemplate), regenerates
// every seeded palette's override sheet + tokens block from palettes.json
// (idempotent birth + repair, through design_palettes' render API — one render
// home), and answers drift for the P-gate. The faithful Dart port of the
// retired evidence/rebrand/genpalettes.mjs — the change-one-change-both mirror
// law died with it.
//
// THE GENERALIZATION (the port's heart; constants empirically fitted by the
// SERVER workstream, 2026-09-10): each corpus color's family is DERIVED from
// palettes.json's default palette anchors —
//   d = sqrt((10·Δhue_circular)² + Δs² + Δl²), nearest anchor wins
// (classifies all 21 marine hexes + 8 triplets exactly; hue-lexicographic
// provably cannot — the paper/beige cluster needs saturation). Gates:
//   · saturation < 12 → palette-NEUTRAL (the #fff/#0a0a0a class): verbatim
//     passthrough, never a slot, never reported;
//   · nearest-anchor circular hue distance > 45° → unindexed + REPORTED by
//     checkPaletteTemplate (intentional chromatics like the error red class;
//     the P-gate owns the allowlist).
//
// The corpus law: ui/styles/**/*.css + assets/css/**/*.css, lexicographic,
// MINUS the generated assets/styles/palettes/ dir, MINUS the resolved tokens
// file (ui/styles/common/tokens.css when it exists, else
// assets/css/tokens.css — the two-layout law). Barrels and font files parse
// to zero color rules. The rule SET reproduces the mjs's hardcoded walk
// exactly (ordering differs; 59 rules, zero duplicate (at,sel,prop) keys, so
// reordered sheets are cascade-equal).
//
// CLI: arxa design palette-index <artifact-dir> [--check]
//   default: write _template.json + render the seeded sheets/tokens blocks
//   --check: print drift (missing template rules, stale template rules,
//            unindexed chromatic rules, token-list skew), exit 1 on any —
//            the P4 engine.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_palettes.dart'
    show PaletteIngestion, PaletteManifest, PaletteTemplate, hexToRgb,
        rgbToHex, rgbToHsl;
import 'palette_derive.dart' show anchorsForN;

// ── the tiny CSS parser (1:1 with the mjs) ───────────────────────────────

class CssRule {
  CssRule(this.at, this.sel, this.body);
  final List<String> at;
  final String sel;
  final String body;
}

List<CssRule> parseCss(String src) {
  src = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final rules = <CssRule>[];
  final atStack = <String>[];
  var i = 0;
  while (i < src.length) {
    while (i < src.length && RegExp(r'\s').hasMatch(src[i])) { i++; }
    if (i >= src.length) break;
    var prelude = '';
    while (i < src.length && src[i] != '{' && src[i] != '}' && src[i] != ';') {
      prelude += src[i++];
    }
    prelude = prelude.trim();
    if (i >= src.length) break;
    final ch = src[i];
    if (ch == ';') { i++; continue; }
    if (ch == '}') { i++; if (atStack.isNotEmpty) atStack.removeLast(); continue; }
    if (ch == '{') {
      i++;
      if (prelude.startsWith('@')) {
        if (RegExp(r'^@(media|supports)').hasMatch(prelude)) {
          atStack.add(prelude);
          continue;
        }
        var depth = 1;
        while (i < src.length && depth > 0) {
          if (src[i] == '{') { depth++; } else if (src[i] == '}') { depth--; }
          i++;
        }
        continue;
      }
      var body = '';
      while (i < src.length && src[i] != '}') {
        if (src[i] == '{') {
          throw StateError('nested block under: $prelude');
        }
        body += src[i++];
      }
      i++;
      rules.add(CssRule([...atStack], prelude, body));
    }
  }
  return rules;
}

// ── the family derivation (the generalization) ───────────────────────────

double _hueDist(double a, double b) {
  var d = (a - b).abs();
  return d > 180 ? 360 - d : d;
}

/// The corpus color -> palette family law: the euclidean (10·Δhue, Δs, Δl)
/// nearest default-palette anchor, gated — saturation < 12 is neutral (null)
/// and a nearest hue distance > 45° is unindexed (null).
String? familyOf(String hex, Map<String, String> anchors) {
  final rgb = hexToRgb(hex);
  final hsl = rgbToHsl(rgb[0], rgb[1], rgb[2]);
  String? best;
  var bestD = double.infinity;
  var bestHue = double.infinity;
  for (final e in anchors.entries) {
    final argb = hexToRgb(e.value);
    final ahsl = rgbToHsl(argb[0], argb[1], argb[2]);
    final dh = _hueDist(hsl[0], ahsl[0]) * 10;
    final ds = hsl[1] - ahsl[1];
    final dl = hsl[2] - ahsl[2];
    final d = dh * dh + ds * ds + dl * dl;
    if (d < bestD) {
      bestD = d;
      best = e.key;
      bestHue = _hueDist(hsl[0], ahsl[0]);
    }
  }
  // The neutral gate (s < 12) keeps hue-less colors out of the slot
  // machinery — but never drops a color that IS (near-)an anchor: a
  // low-saturation ROLE value (energize's warm-gray field) must index.
  if (hsl[1] < 12 && bestD > 25) return null;
  if (best == null || bestHue > 45) return null;
  return best;
}

// ── the corpus walk (the two-layout law) ─────────────────────────────────

/// The resolved tokens file: site-layout first, else app-layout.
String tokensFileFor(String artifactDir) {
  final site = p.join(artifactDir, 'ui', 'styles', 'common', 'tokens.css');
  if (File(site).existsSync()) return site;
  return p.join(artifactDir, 'assets', 'css', 'tokens.css');
}

/// Every stylesheet of the corpus, lexicographic: ui/styles/** and
/// assets/css/**, minus the generated sheets dir and the resolved tokens
/// file. Barrels (@import-only) and font files yield zero color rules.
List<File> corpusFiles(String artifactDir) {
  final out = <File>[];
  final tokens = p.normalize(tokensFileFor(artifactDir));
  for (final root in ['ui/styles', 'assets/css']) {
    final dir = Directory(p.join(artifactDir, root));
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.css')) continue;
      if (p.normalize(f.path) == tokens) continue;
      if (p.normalize(f.path).contains('assets/styles/palettes')) continue;
      out.add(f);
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

// ── declarations + selector prefixing (1:1 with the mjs) ─────────────────

final _hexRe = RegExp(r'#[0-9a-fA-F]{6}\b');
final _rgbRe = RegExp(
    r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([^)]*?)\s*)?\)');

List<(String, String)> _decls(CssRule r) {
  final out = <(String, String)>[];
  for (final d in r.body.split(';')) {
    final ci = d.indexOf(':');
    if (ci < 0) continue;
    final prop = d.substring(0, ci).trim();
    final val = d.substring(ci + 1).trim();
    if (prop.isNotEmpty && val.isNotEmpty) out.add((prop, val));
  }
  return out;
}

String prefixSel(String sel, String attr) {
  return sel.split(',').map((part) {
    final s = part.trim();
    if (RegExp(r'^html\b').hasMatch(s)) {
      return s.replaceFirst(RegExp(r'^html'), 'html$attr');
    }
    if (RegExp(r'^:root\b').hasMatch(s)) {
      return s.replaceFirst(RegExp(r'^:root'), 'html$attr');
    }
    return '$attr $s';
  }).join(',\n');
}

// ── the index ────────────────────────────────────────────────────────────

class PaletteIndex {
  PaletteIndex({required this.anchors, required this.tokens, required this.rules});
  final Map<String, String> anchors;
  final List<Map<String, Object?>> tokens;
  final List<Map<String, Object?>> rules;

  Map<String, Object?> toJson() => {
        'comment': 'Palette ingestion template (the universal palette plane): '
            'the dial server derives palettes by the transplant law — anchors '
            'by the variable-width role law (anchorsForN); per slot dh '
            'additive, s ratio capped [0.3,1.3], dL additive vs the family '
            'anchor. {id} in sel, {n} in tpl are substitution slots. '
            'Regenerate with "arxa design palette-index".',
        'anchors': {
          // The mjs's insertion order, kept for byte-stability.
          'accent': anchors['accent'],
          'dark': anchors['dark'],
          'paper': anchors['paper'],
          'beige': anchors['beige'],
          'field': anchors['field'],
        },
        'tokens': tokens,
        'rules': rules,
      };
}

/// True when a declaration value carries at least one chromatic literal
/// (neutral literals — whites/grays/blacks — never make a rule color-
/// bearing for drift purposes).
bool _hasChromatic(String val, Map<String, String> anchors) {
  for (final m in _hexRe.allMatches(val)) {
    final rgb = hexToRgb(m.group(0)!);
    if (rgbToHsl(rgb[0], rgb[1], rgb[2])[1] >= 12) return true;
  }
  for (final m in _rgbRe.allMatches(val)) {
    final rgb = [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    ];
    if (rgbToHsl(rgb[0], rgb[1], rgb[2])[1] >= 12) return true;
  }
  return false;
}

/// Index the tokens file's :root declarations in order: var name, base
/// value, derived family, form. Exact-hex → 'hex' (base lowercased); a value
/// that IS exactly one rgb()/rgba() → 'rgba:ALPHA-AS-WRITTEN'; a value
/// carrying exactly one triplet → 'shadow:<value with the triplet replaced
/// by {t}>' (the name is historical — the mechanism is any single-triplet
/// value). Neutral and unassigned colors are skipped.
List<Map<String, Object?>> indexTokens(
    String artifactDir, Map<String, String> anchors) {
  final f = File(tokensFileFor(artifactDir));
  if (!f.existsSync()) return const [];
  final rules = parseCss(f.readAsStringSync());
  final out = <Map<String, Object?>>[];
  for (final r in rules) {
    if (r.sel != ':root') continue;
    for (final (prop, val) in _decls(r)) {
      if (!prop.startsWith('--')) continue;
      final wholeRgb = RegExp(
              r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([^)]*?)\s*)?\)$')
          .firstMatch(val);
      final hexMatch = _hexRe.firstMatch(val);
      if (hexMatch != null && wholeRgb == null) {
        final base = hexMatch.group(0)!.toLowerCase();
        final fam = familyOf(base, anchors);
        if (fam == null) continue;
        out.add({'name': prop, 'base': base, 'family': fam, 'form': 'hex'});
      } else if (wholeRgb != null) {
        final triplet = [
          int.parse(wholeRgb.group(1)!),
          int.parse(wholeRgb.group(2)!),
          int.parse(wholeRgb.group(3)!),
        ];
        final fam = familyOf(rgbToHex(triplet[0], triplet[1], triplet[2]), anchors);
        if (fam == null) continue;
        out.add({
          'name': prop,
          'base': triplet,
          'family': fam,
          'form': 'rgba:${wholeRgb.group(4) ?? '1'}',
        });
      } else {
        final m = _rgbRe.firstMatch(val);
        if (m == null) continue;
        final triplet = [
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
        ];
        final fam = familyOf(rgbToHex(triplet[0], triplet[1], triplet[2]), anchors);
        if (fam == null) continue;
        final tpl = val.replaceFirst(
            _rgbRe, 'rgba({t}, ${m.group(4) ?? '1'})');
        out.add({
          'name': prop,
          'base': triplet,
          'family': fam,
          'form': 'shadow:$tpl',
        });
      }
    }
  }
  return out;
}

/// Index every color-bearing declaration of the corpus into template rules.
List<Map<String, Object?>> indexRules(
    String artifactDir, Map<String, String> anchors) {
  final out = <Map<String, Object?>>[];
  for (final f in corpusFiles(artifactDir)) {
    for (final r in parseCss(f.readAsStringSync())) {
      for (final (prop, val) in _decls(r)) {
        final slots = <Map<String, Object?>>[];
        var idx = 0;
        var hit = false;
        var tpl = val.replaceAllMapped(_hexRe, (m) {
          final fam = familyOf(m.group(0)!, anchors);
          if (fam == null) return m.group(0)!;
          hit = true;
          slots.add({
            'base': m.group(0)!.toLowerCase(),
            'family': fam,
            'form': 'hex',
          });
          return '{${idx++}}';
        });
        tpl = tpl.replaceAllMapped(_rgbRe, (m) {
          final triplet = [
            int.parse(m.group(1)!),
            int.parse(m.group(2)!),
            int.parse(m.group(3)!),
          ];
          final fam =
              familyOf(rgbToHex(triplet[0], triplet[1], triplet[2]), anchors);
          if (fam == null) return m.group(0)!;
          hit = true;
          slots.add({'base': triplet, 'family': fam, 'form': 'triplet'});
          final alpha = m.group(4);
          final n = idx++;
          return (alpha != null && alpha.isNotEmpty)
              ? 'rgba({$n}, $alpha)'
              : 'rgb({$n})';
        });
        if (!hit) continue;
        out.add({
          'at': r.at,
          'sel': prefixSel(r.sel, '[data-palette="{id}"]'),
          'tpl': '$prop: $tpl;',
          'slots': slots,
        });
      }
    }
  }
  return out;
}

/// Index the artifact in memory (no writes). Null when no palette plane is
/// declared (a broken declaration disables, never guesses).
PaletteIndex? indexArtifact(String artifactDir) {
  final manifest = PaletteManifest.load(artifactDir);
  if (manifest == null) return null;
  final def = manifest.palettes.firstWhere((e) => e.id == manifest.defaultId);
  final anchors = anchorsForN(def.swatch);
  return PaletteIndex(
    anchors: anchors,
    tokens: indexTokens(artifactDir, anchors),
    rules: indexRules(artifactDir, anchors),
  );
}

/// Write assets/styles/palettes/_template.json (indent 1, the format
/// law). The contract survives a re-index (the 2026-09-11 contrast
/// engine): pairs/familyPairs/surfaces carry over verbatim, and each
/// re-indexed rule keeps the 'key' of the old rule with the same
/// (sel, at, tpl) signature — a contract never silently disappears
/// because the corpus drifted.
void writeTemplate(String artifactDir, PaletteIndex index) {
  final f =
      File(p.join(artifactDir, 'assets', 'styles', 'palettes', '_template.json'));
  Map<String, Object?>? prior;
  try {
    prior = jsonDecode(f.readAsStringSync()) as Map<String, Object?>?;
  } catch (_) {}
  final out = index.toJson();
  if (prior != null) {
    for (final k in ['pairs', 'familyPairs', 'surfaces']) {
      if (prior.containsKey(k)) out[k] = prior[k];
    }
    final oldKeys = <String, String>{};
    final oldRules = prior['rules'];
    if (oldRules is List) {
      for (final r in oldRules) {
        if (r is Map && r['key'] is String) {
          oldKeys['${r['sel']}|${(r['at'] as List).join('|')}|${r['tpl']}'] =
              r['key'] as String;
        }
      }
    }
    if (oldKeys.isNotEmpty && out['rules'] is List) {
      for (final r in (out['rules'] as List).whereType<Map>()) {
        final hit = oldKeys['${r['sel']}|${(r['at'] as List).join('|')}|${r['tpl']}'];
        if (hit != null) r['key'] = hit;
      }
    }
  }
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(
      '${const JsonEncoder.withIndent(' ').convert(out)}\n');
}

/// Regenerate every sheet-carrying manifest entry's override sheet + tokens
/// block through design_palettes' render API (one render home). Idempotent
/// birth + repair: the default palette is the base corpus (no sheet, its
/// block is the authored :root).
void renderSeeded(String artifactDir) {
  final manifest = PaletteManifest.load(artifactDir);
  final template = PaletteTemplate.load(artifactDir);
  if (manifest == null || template == null) return;
  final ingestion = PaletteIngestion(artifactDir: artifactDir);
  for (final entry in manifest.palettes) {
    if (entry.sheet == null) continue;
    final anchors = anchorsForN(entry.swatch);
    ingestion.renderSheet(entry, anchors, template);
    ingestion.replaceTokensBlock(entry, anchors, template);
  }
}

// ── the drift check (the P4 engine) ──────────────────────────────────────

String _ruleKey(String sel, List at, String prop) =>
    '$sel‖${at.join('‖')}‖$prop';

/// Re-index in memory and diff against the on-disk template + tokens file:
/// corpus rules missing from the template, template rules whose selector no
/// longer exists, unindexed chromatic rules (the P-gate allowlist filters
/// the intentional ones), and token-list skew. Empty = clean. No writes.
List<String> checkPaletteTemplate(String artifactDir) {
  final drift = <String>[];
  final manifest = PaletteManifest.load(artifactDir);
  if (manifest == null) return drift;
  final def = manifest.palettes.firstWhere((e) => e.id == manifest.defaultId);
  final anchors = anchorsForN(def.swatch);
  final templateFile =
      File(p.join(artifactDir, 'assets', 'styles', 'palettes', '_template.json'));
  if (!templateFile.existsSync()) {
    return ['_template.json missing — run "arxa design palette-index"'];
  }
  Map<String, dynamic> tpl;
  try {
    tpl = (jsonDecode(templateFile.readAsStringSync()) as Map)
        .cast<String, dynamic>();
  } catch (_) {
    return ['_template.json unreadable — run "arxa design palette-index"'];
  }
  final templateRules = <String>{};
  for (final r in (tpl['rules'] as List? ?? const []).whereType<Map>()) {
    final tplText = r['tpl']?.toString() ?? '';
    final prop = tplText.split(':').first.trim();
    templateRules.add(_ruleKey(r['sel']?.toString() ?? '',
        (r['at'] as List? ?? const []), prop));
  }
  final corpusKeys = <String>{};
  for (final f in corpusFiles(artifactDir)) {
    for (final r in parseCss(f.readAsStringSync())) {
      for (final (prop, val) in _decls(r)) {
        var hasFamily = false;
        for (final m in _hexRe.allMatches(val)) {
          if (familyOf(m.group(0)!, anchors) != null) hasFamily = true;
        }
        for (final m in _rgbRe.allMatches(val)) {
          if (familyOf(
                  rgbToHex(int.parse(m.group(1)!), int.parse(m.group(2)!),
                      int.parse(m.group(3)!)),
                  anchors) !=
              null) {
            hasFamily = true;
          }
        }
        final key = _ruleKey(
            prefixSel(r.sel, '[data-palette="{id}"]'), r.at, prop);
        if (hasFamily) {
          corpusKeys.add(key);
          if (!templateRules.contains(key)) {
            drift.add('missing template rule: ${r.sel} {$prop} — a color-'
                'bearing rule the template does not repaint');
          }
        } else if (_hasChromatic(val, anchors) &&
            !templateRules.contains(key)) {
          drift.add('unindexed chromatic rule: ${r.sel} {$prop: $val} — '
              'not palette-owned; intentional colors need the gate allowlist');
        }
      }
    }
  }
  for (final r in (tpl['rules'] as List? ?? const []).whereType<Map>()) {
    final tplText = r['tpl']?.toString() ?? '';
    final prop = tplText.split(':').first.trim();
    final key = _ruleKey(
        r['sel']?.toString() ?? '', (r['at'] as List? ?? const []), prop);
    if (!corpusKeys.contains(key)) {
      drift.add('stale template rule: ${r['sel']} {$prop} — the corpus no '
          'longer carries this selector');
    }
  }
  // content drift: a shared rule whose slot set changed — a hand-edited
  // corpus color would be repainted from a stale base (the sheet derives
  // transplant(slot.base, ...)), so a stale base is a wrong render.
  final liveRules = indexRules(artifactDir, anchors);
  final liveByKey = <String, Map>{
    for (final r in liveRules)
      _ruleKey(r['sel'].toString(), (r['at'] as List),
          r['tpl'].toString().split(':').first.trim()): r
  };
  String slotsOf(Map rule) => ([
        for (final s in (rule['slots'] as List? ?? const []).whereType<Map>())
          '${s['base']}|${s['family']}|${s['form']}'
      ]..sort())
      .join(',');
  for (final r in (tpl['rules'] as List? ?? const []).whereType<Map>()) {
    final prop = (r['tpl']?.toString() ?? '').split(':').first.trim();
    final key = _ruleKey(
        r['sel']?.toString() ?? '', (r['at'] as List? ?? const []), prop);
    final live = liveByKey[key];
    if (live == null) continue;
    if (slotsOf(r) != slotsOf(live)) {
      drift.add('template rule content drift: ${r['sel']} {$prop} — the '
          'color slots changed; re-run "arxa design palette-index"');
    }
  }
  // token-list skew
  final tokensOnDisk = {
    for (final t in (tpl['tokens'] as List? ?? const []).whereType<Map>())
      t['name'].toString()
  };
  final tokensLive = {
    for (final t in indexTokens(artifactDir, anchors)) t['name'].toString()
  };
  for (final name in tokensLive.difference(tokensOnDisk)) {
    drift.add('template token missing: $name — the tokens file declares it, '
        'the template does not derive it');
  }
  for (final name in tokensOnDisk.difference(tokensLive)) {
    drift.add('stale template token: $name — the tokens file no longer '
        'declares it');
  }
  return drift;
}

// ── the CLI entry ────────────────────────────────────────────────────────

int paletteIndexMain(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length != 1) {
    stderr.writeln('Usage: arxa design palette-index <artifact-dir> [--check]');
    return 2;
  }
  final dir = positional.first;
  if (PaletteManifest.load(dir) == null) {
    stderr.writeln('palette-index: $dir declares no palette plane '
        '(palettes.json missing or malformed)');
    return 1;
  }
  if (args.contains('--check')) {
    final drift = checkPaletteTemplate(dir);
    for (final d in drift) {
      stdout.writeln('drift: $d');
    }
    if (drift.isEmpty) stdout.writeln('palette-index check clean: $dir');
    return drift.isEmpty ? 0 : 1;
  }
  final index = indexArtifact(dir)!;
  writeTemplate(dir, index);
  renderSeeded(dir);
  stdout.writeln('palette-index: $dir — anchors 5, tokens '
      '${index.tokens.length}, rules ${index.rules.length}; seeded sheets + '
      'tokens blocks regenerated');
  return 0;
}
