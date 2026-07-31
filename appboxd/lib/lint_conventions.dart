// Repo convention linter — Dart port of
// archives/tooling-pre-dart/tools/lint_conventions.sh.
//
// Two checks survive the move to Dart:
//   R3 — no absolute project path literals outside config/ (machine paths
//        like /Volumes/ or /Users/ belong in config, never in a literal).
//        Read from config/forbidden_abs_prefixes.txt; substring match on
//        non-comment lines.
//   R2 — no stripped upstream identity names in code OR path
//        (config/stripped_names.txt); whole-token match over the whole
//        file, comments and log strings included.
//
// Retired with the move:
//   R4 — a gate importing a sibling gate (only gates/_common was allowed).
//        Moot: gates are Dart in appboxd/lib/, no sibling-import hazard.
//   R5 — `git diff --exit-code` for a regen assertion. Guarded Python
//        tooling that is gone.
//
// The bash version scanned `git ls-files` (respects .gitignore); this Dart
// port walks the tree and prunes hidden directories plus the build/vendored
// set (notably .dart_tool/, whose package_config.json embeds the very abs
// paths R3 forbids). Same effective scan surface.

import 'dart:io';

import 'package:path/path.dart' as p;

/// One rule violation against a scanned file ([file] is repo-relative).
class LintViolation {
  final String file;
  final String message;
  const LintViolation(this.file, this.message);
}

/// Outcome of a lint run: how many files were scanned and what failed.
class LintResult {
  final int scanned;
  final List<LintViolation> violations;
  const LintResult(this.scanned, this.violations);
  bool get ok => violations.isEmpty;
}

// Build output / vendored / cache trees pruned from the walk. These are
// .gitignored, so the bash `git ls-files` scan never saw them; they hold
// machine-generated paths and names that would only be R2/R3 noise. Hidden
// directories (anything starting with '.') are pruned separately in _walk.
const _skipDirs = <String>{
  'build', 'node_modules', '__pycache__', 'coverage', 'Pods', 'ephemeral',
};

// Flutter/Gradle-generated config FILES (gitignored — `git ls-files
// --exclude-standard` dropped them in the bash version). They embed
// machine-made absolute paths (FLUTTER_ROOT, sdk.dir, …): R3 noise, never
// authored literals. Pruned by basename wherever the walk finds them.
const _generatedFiles = <String>{
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  'local.properties',
  'Generated.xcconfig',
  'flutter_export_environment.sh',
};

final _commentLine = RegExp(r'^\s*#');

/// Runs the R2 + R3 convention lint over [root].
///
/// Requires `config/forbidden_abs_prefixes.txt` and `config/stripped_names.txt`
/// under [root]; both ship at the repo root.
LintResult lintConventions(String root) {
  final absPrefixes =
      _loadPatterns(p.join(root, 'config', 'forbidden_abs_prefixes.txt'));
  final strippedNames =
      _loadPatterns(p.join(root, 'config', 'stripped_names.txt'));

  final violations = <LintViolation>[];
  var scanned = 0;

  void check(String path, String rel) {
    scanned++;

    // R2 path check — whole token, before reading content: a stripped name
    // in a path is a violation even for a binary file.
    for (final name in strippedNames) {
      if (_containsWholeWord(rel, name)) {
        violations.add(
            LintViolation(rel, "stripped upstream name '$name' in path (R2)"));
        break;
      }
    }

    String content;
    try {
      content = File(path).readAsStringSync();
    } catch (_) {
      return; // binary or unreadable — content rules don't apply
    }

    // R2 content check — whole file, comments and log strings included.
    for (final name in strippedNames) {
      if (_containsWholeWord(content, name)) {
        violations.add(LintViolation(
            rel, "stripped upstream name '$name' in content (R2)"));
        break;
      }
    }

    // R3 — absolute path literal on non-comment lines, outside config/.
    if (!_underConfig(rel)) {
      for (final line in content.split('\n')) {
        if (_commentLine.hasMatch(line)) continue;
        for (final prefix in absPrefixes) {
          if (line.contains(prefix)) {
            violations.add(
                LintViolation(rel, 'absolute path literal (R3: read from config)'));
            return;
          }
        }
      }
    }
  }

  _walk(root, root, check);
  return LintResult(scanned, violations);
}

/// Reads a rule file: one pattern per line, `#`-lines and blanks dropped
/// (mirrors `grep -vE '^[[:space:]]*#|^[[:space:]]*$'`).
List<String> _loadPatterns(String path) {
  final lines = File(path).readAsLinesSync();
  return lines
      .where((l) => l.trim().isNotEmpty && !l.trim().startsWith('#'))
      .toList();
}

bool _underConfig(String rel) => rel == 'config' || rel.startsWith('config/');

/// Fixed-substring match bounded by non-word characters (grep -owF). A word
/// char is `[A-Za-z0-9_]`, matching grep's definition.
bool _containsWholeWord(String text, String word) {
  var from = 0;
  while (true) {
    final i = text.indexOf(word, from);
    if (i < 0) return false;
    final beforeOk = i == 0 || !_isWordChar(text.codeUnitAt(i - 1));
    final afterOk = i + word.length >= text.length ||
        !_isWordChar(text.codeUnitAt(i + word.length));
    if (beforeOk && afterOk) return true;
    from = i + 1;
  }
}

bool _isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5a) || // A-Z
    (c >= 0x61 && c <= 0x7a) || // a-z
    c == 0x5f; // _

/// Recursive walk: emits non-exempt files as (absolutePath, repoRelative).
void _walk(String dir, String root, void Function(String, String) onFile) {
  List<FileSystemEntity> entries;
  try {
    entries = Directory(dir).listSync();
  } catch (_) {
    return;
  }
  for (final entry in entries) {
    final name = p.basename(entry.path);
    if (entry is Directory) {
      // Hidden dirs (.git, .dart_tool, .kimi-code, .kit, …) and the named
      // build/vendored set are the gitignore-equivalent prune surface.
      if (name.startsWith('.') || _skipDirs.contains(name)) continue;
      _walk(entry.path, root, onFile);
    } else if (entry is File) {
      final rel = p.relative(entry.path, from: root);
      if (_isExempt(rel)) continue;
      onFile(entry.path, rel);
    }
  }
}

bool _isExempt(String rel) {
  if (rel.startsWith('docs/')) return true;
  if (p.extension(rel) == '.md') return true;
  final base = p.basename(rel);
  if (base == 'LICENSE' || base.startsWith('LICENSE.')) return true;
  if (_generatedFiles.contains(base)) return true;
  // The rule definitions themselves — scanning them is self-referential.
  if (rel == 'config/stripped_names.txt') return true;
  if (rel == 'config/forbidden_abs_prefixes.txt') return true;
  // The linter's own source/tests reference the rule patterns by design
  // (the bash version exempted tools/lint_conventions.sh and its selftest).
  if (rel == 'appboxd/lib/lint_conventions.dart') return true;
  if (rel == 'appboxd/test/lint_conventions_test.dart') return true;
  return false;
}
