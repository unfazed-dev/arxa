/// Emit-time `data-arxa-id` stamping — the machine identity layer decided
/// 2026-08-22 (arxa-harness-and-distribution.md, "RESOLVED — element
/// identity"). `data-el` stays the authored semantic layer; `data-arxa-id` is
/// engine-emitted, opaque, and stable, and is the ONLY attribute the drag
/// overlay, `design patch`, and the lens key on.
///
/// The decision's five points as implemented here:
///   1. two layers — `data-el` is never touched;
///   2. name — `data-arxa-id`;
///   3. stable ids authored at emit time — carry-forward is automatic because
///      stamping only ever ADDS the attribute to elements that lack one:
///      existing ids live in the source file and are never rewritten, so a
///      re-stamp after edits keeps every surviving element's id and allocates
///      fresh numbers (above the file's current max) only to new elements.
///      No sidecar — the artifact file is the persistence;
///   4. coverage — every host element (the htmlElementTags vocabulary), in
///      every .tsx template under the artifact dir, widgets included;
///   5. production — no strip mode exists and none is added.
///
/// Id shape: `<path-stem>-e<n>` where the stem is the artifact-relative path
/// without extension, slashes as dashes (`surfaces/cart.tsx` →
/// `surfaces-cart-e7`) — unique across files by construction.
///
/// Scanner law (write-safe beats clever):
///   - insertion point is ALWAYS immediately after the tag name, so the scan
///     never has to find the closing `>` to place the attribute;
///   - opening-tag extent (for the presence check) is found with quote- and
///     brace-tracking, so `>` inside `{expr}` (arrow functions, comparisons)
///     or inside quoted attribute values does not truncate the tag;
///   - block comments (/* */ and {/* */}) and HTML comments are skipped
///     everywhere; // line comments are skipped only at line start, matching
///     stripComments' anchoring so URLs in strings are not eaten;
///   - quoted strings in code are NOT skipped: an apostrophe in JSX text
///     ("Don't") is far more common than a string literal containing
///     `<tag`. The residual risk — a string literal holding literal JSX —
///     produces a visible diff line, not silent corruption, and lint bans
///     the innerHTML-shaped cases;
///   - `a < b` comparisons are safe (spaced); the unspaced form `a <b` with
///     b an HTML tag name would misparse — prettier-formatted sources never
///     produce it, and it too fails loudly in the diff.
///
/// Loop-rendered elements: one source element inside a `.map` renders N
/// instances that SHARE its id. That is the correct design-level semantic —
/// `design patch` patches the source element, i.e. every row at once; the
/// overlay disambiguates instances by index if it ever needs one row.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_tools.dart'
    show CmdResult, htmlElementTags, svgElementTags;

/// The stamper's full vocabulary — HTML host elements plus SVG, because the
/// ratified coverage is every element (svgElementTags doc explains the split).
final _stampableTags = <String>{...htmlElementTags, ...svgElementTags};

/// Outcome of stamping one source text.
class StampResult {
  /// The source with any missing ids inserted (identical to input when
  /// nothing needed stamping).
  final String code;

  /// How many elements received a new id this pass.
  final int stamped;

  /// How many elements already carried one.
  final int carried;

  const StampResult(this.code, this.stamped, this.carried);
}

final _idRe = RegExp(r'\bdata-arxa-id\s*=');
final _existingNumRe = RegExp(r'data-arxa-id="[^"]*?-e(\d+)"');

/// The id prefix for [relPath] (artifact-relative, POSIX or platform).
String idPrefixFor(String relPath) {
  final noExt = relPath.endsWith('.tsx')
      ? relPath.substring(0, relPath.length - 4)
      : relPath;
  return noExt.replaceAll('\\', '/').replaceAll('/', '-');
}

bool _isNameChar(int c) {
  return (c >= 97 && c <= 122) || // a-z
      (c >= 65 && c <= 90) || // A-Z — continuation only (camelCase svg:
      // clipPath, linearGradient…); the FIRST char is checked lowercase
      // at the call site, so Capitalized components stay exempt
      (c >= 48 && c <= 57) || // 0-9
      c == 45; // -
}

/// Index of the `>` closing the opening tag whose attrs start at [i],
/// tracking {} depth and quoted attribute values. -1 when the text gives
/// out or another `<` opens first (malformed — bail, stamp nothing).
/// Public: design_patch locates patch targets with the same walk.
int openingTagEnd(String s, int i) {
  var depth = 0;
  int? quote;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (quote != null) {
      if (c == 92) {
        i += 2; // backslash escape inside a quoted value
        continue;
      }
      if (c == quote) quote = null;
    } else if (c == 34 || c == 39) {
      quote = c; // " or '
    } else if (c == 123) {
      depth++; // {
    } else if (c == 125) {
      depth--; // }
    } else if (c == 62 && depth == 0) {
      return i; // >
    } else if (c == 60 && depth == 0) {
      return -1; // < — malformed
    }
    i++;
  }
  return -1;
}

/// Stamp [src], allocating ids under [prefix]. Pure — the file write lives
/// in [stampFile]/[stampMain].
StampResult stampSource(String src, String prefix) {
  // Next free counter: one past the highest -e<n> already in the file,
  // regardless of prefix (a file renamed by hand keeps its history).
  var next = 1;
  for (final m in _existingNumRe.allMatches(src)) {
    final n = int.parse(m.group(1)!);
    if (n >= next) next = n + 1;
  }

  final inserts = <int>[]; // offsets (after a tag name) needing an id
  var carried = 0;
  var i = 0;
  final len = src.length;
  while (i < len - 1) {
    final c = src.codeUnitAt(i);
    final d = src.codeUnitAt(i + 1);
    // Template literals — skipped, never stamped. This is where multi-line
    // markup strings live (raw(PIECES)-style generated SVG/HTML), and those
    // are data, not authored elements — stamping inside them would fight
    // their generators. Nested templates can theoretically leak a scan
    // region; the worst case is an id inside a string, visible in the diff
    // (the same documented residual class as quoted strings).
    if (c == 96) {
      // `
      var k = i + 1;
      while (k < len) {
        if (src.codeUnitAt(k) == 92) {
          k += 2; // escaped char
          continue;
        }
        if (src.codeUnitAt(k) == 96) break;
        k++;
      }
      i = k < len ? k + 1 : len;
      continue;
    }
    // Comments — skipped, never stamped.
    if (c == 47 && d == 42) {
      // /* anywhere
      final end = src.indexOf('*/', i + 2);
      i = end < 0 ? len : end + 2;
      continue;
    }
    if (c == 60 && src.startsWith('!--', i + 1)) {
      final end = src.indexOf('-->', i + 4);
      i = end < 0 ? len : end + 3;
      continue;
    }
    if (c == 47 &&
        d == 47 &&
        (i == 0 || src.codeUnitAt(i - 1) == 10 || _onlySpaceBackToLine(src, i))) {
      final end = src.indexOf('\n', i + 2);
      i = end < 0 ? len : end + 1;
      continue;
    }
    if (c == 60) {
      // <
      if (d == 47 || d == 62 || d == 33) {
        i++; // </ closing, <> fragment, <! doctype-ish
        continue;
      }
      if (d >= 97 && d <= 122) {
        var j = i + 1;
        while (j < len && _isNameChar(src.codeUnitAt(j))) {
          j++;
        }
        final name = src.substring(i + 1, j);
        if (!_stampableTags.contains(name)) {
          i = j; // TS generic or lowercase non-element — not markup
          continue;
        }
        // Generic-call shapes with an HTML-name type argument: foo<div>(…) or
        // foo<div, …>. Stamping these would corrupt code, so they bail here —
        // a real <div>( text node is not something templates produce.
        if (j < len &&
            (src.codeUnitAt(j) == 44 || // ,
                (src.codeUnitAt(j) == 62 && // > immediately followed by (
                    j + 1 < len &&
                    src.codeUnitAt(j + 1) == 40))) {
          i = j;
          continue;
        }
        final end = openingTagEnd(src, j);
        if (end < 0) {
          i = j; // malformed — bail on this tag, keep scanning
          continue;
        }
        if (_idRe.hasMatch(src.substring(j, end))) {
          carried++;
        } else {
          inserts.add(j);
        }
        i = end + 1;
        continue;
      }
    }
    i++;
  }

  if (inserts.isEmpty) return StampResult(src, 0, carried);

  final out = StringBuffer();
  var cursor = 0;
  for (final at in inserts) {
    out.write(src.substring(cursor, at));
    out.write(' data-arxa-id="$prefix-e${next++}"');
    cursor = at;
  }
  out.write(src.substring(cursor));
  return StampResult(out.toString(), inserts.length, carried);
}

/// True when only whitespace lies between [i] and the start of its line.
bool _onlySpaceBackToLine(String s, int i) {
  var k = i - 1;
  while (k >= 0) {
    final c = s.codeUnitAt(k);
    if (c == 10) return true;
    if (c != 32 && c != 9) return false;
    k--;
  }
  return true;
}

/// Stamp one file in place. Returns the [StampResult] for reporting.
StampResult stampFile(File file, String prefix) {
  final src = file.readAsStringSync();
  final res = stampSource(src, prefix);
  if (res.stamped > 0) file.writeAsStringSync(res.code);
  return res;
}

/// `arxa design stamp <artifactDir>` — stamp every .tsx template under the
/// artifact dir (widgets included; coverage is EVERY element).
CmdResult stampMain(List<String> args) {
  if (args.isEmpty) {
    return CmdResult(2, stderrLines: [
      'arxa design stamp: missing <artifactDir> '
          '(e.g. ~/.arxa/projects/<name>/design)'
    ]);
  }
  final dir = Directory(args.first);
  if (!dir.existsSync()) {
    return CmdResult(2,
        stderrLines: ['arxa design stamp: no such dir: ${args.first}']);
  }
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.tsx'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    return CmdResult(2,
        stderrLines: ['arxa design stamp: no .tsx under ${args.first}']);
  }
  final out = <String>[];
  var totalStamped = 0, totalCarried = 0;
  for (final f in files) {
    final rel = p.split(p.relative(f.path, from: dir.path)).join('/');
    final res = stampFile(f, idPrefixFor(rel));
    totalStamped += res.stamped;
    totalCarried += res.carried;
    out.add('$rel: ${res.stamped} stamped, ${res.carried} carried');
  }
  out.add('stamp: $totalStamped new ids, $totalCarried carried, '
      '${files.length} files');
  return CmdResult(0, stdoutLines: out);
}
