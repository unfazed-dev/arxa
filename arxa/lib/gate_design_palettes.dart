/// The P-gate: the palette-plane completeness law (grilled Q9 of
/// docs/plans/arxa-palette-plane-universal.md), enforced against ANY design
/// artifact tree. Companion to the W/S gates: the plane is declared in
/// palettes.json, and a declaration that its artifacts cannot cash out is a
/// lie the lint catches at design time.
///
/// Four hard-fail rules; every failure names the concrete fix:
///
///   P1  manifest valid — palettes.json parses as a PaletteManifest (the
///       runtime's own load is the authority), the default id resolves to an
///       entry, every swatch is 3..7 of valid #rrggbb hexes (the Q5 law;
///       N=5 keeps the verified lightness-rank byte-for-byte).
///   P2  plane files — assets/styles/palettes/_template.json (the
///       pre-indexed color slots) and assets/app/palette.js (the live
///       attribute + broadcast runtime) exist.
///   P3  artifacts intact — every manifest entry with a sheet field has the
///       file on disk, and the tokens file carries a [data-palette="<id>"]
///       block for every NON-default entry (the default IS the base corpus
///       — it needs no block). The tokens file resolves site-layout first
///       (ui/styles/common/tokens.css), else app-layout
///       (assets/css/tokens.css — the hello-hda layout).
///   P4  template coverage — every color-bearing rule in the artifact's
///       stylesheets is indexed in _template.json; the leak-killer, run as
///       checkPaletteTemplate (the palette-index --check engine). Skipped
///       when the template itself is missing — P2 already owns that finding.
///       Drift naming ONLY allowlisted colors (the P4 allowlist below:
///       intentional chromatic rules, allowlisted by operator decision and
///       recorded in this file) drops to the notes channel; everything
///       else fails.
///
/// An artifact without palettes.json declares no palette plane and passes
/// vacuously — the same discipline as the S-gate without a shell registry;
/// pre-plane artifacts are migrated by tooling (Q9), never failed by lint.
///
/// The advisory channel (notes, like D9 — never a hard fail): a
/// hardcoded-hex sweep over the stylesheets OUTSIDE tokens.css and the
/// generated palette sheets. Intentional non-palette colors exist by law —
/// the #0a0a0a stage-island class — and ride the allowlist.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_axes.dart' show axisValuePattern;
import 'design_palette_index.dart' show checkPaletteTemplate;
import 'design_palettes.dart' show PaletteManifest, PaletteTemplate;
import 'design_tools.dart' show LintFinding;
import 'palette_contrast.dart';

final _hex6 = RegExp(r'^#[0-9a-fA-F]{6}$');

/// 6-digit hexes in the corpus. The lookahead refuses an 8-digit form's
/// first six digits — the plane speaks #rrggbb.
final _hardHex = RegExp(r'#[0-9a-fA-F]{6}(?![0-9a-fA-F])');

/// Intentional non-palette colors exist by law — the #0a0a0a stage-island
/// class (plan Q9). Lowercased; the sweep compares lowercased.
const _hexAllowlist = {'#0a0a0a'};

/// The P4 allowlist (plan amendment): intentional chromatic rules the
/// template deliberately does not index. The pattern — an intentional color
/// is allowlisted by operator decision and recorded HERE, in the gate —
/// keeps the honest indexer dumb: it reports every unindexed chromatic
/// rule; the gate decides which are lawful. #c0392b is the academy.css
/// .waitlist-error error-red class. Lowercased; drift hexes compare
/// lowercased. A drift line carrying any NON-allowlisted color (or no
/// color at all) fails — the allowlist excuses colors, never lines.
const _p4Allowlist = {
  '#c0392b', // arxa-site: academy.css .waitlist-error (the error red class)
  '#dc2626', // hello-hda: app.css .field --field-error (the error red class)
  '#d0b0e0', // energize-landing: rental fleet color swatch (product content,
  // not chrome — a fleet color chip stays itself under every palette)
};

/// Run P1–P5 over [artifactDir]. Hard failures return; the hardcoded-hex
/// sweep goes to [notes] and never affects the exit code. [templateCheck]
/// is the P4 engine seam — it defaults to checkPaletteTemplate, the pinned
/// palette-index signature; tests pin the gate's plumbing, not the
/// indexer's diff details (those belong to design_palette_index_test).
List<LintFinding> gateDesignPalettes(String artifactDir,
    {List<LintFinding>? notes, List<String> Function(String)? templateCheck}) {
  final findings = <LintFinding>[];
  final manifestFile = File(p.join(artifactDir, 'palettes.json'));
  // Vacuous pass: no plane declared (the S-gate registry discipline).
  if (!manifestFile.existsSync()) return findings;

  final manifest = _p1Manifest(artifactDir, manifestFile, findings);
  _p2PlaneFiles(artifactDir, findings);
  if (manifest != null) _p3Artifacts(artifactDir, manifest, findings);
  final templateFile = File(
      p.join(artifactDir, 'assets', 'styles', 'palettes', '_template.json'));
  if (templateFile.existsSync()) {
    for (final drift in (templateCheck ?? checkPaletteTemplate)(artifactDir)) {
      final driftHexes = _hardHex
          .allMatches(drift)
          .map((m) => m.group(0)!.toLowerCase())
          .toSet();
      if (driftHexes.isNotEmpty && driftHexes.every(_p4Allowlist.contains)) {
        notes?.add(LintFinding(
            templateFile.path,
            'P4 template coverage (allowlisted): $drift — intentional '
            'color on the P4 allowlist by operator decision, recorded in '
            'gate_design_palettes.dart'));
        continue;
      }
      findings
          .add(LintFinding(templateFile.path, 'P4 template coverage: $drift'));
    }
  }
  if (manifest != null) {
    _p5Contrast(artifactDir, manifest, findings, notes);
  }
  _advisoryHexSweep(artifactDir, notes);
  findings.sort((a, b) => a.toString().compareTo(b.toString()));
  return findings;
}

// ── P5: the contrast contract (grilled 2026-09-11) ─────────────────────
/// Every sheet-carrying palette answers for its contracted pairs against
/// the CSS that actually SHIPPED — hand edits and MANUAL entries are
/// caught here exactly like derivation bugs (author custody may publish
/// what it likes; the gate says true things). Hex-form slot values are
/// read in render order off the sheet (comments stripped first — the
/// solve log lives in the header), token values off the tokens block
/// (rgba forms keep their core). Ghost slots never ride the contract,
/// so they are never measured. A template with no contract earns an
/// advisory note, not a failure — legacy planes stay green.
void _p5Contrast(String artifactDir, PaletteManifest manifest,
    List<LintFinding> findings, List<LintFinding>? notes) {
  final template = PaletteTemplate.load(artifactDir);
  final templateFile = File(
      p.join(artifactDir, 'assets', 'styles', 'palettes', '_template.json'));
  if (template == null) return;
  if (!template.declaresContract) {
    notes?.add(LintFinding(templateFile.path,
        'P5 contrast: the template declares no pair contract — legacy plane; '
        'author pairs/familyPairs/surfaces in _template.json to switch the '
        'contrast engine on'));
    return;
  }
  final tokensFile = _tokensFile(artifactDir);
  final tokensText =
      tokensFile.existsSync() ? tokensFile.readAsStringSync() : '';
  for (final e in manifest.palettes) {
    final sheetPath = e.sheet;
    if (sheetPath == null) continue; // the default IS the base corpus
    final sheetFile = File(p.join(artifactDir, sheetPath.replaceFirst('/', '')));
    if (!sheetFile.existsSync()) continue; // P3 already fails this
    // The shipped hexes, in render order: strip comments, take the
    // 6-digit hexes the renderer emitted for hex-form slots.
    final body = sheetFile
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final shipped = RegExp(r'#[0-9a-fA-F]{6}\b')
        .allMatches(body)
        .map((m) => m.group(0)!.toUpperCase())
        .toList();
    final slotHexes = <String, String>{};
    var n = 0;
    for (var i = 0; i < template.rules.length; i++) {
      final slots = (template.rules[i]['slots'] as List).cast<Map>();
      for (var j = 0; j < slots.length; j++) {
        if (slots[j]['form'] == 'hex' && n < shipped.length) {
          slotHexes['r${i}s$j'] = shipped[n++];
        }
      }
      final key = template.rules[i]['key'];
      if (key is String && slots.isNotEmpty) {
        slotHexes[key] = slotHexes['r${i}s0'] ?? '';
      }
    }
    // Token values off the shipped tokens block (hex + rgba cores).
    final block = RegExp(
            '\\[data-palette="${e.id}"\\] \\{([^}]*)\\}')
        .firstMatch(tokensText);
    if (block != null) {
      for (final line in block.group(1)!.split('\n')) {
        final hex = RegExp('(--[a-z0-9-]+):\\s*(#[0-9a-fA-F]{6})')
            .firstMatch(line);
        if (hex != null) {
          slotHexes[hex.group(1)!] = hex.group(2)!.toUpperCase();
          continue;
        }
        final rgba = RegExp(
                '(--[a-z0-9-]+):\\s*rgba\\((\\d+), (\\d+), (\\d+),')
            .firstMatch(line);
        if (rgba != null) {
          slotHexes[rgba.group(1)!] = rgbToHexString(
              int.parse(rgba.group(2)!),
              int.parse(rgba.group(3)!),
              int.parse(rgba.group(4)!));
        }
      }
    }
    // Expand the family pairs the same way the solver does, then judge
    // every resolvable pair's shipped ratio.
    final expanded = expandPairsForGate(template);
    var failures = 0;
    for (final pair in expanded) {
      final fg = slotHexes[pair.fg], bg = slotHexes[pair.bg];
      if (fg == null || bg == null || fg.isEmpty || bg.isEmpty) continue;
      final measured = pair.fgAlpha == null
          ? contrastRatio(fg, bg)
          : contrastRatio(
              rgbToHexStringFromComposite(fg, bg, pair.fgAlpha!), bg);
      if (measured < pair.target) {
        failures++;
        findings.add(LintFinding(sheetFile.path,
            'P5 contrast: "${e.id}" — ${pair.fg} on ${pair.bg} '
            '(${pair.level}) ${measured.toStringAsFixed(2)}:1 < '
            '${pair.target}:1 — Re-solve in the dial or arxa design '
            'palette-index'));
      }
    }
    if (failures > 0 && !e.auto) {
      notes?.add(LintFinding(sheetFile.path,
          'P5 contrast: "${e.id}" is MANUAL (author custody) — the failing '
          'pairs above ship as authored; Re-solve returns it to AUTO'));
    }
  }
}

/// The gate's family-pair expansion — the solver's, minus the anchors
/// (the gate judges shipped hexes, never re-derives).
List<ContrastPair> expandPairsForGate(PaletteTemplate template) {
  final pairs = [...template.pairs];
  if (template.familyPairs.isEmpty) return pairs;
  for (var i = 0; i < template.rules.length; i++) {
    final rule = template.rules[i];
    final tpl = (rule['tpl'] as String).trimLeft();
    final slots = (rule['slots'] as List);
    if (slots.isEmpty || !tpl.startsWith('color:')) continue;
    final first = Map<String, Object?>.from(slots.first as Map);
    if (first['form'] != 'hex') continue;
    final fgFam = first['family'] as String;
    for (final fp in template.familyPairs) {
      if (fp.fg != fgFam) continue;
      for (var k = 0; k < template.rules.length; k++) {
        final srule = template.rules[k];
        final stpl = (srule['tpl'] as String).trimLeft();
        if (!stpl.startsWith('background')) continue;
        final ss = (srule['slots'] as List);
        if (ss.isEmpty) continue;
        final sslot = Map<String, Object?>.from(ss.first as Map);
        if (sslot['form'] != 'hex') continue;
        if (!fp.on.contains(sslot['family'])) continue;
        pairs.add(ContrastPair(fg: 'r${i}s0', bg: 'r${k}s0', level: fp.level));
      }
      for (final fam in fp.on) {
        final token = template.surfaces[fam];
        if (token != null && template.tokens.any((t) => t['name'] == token)) {
          pairs.add(ContrastPair(fg: 'r${i}s0', bg: token, level: fp.level));
        }
      }
    }
  }
  return pairs;
}

String rgbToHexString(int r, int g, int b) =>
    '#${[r, g, b].map((v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';

String rgbToHexStringFromComposite(String fg, String bg, double alpha) {
  final mixed = composite(hexToRgb(fg), hexToRgb(bg), alpha);
  return rgbToHexString(mixed[0], mixed[1], mixed[2]);
}

/// P1 — the manifest must parse, its default must resolve, and every swatch
/// obeys the 3–7 law over valid hexes. PaletteManifest.load stays the
/// authority (null = fail); the raw pass below only WORDS the failure
/// concretely — which entry, which swatch, which fix. Returns the loaded
/// manifest for P3, or null when the manifest could not be loaded.
PaletteManifest? _p1Manifest(
    String artifactDir, File manifestFile, List<LintFinding> findings) {
  final before = findings.length;
  void fail(String msg) => findings.add(LintFinding(manifestFile.path, msg));

  Object? parsed;
  try {
    parsed = jsonDecode(manifestFile.readAsStringSync());
  } catch (_) {
    fail('P1 manifest: palettes.json is not valid JSON — fix the file or '
        'delete it (an absent file declares no plane; a broken one lies)');
    return null;
  }
  if (parsed is! Map) {
    fail('P1 manifest: palettes.json must be a JSON object '
        '{"default": "<id>", "palettes": [...]} — fix the file or delete it');
    return null;
  }
  final def = parsed['default'];
  final list = parsed['palettes'];
  if (def is! String || list is! List) {
    fail('P1 manifest: palettes.json must carry "default" (an entry id) and '
        '"palettes" (a list of entries) — fix the file or delete it');
    return null;
  }
  final ids = <String>{};
  for (var i = 0; i < list.length; i++) {
    final raw = list[i];
    if (raw is! Map) {
      fail('P1 manifest: palettes[$i] is not an entry object — every entry '
          'carries id, name, swatch and themeColor');
      continue;
    }
    final id = raw['id'];
    if (id is! String || !axisValuePattern.hasMatch(id)) {
      fail('P1 manifest: palettes[$i] has no valid id — the id is the '
          'html[data-palette] value and must match ${axisValuePattern.pattern}');
      continue;
    }
    ids.add(id);
    if (raw['name'] is! String || raw['themeColor'] is! String) {
      fail('P1 manifest: palette "$id" must carry name and themeColor '
          'strings — themeColor is the meta theme-color while active');
    }
    final swatch = raw['swatch'];
    if (swatch is! List || swatch.length < 3 || swatch.length > 7) {
      fail('P1 3–7 law: palette "$id" declares '
          '${swatch is List ? swatch.length : 'no'} swatches — the '
          'declaration accepts 3..7 hexes (N<5 interpolates the missing '
          'roles, N>5 decimates; the dial editor floors at 3)');
    } else {
      for (final h in swatch) {
        if (h is! String || !_hex6.hasMatch(h)) {
          fail('P1 manifest: palette "$id" swatch "$h" is not a valid '
              'hex — the plane speaks 6-digit hexes with the # prefix');
        }
      }
    }
  }
  if (!ids.contains(def)) {
    fail('P1 manifest: default "$def" resolves to no entry — point '
        '"default" at one of {${ids.join(', ')}} or add the missing entry');
  }
  if (findings.length == before && PaletteManifest.load(artifactDir) == null) {
    fail('P1 manifest: palettes.json does not parse as a PaletteManifest — '
        'the plane is declared but broken; fix the file or delete it');
  }
  return PaletteManifest.load(artifactDir);
}

/// P2 — the two plane files every declaring artifact ships at birth.
void _p2PlaneFiles(String artifactDir, List<LintFinding> findings) {
  final template = File(
      p.join(artifactDir, 'assets', 'styles', 'palettes', '_template.json'));
  if (!template.existsSync()) {
    findings.add(LintFinding(
        template.path,
        'P2 plane files: assets/styles/palettes/_template.json is missing — '
        'the pre-indexed color slots every override sheet derives from; '
        'regenerate the plane (arxa design palette-index) or restore the file'));
  }
  final runtime = File(p.join(artifactDir, 'assets', 'app', 'palette.js'));
  if (!runtime.existsSync()) {
    findings.add(LintFinding(
        runtime.path,
        'P2 plane files: assets/app/palette.js is missing — the live '
        'data-palette attribute + broadcast runtime; restore it from the '
        'designer runtime vendor'));
  }
}

/// The tokens file the plane writes per-palette var blocks into. Two
/// stylesheet layouts exist (plan amendment): site-layout
/// ui/styles/common/tokens.css wins; app-layout artifacts (hello-hda) carry
/// assets/css/tokens.css. Falls back to the site path so a missing file
/// anchors its findings where the file SHOULD be.
File _tokensFile(String artifactDir) {
  final site =
      File(p.join(artifactDir, 'ui', 'styles', 'common', 'tokens.css'));
  if (site.existsSync()) return site;
  final app = File(p.join(artifactDir, 'assets', 'css', 'tokens.css'));
  if (app.existsSync()) return app;
  return site;
}

/// P3 — the manifest's promises on disk: every declared sheet exists, and
/// every non-default entry has its var block in the resolved tokens file
/// (the default IS the base corpus — it needs no block). Mirrors
/// PaletteIngestion's own intact-check so the gate and the runtime agree on
/// what "intact" means.
void _p3Artifacts(
    String artifactDir, PaletteManifest manifest, List<LintFinding> findings) {
  final tokensFile = _tokensFile(artifactDir);
  final tokensRel = p.relative(tokensFile.path, from: artifactDir);
  final tokens =
      tokensFile.existsSync() ? tokensFile.readAsStringSync() : null;
  for (final e in manifest.palettes) {
    final sheet = e.sheet;
    if (sheet != null &&
        !File(p.join(artifactDir, sheet.replaceFirst('/', ''))).existsSync()) {
      findings.add(LintFinding(
          p.join(artifactDir, 'palettes.json'),
          'P3 artifacts intact: palette "${e.id}" declares sheet $sheet but '
          'the file is gone — regenerate the override sheets (arxa design '
          'palette-index) or drop the entry from palettes.json'));
    }
    if (e.id == manifest.defaultId) continue;
    if (tokens == null || !tokens.contains('[data-palette="${e.id}"]')) {
      findings.add(LintFinding(
          tokensFile.path,
          'P3 artifacts intact: $tokensRel carries no '
          '[data-palette="${e.id}"] block — its variables never apply; '
          'regenerate the tokens blocks or drop the entry'));
    }
  }
}

/// The advisory sweep: hardcoded hexes in stylesheets outside the plane's
/// own files (tokens.css owns the vars; the generated sheets are hexes by
/// construction). Notes only — an intentional non-palette color is lawful
/// (the allowlist), so the sweep can never fail the gate.
void _advisoryHexSweep(String artifactDir, List<LintFinding>? notes) {
  if (notes == null) return;
  for (final root in ['assets', 'ui']) {
    final d = Directory(p.join(artifactDir, root));
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.css')) continue;
      final rel = p.relative(f.path, from: artifactDir);
      if (rel == p.join('ui', 'styles', 'common', 'tokens.css')) continue;
      if (rel == p.join('assets', 'css', 'tokens.css')) continue;
      if (p.isWithin(p.join('assets', 'styles', 'palettes'), rel)) continue;
      final hits = _hardHex
          .allMatches(f.readAsStringSync())
          .map((m) => m.group(0)!.toLowerCase())
          .where((h) => !_hexAllowlist.contains(h))
          .toSet()
          .toList()
        ..sort();
      if (hits.isEmpty) continue;
      notes.add(LintFinding(
          f.path,
          'hardcoded hexes outside the palette plane: ${hits.length} unique '
          '(${hits.take(3).join(', ')}${hits.length > 3 ? ', …' : ''}) — '
          'palette colors belong in tokens.css / the generated sheets; '
          'intentional non-palette colors ride the allowlist'));
    }
  }
}
