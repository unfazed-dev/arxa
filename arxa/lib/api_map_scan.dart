// api_map_scan.dart — deterministic Flutter API gate.
//
// Port of arxa_kit/tools/api_map_scan.sh. Scans the CONSUMER app's lib/ for
// every BANNED token in the enforced (`E`) rows of FLUTTER_API_MAP.md —
// deprecated or removed Flutter SDK APIs (FlatButton family, WillPopScope,
// withOpacity, 2018 TextTheme getters, …). Returns one [ApiMapViolation] per
// (file, token) hit — the gate fails on any hit.
//
// Scope: <appRoot>/lib only — never the vendored kit (it has its own gates),
// never test/. Dart comments are stripped before matching (same as
// capability_scan.dart); string literals are NOT stripped — don't name banned
// APIs in user-facing strings.
//
// Map grammar (parsed here — the fenced ```map block is the single source of
// truth; see FLUTTER_API_MAP.md for the full spec):
//   problem-class | mode | banned-tokens | material | cupertino | kit | urls
//   mode E = enforced (scanned), A = advisory (skipped); `—` = none;
//   `*` inside a token = .*? wildcard; tokens get \b at alphanumeric edges.

import 'dart:io';

import 'package:path/path.dart' as p;

/// One banned-API hit in the consumer app's lib/.
class ApiMapViolation {
  /// Relpath of the file (relative to appRoot) that matched.
  final String file;

  /// The banned token that matched.
  final String token;

  /// Sanctioned replacement (the `material` column of the map row).
  final String sanctioned;

  /// Problem class (the first column of the map row).
  final String problemClass;

  ApiMapViolation({
    required this.file,
    required this.token,
    required this.sanctioned,
    required this.problemClass,
  });

  @override
  String toString() => '$file — $token ($sanctioned; $problemClass)';
}

// ── comment stripping (same approach as capability_scan.dart) ─────────────────
final _lineComment = RegExp(r'//[^\n]*');
final _blockComment = RegExp(r'/\*.*?\*/', dotAll: true);

String _stripDartComments(String src) {
  final noBlocks = src.replaceAll(_blockComment, '');
  return noBlocks.replaceAll(_lineComment, '');
}

/// A parsed enforced map row: problem class, its (token, regex) pairs, and the
/// sanctioned replacement.
class _Rule {
  final String problemClass;
  final List<(String, RegExp)> tokens;
  final String sanctioned;
  _Rule(this.problemClass, this.tokens, this.sanctioned);
}

/// Scan [appRoot]/lib against the enforced rows of [mapPath]
/// (kit/core/FLUTTER_API_MAP.md). Violations are deduped by (file, token) and
/// sorted by (file, token).
///
/// Throws [FormatException] on a malformed map row or a missing map file, and
/// [StateError] when the map contains no enforced rows (a misconfigured gate —
/// mirrors the shell's exit code 2).
List<ApiMapViolation> scanApiMap(String appRoot, String mapPath) {
  final rules = _parseMap(mapPath);

  final hits = <String, ApiMapViolation>{}; // key '$file\x00$token'
  for (final f in _dartFilesIn(p.join(appRoot, 'lib'))) {
    final code = _stripDartComments(_readOrEmpty(f));
    final rel = p.relative(f.path, from: appRoot);
    for (final rule in rules) {
      for (final (tok, rx) in rule.tokens) {
        if (rx.hasMatch(code)) {
          final key = '$rel\x00$tok';
          hits.putIfAbsent(
            key,
            () => ApiMapViolation(
              file: rel,
              token: tok,
              sanctioned: rule.sanctioned,
              problemClass: rule.problemClass,
            ),
          );
        }
      }
    }
  }

  final out = hits.values.toList();
  out.sort((a, b) {
    final byFile = a.file.compareTo(b.file);
    return byFile != 0 ? byFile : a.token.compareTo(b.token);
  });
  return out;
}

/// Parse the fenced ```map block of [mapPath] into enforced [_Rule]s.
List<_Rule> _parseMap(String mapPath) {
  final f = File(mapPath);
  if (!f.existsSync()) {
    throw FormatException('api map scan: map not found: $mapPath');
  }
  final rows = <_Rule>[];
  var inBlock = false;
  for (final raw in f.readAsLinesSync()) {
    final s = raw.trim();
    if (s.startsWith('```')) {
      inBlock = s == '```map';
      continue;
    }
    if (!inBlock || s.isEmpty || s.startsWith('#')) continue;
    final fields = s.split('|').map((x) => x.trim()).toList();
    if (fields.length != 7) {
      throw FormatException(
          'api map scan: malformed map row (${fields.length} fields): $s');
    }
    final problemClass = fields[0];
    final mode = fields[1];
    final banned = fields[2];
    final material = fields[3];
    if (mode != 'E' || banned == '—') continue;
    final tokens = banned
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .map((t) => (t, _tokenRe(t)))
        .toList();
    rows.add(_Rule(problemClass, tokens, material));
  }
  if (rows.isEmpty) {
    throw StateError('api map scan: no enforced rows parsed from $mapPath');
  }
  return rows;
}

/// Build the regex for one banned token. `*` → `.*?` wildcard; word boundaries
/// added at alphanumeric (or `_`) edges. Mirrors api_map_scan.sh `token_re`.
RegExp _tokenRe(String tok) {
  var rx = RegExp.escape(tok).replaceAll(r'\*', '.*?');
  final alnumUnder = RegExp(r'[A-Za-z0-9_]');
  if (alnumUnder.hasMatch(tok[0])) rx = r'\b' + rx;
  if (alnumUnder.hasMatch(tok[tok.length - 1])) rx = rx + r'\b';
  return RegExp(rx);
}

// ── filesystem helpers ────────────────────────────────────────────────────────

List<File> _dartFilesIn(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  final out = <File>[];
  for (final entry in d.listSync(recursive: true)) {
    if (entry is File && entry.path.endsWith('.dart')) out.add(entry);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

String _readOrEmpty(File f) {
  try {
    return f.readAsStringSync();
  } catch (_) {
    return '';
  }
}
