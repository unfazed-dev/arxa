/// The F-gate: the font-plane completeness law (grilled 2026-09-13),
/// enforced against ANY design artifact tree that declares fonts.json.
/// Companion to the P-gate (gate_design_palettes): a declaration the
/// artifacts cannot cash out is a lie the lint catches at design time.
///
/// Three hard-fail rules; every failure names the concrete fix:
///
///   F1  manifest valid — fonts.json parses as a FontPlaneManifest (the
///       runtime's own load is the authority), the defaults resolve to
///       declared choices, ids are url-lawful.
///   F2  plane files — assets/app/font.js (the live attribute + css2-link
///       runtime) exists when ANY declared choice loads a webfont (a
///       system-stack-only plane still needs it — the switcher must run).
///   F3  artifacts intact — every choice with a sheet has the file on
///       disk, and every role's token is declared in the corpus' base
///       stylesheets (a sheet overriding a token nothing reads is dead
///       weight; the base corpus IS the default choices).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_fonts.dart';
import 'design_tools.dart' show LintFinding;

List<LintFinding> gateDesignFonts(String artifactDir,
    {List<LintFinding>? notes}) {
  final findings = <LintFinding>[];
  final manifestFile = File(p.join(artifactDir, 'fonts.json'));
  // Vacuous pass: no plane declared (the universal law ships it at birth,
  // legacy trees adopt it when they are ready).
  if (!manifestFile.existsSync()) return findings;

  // F1 — manifest valid (the runtime's own loader is the authority).
  final manifest = FontPlaneManifest.load(artifactDir);
  if (manifest == null) {
    findings.add(LintFinding('fonts.json',
        'F1: fonts.json does not parse as a font plane declaration — the '
        'load is null (bad ids, a default naming an undeclared choice, or '
        'an empty roles array); fix the manifest'));
    return findings;
  }

  // F2 — the applier ships.
  final fontJs = File(p.join(artifactDir, 'assets', 'app', 'font.js'));
  if (!fontJs.existsSync()) {
    findings.add(LintFinding('assets/app/font.js',
        'F2: the font plane is declared but assets/app/font.js is missing '
        '— copy it from the starter (examples/hello-hda) so the attributes, '
        'the css2 link and the receipts have an owner'));
  }

  // F3 — sheets on disk + the role token is real corpus vocabulary.
  final corpus = StringBuffer();
  for (final dir in [
    Directory(p.join(artifactDir, 'ui', 'styles')),
    Directory(p.join(artifactDir, 'assets', 'css')),
  ]) {
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.css')) corpus.writeln(f.readAsStringSync());
    }
  }
  for (final role in manifest.roles) {
    if (!corpus.toString().contains(role.token)) {
      findings.add(LintFinding('fonts.json',
          'F3: role "${role.id}" overrides ${role.token} but no artifact '
          'stylesheet declares it — a sheet nothing reads is dead weight; '
          'point the role at the corpus\' real token'));
    }
    for (final c in role.choices) {
      if (c.sheet == null) continue;
      final f = File(p.join(artifactDir, c.sheet!.substring(1)));
      if (!f.existsSync()) {
        findings.add(LintFinding(c.sheet!,
            'F3: choice "${role.id}/${c.id}" declares this sheet but the '
            'file is missing — regenerate it (delete + re-pick the family)'));
      }
    }
  }
  if (findings.isEmpty && notes != null) {
    notes.add(LintFinding('fonts.json',
        'font plane: ${manifest.roles.length} role(s), '
        '${manifest.roles.fold<int>(0, (n, r) => n + r.choices.length)} '
        'choices — F1-F3 clean'));
  }
  return findings;
}
