// kit_facts — Dart port of stacked_kit/tools/extract_facts.sh.
//
// Mines each package under a kit root: pubspec (name/version/description/
// dependencies), the public Dart surface (class/enum/typedef/mixin names +
// kinds from lib/, comments and string contents stripped before matching),
// testing.dart presence, and README size + first line. Output is one JSON per
// kit (atomic temp + rename write), consumed downstream for drift detection
// and playbook generation — the codebase's mechanical memory.
//
// stripNoncode is the load-bearing part: it removes line comments, NESTED
// block comments (Dart allows nesting), and string contents (raw/normal,
// single/double/triple quotes, backslash escapes, and ${} interpolation whose
// nested code is itself re-scanned by the same machine) so a `// class Ghost`
// never reaches the symbol regex. Ported faithfully from the Python original.
//
// Adaptations from the shell+Python original:
//   - scans `kit/` (renamed from stacked_kit/) — pass as kitRoot
//   - kit dep prefix is `arxa_kit` (renamed from stacked_kit)
//   - FRAMEWORK set unchanged: stacked, stacked_services, stacked_shared,
//     stacked_generator, stacked_cli, meta (real pub.dev packages, not renamed)

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Framework deps that are constant across the rename — real pub.dev packages,
/// not renamed. Mirrors the FRAMEWORK set in extract_facts.sh.
const Set<String> frameworkDeps = {
  'stacked',
  'stacked_services',
  'stacked_shared',
  'stacked_generator',
  'stacked_cli',
  'meta',
};

/// The kit-package name prefix (renamed from stacked_kit_* → arxa_kit_*).
const String kitPrefix = 'arxa_kit';

/// Declaration regex: a kind keyword + a Capitalized identifier. Alternation
/// order matters — `abstract interface class` / `abstract class` must precede
/// the bare `class` so the full kind is captured rather than just `class`.
final RegExp _symRegex = RegExp(
  r'(abstract\s+interface\s+class|abstract\s+class|class|enum|typedef|mixin)'
  r'\s+([A-Z][A-Za-z0-9_]*)',
);

/// Extracts per-kit facts: pubspec metadata, public Dart surface, dependency
/// topology, README info.
///
/// [kitRoot] is the directory containing kit packages (e.g. `kit/`).
/// [factsDir], when given, is where one JSON per kit is written atomically
/// (temp file + rename, so a concurrent reader never sees a torn fact). When
/// null, no files are written — the facts are returned in memory only. Returns
/// the extracted facts in alphabetical kit order.
List<Map<String, dynamic>> extractFacts(String kitRoot, {String? factsDir}) {
  final root = Directory(kitRoot);
  if (!root.existsSync()) return const [];

  if (factsDir != null) Directory(factsDir).createSync(recursive: true);

  final facts = <Map<String, dynamic>>[];
  for (final kit in _discoverKits(root)) {
    final dir = Directory(p.join(kitRoot, kit));
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) continue;

    final pub = _parsePubspec(pubspec);
    final syms = _publicSurface(Directory(p.join(dir.path, 'lib')));
    final readme = _readmeInfo(dir);
    final hasTesting =
        File(p.join(dir.path, 'lib', 'testing.dart')).existsSync();

    // Dependency topology: kit↔kit deps, framework deps, backing (third-party).
    // Lists preserve pubspec declaration order (Map iteration order).
    final kitDeps = <String>[
      for (final k in pub.dependencies.keys)
        if (k.startsWith(kitPrefix) && k != pub.name) k,
    ];
    final framework = <String>[
      for (final k in pub.dependencies.keys)
        if (frameworkDeps.contains(k)) k,
    ];
    final backing = <String>[
      for (final k in pub.dependencies.keys)
        if (!frameworkDeps.contains(k) &&
            !k.startsWith(kitPrefix) &&
            k != 'flutter')
        k,
    ];

    facts.add({
      'kit': kit,
      'name': pub.name,
      'version': pub.version,
      'description': pub.description,
      'dependencies': pub.dependencies,
      'kitDeps': kitDeps,
      'frameworkDeps': framework,
      'backingPackages': backing,
      'publicSurface': syms,
      'hasTesting': hasTesting,
      'readmeLines': readme.lines,
      'readmeFirst': readme.first,
    });

    if (factsDir != null) {
      _atomicWrite(p.join(factsDir, '$kit.json'), facts.last);
    }
  }
  return facts;
}

/// Immediate subdirectories of [root] holding a pubspec.yaml, basename only,
/// sorted. Skips `.dart_tool` (regenerable). Mirrors the
/// `find -maxdepth 2 -name pubspec.yaml` in extract_facts.sh (kit/ is flat).
List<String> _discoverKits(Directory root) {
  final kits = <String>[];
  for (final entry in root.listSync()) {
    if (entry is! Directory) continue;
    final name = p.basename(entry.path);
    if (name == '.dart_tool') continue;
    if (File(p.join(entry.path, 'pubspec.yaml')).existsSync()) {
      kits.add(name);
    }
  }
  kits.sort();
  return kits;
}

/// Parse a pubspec.yaml into name/version/description/dependencies. A tiny
/// hand-rolled reader — pubspec.yaml is structurally simple (no flow style,
/// no anchors) and pulling in a YAML dep for this would be overkill.
({String name, String version, String description, Map<String, String> dependencies})
    _parsePubspec(File pubspec) {
  var name = '';
  var version = '';
  var desc = '';
  final deps = <String, String>{};
  final lines = pubspec.readAsLinesSync();
  const foldMarkers = {'', '>-', '>', '|-', '|'};
  var section = ''; // '' | 'deps'

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.startsWith('name:')) {
      name = line.substring(line.indexOf(':') + 1).trim();
    } else if (line.startsWith('version:')) {
      version = line.substring(line.indexOf(':') + 1).trim();
    } else if (line.startsWith('description:')) {
      // Plain scalars and YAML fold markers (>- > |- |) both continue on
      // more-indented lines; consume and join them. Quote-wrapped values are
      // unwrapped first (strip leading/trailing " then ').
      var val = line.substring(line.indexOf(':') + 1).trim();
      val = _stripEnds(val, '"');
      val = _stripEnds(val, "'");
      final parts = foldMarkers.contains(val) ? <String>[] : [val];
      i += 1;
      while (i < lines.length && _contLine.hasMatch(lines[i])) {
        parts.add(lines[i].trim());
        i += 1;
      }
      desc = parts.join(' ');
      continue; // i already advanced past the continuation block
    } else if (_depsSection.hasMatch(line)) {
      section = 'deps';
    } else if (_endSection.hasMatch(line)) {
      section = '';
    } else if (section == 'deps') {
      final m = _depLine.firstMatch(line);
      if (m != null) {
        final v = m.group(2)!.trim();
        deps[m.group(1)!] = v.isEmpty ? '(path/sdk)' : v;
      }
    }
    i += 1;
  }
  return (name: name, version: version, description: desc, dependencies: deps);
}

/// README.md line count + first non-empty heading line (leading `#` stripped).
/// Returns (0, '') when absent.
({int lines, String first}) _readmeInfo(Directory dir) {
  final file = File(p.join(dir.path, 'README.md'));
  if (!file.existsSync()) return (lines: 0, first: '');
  // split('\n') (not readAsLines) so a trailing newline counts as one more
  // line — matches the Python `read().split('\n')` byte-for-byte.
  final lines = file.readAsStringSync().split('\n');
  var first = '';
  for (final l in lines) {
    if (l.trim().isNotEmpty) {
      first = l.trim().replaceFirst(RegExp(r'^#+'), '').trim();
      break;
    }
  }
  return (lines: lines.length, first: first);
}

/// Public Dart surface from lib/: for each .dart file (sorted within a dir,
/// then subdirs sorted — deterministic, unlike os.walk's FS order), strip
/// comments/strings and collect the first declaration of each name (first
/// occurrence wins, dedup by name). `file` is relative to lib/.
List<Map<String, String>> _publicSurface(Directory libdir) {
  final syms = <Map<String, String>>[];
  if (!libdir.existsSync()) return syms;
  _walkDart(libdir, libdir, syms, <String>{});
  return syms;
}

void _walkDart(Directory dir, Directory libdir, List<Map<String, String>> syms,
    Set<String> seen) {
  final files = <File>[];
  final dirs = <Directory>[];
  for (final e in dir.listSync()) {
    if (e is Directory) {
      dirs.add(e);
    } else if (e is File && e.path.endsWith('.dart')) {
      files.add(e);
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  dirs.sort((a, b) => a.path.compareTo(b.path));

  for (final f in files) {
    String txt;
    try {
      txt = f.readAsStringSync();
    } catch (_) {
      txt = '';
    }
    final rel = p.relative(f.path, from: libdir.path).replaceAll('\\', '/');
    for (final m in _symRegex.allMatches(stripNoncode(txt))) {
      final kind = m.group(1)!.replaceAll('  ', ' ').trim();
      final nm = m.group(2)!;
      if (seen.contains(nm)) continue;
      seen.add(nm);
      syms.add({'name': nm, 'kind': kind, 'file': rel});
    }
  }
  for (final d in dirs) {
    _walkDart(d, libdir, syms, seen);
  }
}

/// Atomically write [fact] as pretty JSON to [outPath]: write `<outPath>.tmp`
/// then rename over the target. rename(2) atomically replaces, so a reader
/// never observes a half-written file. No trailing newline (matches Python
/// `json.dump`).
void _atomicWrite(String outPath, Map<String, dynamic> fact) {
  final tmp = '$outPath.tmp';
  File(tmp).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(fact));
  File(tmp).renameSync(outPath);
}

// ── stripNoncode ──────────────────────────────────────────────────────────
//
// Removes comments and string contents before symbol matching, so text like
// `// class Ghost {}` never reaches the regex. Handles Dart's forms: line
// comments, NESTED block comments, raw/normal strings, single/double/triple
// quotes, backslash escapes, and ${} interpolation (whose nested code is
// scanned by the same machine — declarations can't appear in an expression,
// but nested strings can). Faithful port of the Python strip_noncode.

final RegExp _depsSection = RegExp(r'^dependencies:\s*$');
final RegExp _endSection = RegExp(r'^(dev_dependencies|flutter|environment):');
final RegExp _depLine = RegExp(r'^  ([A-Za-z0-9_]+):\s*(.*)');
final RegExp _contLine = RegExp(r'^\s+\S');

enum _LexState { code, block, str }

class _StrFrame {
  const _StrFrame(this.q, this.triple, this.raw, this.braces);
  final String q;
  final bool triple;
  final bool raw;
  final int braces;
}

/// Strip comments and string contents from Dart source [txt], returning the
/// surviving code (string/whitespace gaps collapse out — only the code chars
/// outside any comment or string literal remain).
String stripNoncode(String txt) {
  final out = StringBuffer();
  final n = txt.length;
  var i = 0;
  var state = _LexState.code;
  var blockDepth = 0;
  var q = ''; // current quote char
  var triple = false;
  var raw = false;
  // Frames to resume the enclosing string after a ${...} interpolation:
  // (q, triple, raw, braces-at-push-time).
  final stack = <_StrFrame>[];
  var braces = 0; // brace depth of the current ${...} level

  while (i < n) {
    final c = txt[i];
    if (state == _LexState.code) {
      if (_at(txt, '//', i)) {
        final j = txt.indexOf('\n', i);
        i = j < 0 ? n : j;
        continue;
      }
      if (_at(txt, '/*', i)) {
        state = _LexState.block;
        blockDepth = 1;
        i += 2;
        continue;
      }
      var j = i;
      raw = false;
      var cc = c;
      if (c == 'r' && i + 1 < n && (txt[i + 1] == "'" || txt[i + 1] == '"')) {
        raw = true;
        j += 1;
        cc = txt[j];
      }
      if (cc == "'" || cc == '"') {
        q = cc;
        triple = _at(txt, cc + cc + cc, j);
        state = _LexState.str;
        i = j + (triple ? 3 : 1);
        continue;
      }
      // Inside a ${...} interpolation, track braces so the matching `}` returns
      // to the enclosing string. (cc == c here: a raw prefix would have
      // continued above.)
      if (stack.isNotEmpty && c == '{') braces += 1;
      if (stack.isNotEmpty && c == '}') {
        braces -= 1;
        if (braces == 0) {
          final f = stack.removeLast();
          q = f.q;
          triple = f.triple;
          raw = f.raw;
          braces = f.braces;
          state = _LexState.str;
          i += 1;
          continue;
        }
      }
      out.write(c);
      i += 1;
      continue;
    }

    if (state == _LexState.block) {
      if (_at(txt, '/*', i)) {
        blockDepth += 1;
        i += 2;
        continue;
      }
      if (_at(txt, '*/', i)) {
        blockDepth -= 1;
        i += 2;
        if (blockDepth == 0) state = _LexState.code;
        continue;
      }
      i += 1;
      continue;
    }

    // state == str
    if (!raw && c == '\\') {
      i += 2; // backslash escape: skip the escaped char
      continue;
    }
    if (!raw && c == '\$' && i + 1 < n && txt[i + 1] == '{') {
      stack.add(_StrFrame(q, triple, raw, braces));
      braces = 1;
      state = _LexState.code;
      i += 2;
      continue;
    }
    if (triple) {
      if (_at(txt, q + q + q, i)) {
        state = _LexState.code;
        i += 3;
        continue;
      }
      i += 1;
      continue;
    }
    if (c == q) {
      state = _LexState.code;
      i += 1;
      continue;
    }
    i += 1;
  }
  return out.toString();
}

/// True iff [pat] occurs at index [i] of [s] (bounds-checked). A zero-alloc
/// alternative to `s.substring(i, i+len) == pat` for the hot stripNoncode loop.
bool _at(String s, String pat, int i) {
  final end = i + pat.length;
  if (end > s.length) return false;
  for (var j = 0; j < pat.length; j++) {
    if (s.codeUnitAt(i + j) != pat.codeUnitAt(j)) return false;
  }
  return true;
}

/// Strip all leading and trailing occurrences of [ch] from [s] (Python
/// `str.strip(ch)` semantics).
String _stripEnds(String s, String ch) {
  var start = 0;
  var end = s.length;
  while (start < end && s[start] == ch) {
    start++;
  }
  while (end > start && s[end - 1] == ch) {
    end--;
  }
  return s.substring(start, end);
}
