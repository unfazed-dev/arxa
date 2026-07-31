// Docs index validator — enforces the docs/INDEX.md contract
// ("Every document in this repo … in one token-light file"):
//   R1 (FAIL) — every relative link target in docs/INDEX.md exists
//        (file or directory). Dead links are always wrong.
//   R2 (warn) — every docs/**/*.md is referenced from INDEX.md.
//        Orphans are advisory until the index is curated; they never
//        fail the run.
// Backs the doc-enforcement hooks (hooks/appbox-doc-*.js); pure Dart, no
// dependencies beyond path/ — same shape as lint_conventions.dart.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// One finding against the docs tree ([file] is repo-relative).
class DocIssue {
  final String file;
  final String message;
  const DocIssue(this.file, this.message);

  @override
  String toString() => '$file: $message';
}

/// Outcome of a validation run.
class DocsResult {
  final int scanned;
  final List<DocIssue> failures;
  final List<DocIssue> warnings;
  const DocsResult(this.scanned, this.failures, this.warnings);

  /// R2 orphans are advisory — only R1 dead links fail a run.
  bool get ok => failures.isEmpty;
}

final _link = RegExp(r'\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
final _external = RegExp(r'^(?:[a-z][a-z0-9+.-]*:|#)', caseSensitive: false);

/// Validates the docs contract under [root] (the repo root; docs live in
/// [root]/docs with the index at docs/INDEX.md).
DocsResult validateDocs(String root) {
  final docsDir = p.join(root, 'docs');
  final indexFile = File(p.join(docsDir, 'INDEX.md'));
  if (!indexFile.existsSync()) {
    return DocsResult(
        0, [DocIssue('docs/INDEX.md', 'index missing — nothing to enforce')], const []);
  }
  final index = indexFile.readAsStringSync();

  final failures = <DocIssue>[];
  final warnings = <DocIssue>[];

  // R1 — every relative link target in INDEX.md exists.
  var scanned = 0;
  for (final match in _link.allMatches(index)) {
    var target = match.group(1)!;
    if (_external.hasMatch(target)) continue; // http(s):, mailto:, #anchor
    target = target.split('#').first; // strip in-doc anchors
    if (target.isEmpty) continue;
    scanned++;
    final resolved = p.normalize(p.join(docsDir, target));
    if (!File(resolved).existsSync() && !Directory(resolved).existsSync()) {
      failures.add(DocIssue('docs/INDEX.md', 'dead link (R1): $target'));
    }
  }

  // R2 — every docs/**/*.md is referenced from INDEX.md (advisory).
  final dir = Directory(docsDir);
  if (dir.existsSync()) {
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final rel =
          p.relative(entity.path, from: docsDir).replaceAll(r'\', '/');
      if (rel == 'INDEX.md') continue;
      if (!index.contains(rel)) {
        warnings.add(DocIssue('docs/$rel', 'not referenced from INDEX.md (R2)'));
      }
    }
  }

  return DocsResult(scanned, failures, warnings);
}
