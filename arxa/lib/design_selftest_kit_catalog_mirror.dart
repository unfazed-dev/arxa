// Slice 6 (docs/plans/views-explode-lens-interflow-and-shell-panels.md, E5)
// — anti-rot check for the designer-side kit mirror.
//
// `config/kit-registry.json` is the single source of truth for kits;
// `skills/arxa-designer/references/kit-catalog.md` is supposed to mirror
// it for a human designer. Nothing enforced that mirror, so it rotted: 24
// kits in the registry, zero listed in the doc. This check makes that
// impossible to repeat silently — every `dir` in the registry must appear
// in the catalog doc as `` `dir` ``.
//
// Lives in its own file only because `_Check`/`_Section`/`_lXxx` in
// design_selftest.dart are library-private and that file was held by another
// agent when this was authored. WIRED as of 2026-08-02 —
// design_selftest.dart imports this and registers
// `_Check(_lKitCatalogMirror, _Section.structure, kitCatalogMirrorCheck)`;
// the selftest is 25 checks, not 24.
//
// Red-first, both directions, verified:
//   - strip every mention of `bluetooth` (table-only kit)
//       -> FAIL 1/24 kit(s) not mirrored: bluetooth
//   - delete the `payments` TABLE ROW, leaving its two prose mentions
//       -> FAIL 1/24 kit(s) not mirrored: payments
//   - restore -> passed 25, failed 0, skipped 0 of 25
// The second case is the one that matters: it was GREEN before the row-scoping
// below, so the check silently could not see a deleted row for any kit the
// prose happens to name.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/design_selftest.dart' show CheckOutcome;
import 'package:path/path.dart' as p;

/// Every `dir` in `config/kit-registry.json` must appear in
/// `skills/arxa-designer/references/kit-catalog.md` as `` `dir` ``.
///
/// [skill] is the designer skill dir the selftest runner already resolves
/// (`<repo>/skills/arxa-designer` by default — see `_defaultSkillDir` in
/// design_selftest.dart). The registry lives outside the skill tree at
/// `<repo>/config/kit-registry.json`, so the repo root is derived from
/// [skill] by walking up two segments (`skills/arxa-designer` -> repo).
/// [art] and [src] are unused; the signature matches `_CheckFn` in
/// design_selftest.dart so this drops into `_buildChecks` without adapting.
Future<CheckOutcome> kitCatalogMirrorCheck(String art, String skill, String src) async {
  // Walk UP from the skill dir for config/kit-registry.json rather than
  // assuming `dirname(dirname(skill))`. That assumption holds only for the
  // real `<repo>/skills/arxa-designer` layout and breaks the moment the skill
  // is a copy — design_selftest_test.dart builds a minimal clean skill in a
  // system temp dir, where the two-levels-up guess lands in /var/folders and
  // the check failed the green baseline. Falling back to cwd covers that case,
  // because the registry being checked is a REPO invariant, not a property of
  // whichever skill copy is under test.
  File? registryFile;
  for (var d = Directory(skill).absolute;; d = d.parent) {
    final f = File(p.join(d.path, 'config', 'kit-registry.json'));
    if (f.existsSync()) { registryFile = f; break; }
    if (d.path == d.parent.path) break;
  }
  for (var d = Directory.current.absolute; registryFile == null;) {
    final f = File(p.join(d.path, 'config', 'kit-registry.json'));
    if (f.existsSync()) { registryFile = f; break; }
    if (d.path == d.parent.path) break;
    d = d.parent;
  }
  if (registryFile == null) {
    return const CheckOutcome.fail(
        'config/kit-registry.json not found above the skill dir or the cwd');
  }
  final catalogFile = File(p.join(skill, 'references', 'kit-catalog.md'));
  if (!catalogFile.existsSync()) {
    return const CheckOutcome.fail('references/kit-catalog.md missing');
  }

  final dynamic registry;
  try {
    registry = jsonDecode(registryFile.readAsStringSync());
  } catch (e) {
    return CheckOutcome.fail('kit-registry.json does not parse: $e');
  }
  final kits = registry is Map ? registry['kits'] : null;
  if (kits is! List || kits.isEmpty) {
    return const CheckOutcome.fail('kit-registry.json "kits" is not a non-empty array');
  }

  // TABLE ROWS ONLY — not the whole document. Searching the full text passes
  // on a kit that is merely name-dropped in prose ("a checkout gets
  // `payments`"), so deleting its catalog ROW would go unnoticed: verified by
  // removing the `payments` row, which left the check green because two prose
  // mentions remained. Six kits are named in prose, so a whole-document search
  // is blind for a quarter of the registry. A row is a line starting with `|`.
  final rows = catalogFile
      .readAsLinesSync()
      .where((l) => l.trimLeft().startsWith('|'))
      .join('\n');
  final missing = <String>[];
  for (final k in kits) {
    if (k is! Map || k['dir'] is! String) {
      missing.add('(malformed registry entry: $k)');
      continue;
    }
    final dir = k['dir'] as String;
    if (!rows.contains('`$dir`')) missing.add(dir);
  }
  if (missing.isNotEmpty) {
    return CheckOutcome.fail(
        '${missing.length}/${kits.length} kit(s) not mirrored in kit-catalog.md: '
        '${missing.join(', ')}');
  }
  return CheckOutcome.okWithSummary('${kits.length} kits mirrored');
}
