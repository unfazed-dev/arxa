// KB-lint port of skills/appbox-lint/lint_kb.py — the WARN-class checks the
// Python script adds on top of validate_docs.dart's dead-link (R1, fail) and
// index-coverage (R2, warn) contract. The ERROR-class checks in lint_kb.py
// (index coverage, link integrity) are already enforced by validate_docs.dart
// and are intentionally NOT duplicated here; this module returns only the
// three advisory findings the script layers on top:
//   3. orphans  — a docs page with no inbound link AND absent from the index.
//   4. supersede — changelog uses 'supersed*' without a SUPERSEDED back-pointer.
//   5. wikilink — a [[slug]] in memory/**/*.md with no matching file stem.
//
// Memory path: lint_kb.py hardcoded a machine-specific ~/.claude/projects/...
// path — a bug. The port defaults to <root>/memory (this repo's memory tree),
// overridable via [memoryDir]. Pure Dart stdlib + package:path; no IO beyond
// reading the docs/memory trees.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// One KB-lint finding ([file] is repo-relative, e.g. docs/x.md or memory/y.md).
class KbIssue {
  final String file;
  final String message;
  const KbIssue(this.file, this.message);

  @override
  String toString() => '$file: $message';
}

// [text](target) — markdown link; group 1 is the bare target.
final _link = RegExp(r'\[[^\]]*\]\(([^)]+)\)');
// [[slug]] or [[slug|alias]] — group 1 is the slug.
final _wikilink = RegExp(r'\[\[([^\]|]+)(?:\|[^\]]*)?\]\]');
// Absolute or scheme targets are never repo-relative links.
final _external = RegExp(r'^(?:[a-z][a-z0-9+.-]*:|//|/)');

List<File> _mdFiles(Directory d) {
  if (!d.existsSync()) return const [];
  final files = d
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Runs the three WARN-class KB-lint checks under [root] (the repo root; docs
/// live in `[root]/docs` with the index at docs/INDEX.md, memory in [memoryDir]
/// which defaults to `[root]/memory`). Returns advisory findings — never throws,
/// never fails a run. Mirrors lint_kb.py checks 3-5.
List<KbIssue> lintKb(String root, {String? memoryDir}) {
  memoryDir ??= p.join(root, 'memory');
  final docsDir = Directory(p.join(root, 'docs'));
  final indexFile = File(p.join(docsDir.path, 'INDEX.md'));
  final indexTxt = indexFile.existsSync() ? indexFile.readAsStringSync() : '';
  final md = _mdFiles(docsDir);

  // Build the inbound set: every docs page that some relative .md link resolves
  // to. Dead targets simply contribute no inbound (they're validate_docs.dart
  // R1's job, not a KB-lint finding).
  final inbound = <String>{};
  for (final f in md) {
    for (final m in _link.allMatches(f.readAsStringSync())) {
      var tgt = m.group(1)!.split('#').first.trim();
      if (tgt.isEmpty || _external.hasMatch(tgt) || !tgt.endsWith('.md')) {
        continue;
      }
      final dest = p.normalize(p.join(p.dirname(f.path), tgt));
      if (File(dest).existsSync()) inbound.add(dest);
    }
  }

  final warnings = <KbIssue>[];

  // 3. ORPHANS — a docs page with no inbound link AND not referenced in the index.
  for (final f in md) {
    if (p.equals(f.path, indexFile.path)) continue;
    final rel = p.relative(f.path, from: docsDir.path).replaceAll(r'\', '/');
    final normalized = p.normalize(f.path);
    if (!inbound.contains(normalized) && !indexTxt.contains(rel)) {
      warnings.add(KbIssue(
          'docs/$rel', 'orphan: no inbound link and not indexed'));
    }
  }

  // 4. SUPERSEDE — changelog uses 'supersed*' without a SUPERSEDED back-pointer.
  final changelog = File(p.join(docsDir.path, 'changelog.md'));
  if (changelog.existsSync()) {
    final txt = changelog.readAsStringSync();
    if (RegExp('supersed', caseSensitive: false).hasMatch(txt) &&
        !txt.contains('SUPERSEDED')) {
      warnings.add(KbIssue('docs/changelog.md',
          "supersedes used but no 'SUPERSEDED' back-pointer found"));
    }
  }

  // 5. WIKILINK — a [[slug]] in memory/**/*.md with no matching file stem.
  final memDir = Directory(memoryDir);
  if (memDir.existsSync()) {
    final memFiles = _mdFiles(memDir);
    final slugs = memFiles
        .map((f) => p.basenameWithoutExtension(f.path))
        .toSet();
    for (final f in memFiles) {
      for (final m in _wikilink.allMatches(f.readAsStringSync())) {
        final slug = m.group(1)!.trim();
        if (!slugs.contains(slug)) {
          final rel =
              p.relative(f.path, from: memoryDir).replaceAll(r'\', '/');
          warnings.add(KbIssue('memory/$rel',
              'wikilink: [[$slug]] has no target file (forward-ref?)'));
        }
      }
    }
  }

  return warnings;
}
