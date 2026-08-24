/// `design patch` — the structured-patch verb the element-identity decision
/// (2026-08-22, arxa-harness-and-distribution.md) unblocked. Item 15's law:
/// every change is a structured patch against an element addressed by its
/// `data-arxa-id` — never freeform DOM/CSS writes, never whole-file rewrites.
///
/// v1 grammar (deliberately small — the drag overlay is the first consumer):
///   --set name=value      set/replace an attribute (value always re-quoted)
///   --rm name             remove an attribute
///   --style prop=value    merge one CSS property into the style attribute
///   --rm-style prop       remove one CSS property (empty style attr removed)
///   --text value          replace the element's whole text content — only a
///                         pure-text element; nested markup refuses loudly
///   --was previous        seed-route provenance: the instance's pre-edit
///                         rendered text (the value anchor)
///   --nth index           seed-route provenance: 0-based occurrence index
///                         among loop-rendered instances of the id
///   --page pathname       seed-route provenance: the page being edited
///                         (slug/href correlation)
///
/// Two applicators share one transform: [patchSource] for SOURCE (the id's
/// uniqueness invariant holds there, so a duplicate is a loud bail), and
/// [patchAllRendered] for RENDERED markup, where loop-rendered instances
/// SHARE an id by design (design_stamp.dart) and the design-level semantic
/// of patching the source element is "every row at once". The Draft Overlay
/// (Design Dial, Design Mode) applies through [patchAllRendered]; the commit
/// path applies through [patchSource].
///
/// Loud bails, by design: id not found (exit 3), id found in more than one
/// file (exit 4 — the stamper's uniqueness invariant is broken), the edit is
/// refused in place (exit 5): style is a `{...}` expression rather than a
/// quoted string (merging into an expression needs a JS evaluator, which this
/// deliberately is not), or --text aims at a void element or one wrapping
/// nested markup; or a value containing a double quote (exit 2).
///
/// Transport: the engine writes the file directly here — the CLI is local
/// and the design server's watcher hot-reloads on the write. When the drag
/// overlay lands it posts through /__project_write instead, so the browser
/// side keeps exactly one traversal-safe write path; the locate-and-transform
/// half ([patchSource]) is shared by both.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_stamp.dart' show openingTagEnd;
import 'design_tools.dart' show CmdResult;

/// One structured edit set against one element.
class PatchEdits {
  /// Attribute name → new value; a null value removes the attribute.
  final Map<String, String?> attrs;

  /// CSS property → new value; a null value removes the property.
  final Map<String, String?> style;

  /// Replacement text content; null leaves the content alone. Refused when
  /// the element is void or wraps nested markup (loud, never a silent nuke).
  final String? text;

  const PatchEdits(
      {this.attrs = const {}, this.style = const {}, this.text});

  bool get isEmpty => attrs.isEmpty && style.isEmpty && text == null;
}

/// Outcome of patching one source text.
class PatchResult {
  /// The patched source (identical to the input when [found] is false).
  final String code;

  /// Whether the id was found and the edits applied.
  final bool found;

  /// Set when the target was found but an edit could not be applied
  /// (a `{...}` style expression, or a refused text edit).
  final String? error;

  /// How many occurrences were patched — always 1 from [patchSource] (its
  /// uniqueness law), N from [patchAllRendered] (loop-shared ids).
  final int applied;

  /// Scan cursor for the [patchAllRendered] loop: the position just past the
  /// patched tag's `>` in [code], where the next occurrence search resumes.
  /// Null when nothing was found or the edit was refused.
  final int? nextFrom;

  const PatchResult(this.code,
      {this.found = true, this.error, this.applied = 1, this.nextFrom});
}

final _wsRe = RegExp(r'\s');

/// Apply [edits] to the element carrying [id] in [src]. Pure. The SOURCE
/// applicator: the stamper's uniqueness invariant holds in source, so a
/// duplicate marker is a loud bail, never a patch-both. [attr] selects the
/// identity layer: the default machine identity, or 'data-el' for the
/// authored-semantic targeting the dial switches to when one machine id
/// fans out over heterogeneous authored meanings (amended 2026-08-24:
/// authored identity wins on divergence).
PatchResult patchSource(String src, String id, PatchEdits edits,
    {String attr = 'data-arxa-id'}) {
  final marker = '$attr="$id"';
  final at = src.indexOf(marker);
  if (at < 0) return PatchResult(src, found: false);
  if (src.indexOf(marker, at + 1) >= 0) {
    return PatchResult(src,
        found: false, error: '$attr "$id" appears twice in one source');
  }
  return _patchAt(src, id, at, edits);
}

/// The RENDERED-markup applicator. Loop-rendered instances share one source
/// element's id by design (design_stamp.dart), so EVERY occurrence is
/// patched — that is what patching the source element means. A refusal stops
/// the loop and reports how many instances were already patched.
PatchResult patchAllRendered(String html, String id, PatchEdits edits,
    {String attr = 'data-arxa-id', int? onlyNth}) {
  final marker = '$attr="$id"';
  var out = html;
  var applied = 0;
  var seen = 0;
  var from = 0;
  while (true) {
    final at = out.indexOf(marker, from);
    if (at < 0) {
      return applied == 0 && seen == 0
          ? PatchResult(out, found: false, applied: 0)
          : PatchResult(out, applied: applied);
    }
    final mine = seen++;
    if (onlyNth != null && mine != onlyNth) {
      // Instance-scoped text (seed-backed rows): measure past this
      // occurrence without touching it — an empty edit set is a no-op
      // transform that still yields the scan cursor.
      final probe = _patchAt(out, id, at, const PatchEdits());
      from = probe.nextFrom ?? at + marker.length;
      continue;
    }
    final r = _patchAt(out, id, at, edits);
    if (r.error != null) {
      return PatchResult(r.code,
          found: applied > 0 || mine > 0, error: r.error, applied: applied);
    }
    out = r.code;
    applied++;
    from = r.nextFrom!;
  }
}

/// Void elements never carry text content — a --text aimed at one refuses.
const _voidTags = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img',
  'input', 'link', 'meta', 'source', 'track', 'wbr',
};

/// Text content crossing the markup boundary: the three markup-significant
/// characters, ampersand first so the escapes themselves survive.
String _escapeText(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// The one-occurrence transform both applicators share: [at] is the index of
/// the marker `data-arxa-id="$id"` in [src]. Pure.
PatchResult _patchAt(String src, String id, int at, PatchEdits edits) {
  // Walk back to the `<` that opens the tag holding the marker. Attribute
  // expressions can contain `<` (a < b), so candidates are validated: the
  // right one is a lowercase tag whose extent CONTAINS the marker.
  var lt = src.lastIndexOf('<', at);
  var nameEnd = -1, tagEnd = -1;
  while (lt >= 0) {
    if (lt + 1 < src.length) {
      final c = src.codeUnitAt(lt + 1);
      if (c >= 97 && c <= 122) {
        var j = lt + 1;
        while (j < src.length &&
            ((src.codeUnitAt(j) >= 97 && src.codeUnitAt(j) <= 122) ||
                (src.codeUnitAt(j) >= 65 &&
                    src.codeUnitAt(j) <= 90) || // camelCase svg continuation
                (src.codeUnitAt(j) >= 48 && src.codeUnitAt(j) <= 57) ||
                src.codeUnitAt(j) == 45)) {
          j++;
        }
        final end = openingTagEnd(src, j);
        if (end > at) {
          nameEnd = j;
          tagEnd = end;
          break;
        }
      }
    }
    lt = src.lastIndexOf('<', lt - 1);
  }
  if (tagEnd < 0) {
    return PatchResult(src,
        found: false, error: 'id "$id" is not inside a host element tag');
  }

  var tag = src.substring(nameEnd, tagEnd); // attribute region of the open tag

  // ── attribute edits ──
  for (final e in edits.attrs.entries) {
    if (e.key.contains(_wsRe) || e.key.contains('=')) {
      return PatchResult(src, error: 'bad attribute name "${e.key}"');
    }
    if (e.value != null && e.value!.contains('"')) {
      return PatchResult(src,
          error: 'value for "${e.key}" contains a double quote');
    }
    final attrRe = RegExp(
        '\\s${e.key}\\s*=\\s*("[^"]*"|' "'" '[^' "'" ']*' "'" '|\\{[^{}]*\\})');
    if (e.value == null) {
      tag = tag.replaceFirst(attrRe, '');
    } else if (attrRe.hasMatch(tag)) {
      tag = tag.replaceFirstMapped(
          attrRe, (m) => '${m[0]!.substring(0, 1)}${e.key}="${e.value}"');
    } else {
      tag = ' ${e.key}="${e.value}"$tag';
    }
  }

  // ── style merges ──
  if (edits.style.isNotEmpty) {
    final styleRe = RegExp('\\sstyle\\s*=\\s*"([^"]*)"');
    final exprRe = RegExp('\\sstyle\\s*=\\s*\\{');
    if (exprRe.hasMatch(tag)) {
      return PatchResult(src,
          error: 'style on "$id" is a {...} expression — '
              'structured style merges need a quoted style attribute');
    }
    final props = <String, String>{};
    final order = <String>[];
    final m = styleRe.firstMatch(tag);
    if (m != null) {
      for (final decl in m.group(1)!.split(';')) {
        final colon = decl.indexOf(':');
        if (colon < 0) continue;
        final prop = decl.substring(0, colon).trim();
        final val = decl.substring(colon + 1).trim();
        if (prop.isEmpty) continue;
        if (!props.containsKey(prop)) order.add(prop);
        props[prop] = val;
      }
    }
    for (final e in edits.style.entries) {
      if (e.value == null) {
        props.remove(e.key);
        order.remove(e.key);
      } else {
        if (!props.containsKey(e.key)) order.add(e.key);
        props[e.key] = e.value!;
      }
    }
    final merged = order.map((k) => '$k: ${props[k]}').join('; ');
    if (m != null) {
      tag = order.isEmpty
          ? tag.replaceFirst(styleRe, '')
          : tag.replaceFirst(styleRe, ' style="$merged"');
    } else if (order.isNotEmpty) {
      tag = ' style="$merged"$tag';
    }
  }

  var out = '${src.substring(0, nameEnd)}$tag${src.substring(tagEnd)}';
  final gt = nameEnd + tag.length; // index of the tag's '>' in out

  // ── text replacement ──
  if (edits.text != null) {
    final name = src.substring(lt + 1, nameEnd);
    if (_voidTags.contains(name) || src.substring(tagEnd - 1, tagEnd) == '/') {
      return PatchResult(src,
          error: '--text on "$id": "$name" is a void element — '
              'it carries no text content');
    }
    // Find the matching close tag, tracking same-name nesting; a self-closed
    // same-name child adds no depth.
    final closeRe = RegExp('</?$name[\\s>]');
    var depth = 1;
    int? closeStart;
    for (final m in closeRe.allMatches(out, gt + 1)) {
      if (out.codeUnitAt(m.start + 1) == 47) {
        depth--;
        if (depth == 0) {
          closeStart = m.start;
          break;
        }
      } else {
        final end = out.indexOf('>', m.start);
        if (end < 0 || out.codeUnitAt(end - 1) != 47) depth++;
      }
    }
    if (closeStart == null) {
      return PatchResult(src,
          error: '--text on "$id": no closing </$name> found');
    }
    final inner = out.substring(gt + 1, closeStart);
    if (RegExp('<[a-zA-Z!]').hasMatch(inner)) {
      return PatchResult(src,
          error: '--text refused: "$id" wraps nested markup — '
              'edit its leaves instead');
    }
    out = '${out.substring(0, gt + 1)}${_escapeText(edits.text!)}'
        '${out.substring(closeStart)}';
  }

  return PatchResult(out, nextFrom: gt + 1);
}

/// The inner content of the element carrying [attr]="[id]" in [src], or
/// null when the element cannot be located. Raw - may be a JSX expression.
String? _innerOf(String src, String id, String attr) {
  final at = src.indexOf('$attr="$id"');
  if (at < 0) return null;
  final seg = src.substring(0, at + 1);
  var lt = seg.lastIndexOf('<');
  while (lt >= 0) {
    final m = RegExp(r'<([a-zA-Z][a-zA-Z0-9-]*)').firstMatch(seg.substring(lt));
    if (m != null && !seg.substring(lt, at + 1).contains('>')) {
      final name = m.group(1)!;
      final close = src.indexOf('</' + name + '>', at);
      if (close < 0) return null;
      return src.substring(src.indexOf('>', lt) + 1, close);
    }
    lt = seg.lastIndexOf('<', lt - 1);
  }
  return null;
}

/// Routes a --text op whose target element is t()-backed into the l10n ARB
/// files - THE SSOT for every localized string. Returns null when [f] does
/// not carry the marker (caller tries other files).
CmdResult? routeTextToArbForFile(
    File f, Directory dir, String id, String attr, String text) {
  final src = f.readAsStringSync();
  final at = src.indexOf('$attr="$id"');
  if (at < 0) return null;
  final inner = _innerOf(src, id, attr);
  if (inner == null) return null;
  final trimmed = inner.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return null;
  final body = trimmed.substring(1, trimmed.length - 1).trim();
  // {t('key')} | {t("key")} - optionally a trailing comma inside the call.
  // Manual scan: a regex here would need quote-class juggling this file
  // is better off without.
  String? key;
  if (body.startsWith('t(') && body.endsWith(')')) {
    var args = body.substring(2, body.length - 1).trim();
    if (args.endsWith(',')) args = args.substring(0, args.length - 1).trim();
    if (args.length >= 2) {
      final q = args[0];
      if ((q == "'" || q == '"') && args.endsWith(q)) {
        final cand = args.substring(1, args.length - 1);
        if (!cand.contains(q) &&
            RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(cand)) {
          key = cand;
        }
      }
    }
  }
  if (key == null) {
    // Brace-wrapped but not a recognized t() call: a data-binding the
    // grammar must not overwrite with one locale's literal.
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text refused: "$id" is expression-backed '
          '("$trimmed") - its text lives in a data source (l10n ARB, seed '
          'fixtures), not as a literal here'
    ]);
  }
  final arbDir = Directory(p.join(dir.path, 'l10n'));
  if (!arbDir.existsSync()) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: "$id" reads t($key) but no l10n/ directory '
          'exists under ' + dir.path
    ]);
  }
  final valueRe = RegExp('"' + RegExp.escape(key) + '"[\\s]*:[\\s]*"(?:[^"\\\\]|\\\\.)*"');
  final newValue = '"' + key + '": "' + text.replaceAll('"', r'\"') + '"';
  var updated = 0;
  final missing = <String>[];
  for (final arb in arbDir.listSync().whereType<File>()) {
    if (!arb.path.endsWith('.arb')) continue;
    final arbSrc = arb.readAsStringSync();
    if (!valueRe.hasMatch(arbSrc)) {
      missing.add(p.basename(arb.path));
      continue;
    }
    arb.writeAsStringSync(arbSrc.replaceFirst(valueRe, newValue));
    updated++;
  }
  if (missing.isNotEmpty) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: key "$key" missing in: ' + missing.join(', ') +
          ' - add it there and retry'
    ]);
  }
  final rel = p.split(p.relative(f.path, from: dir.path)).join('/');
  return CmdResult(0, stdoutLines: [
    'routed $id -> l10n key "$key" ($updated locale(s) updated); '
        '$rel left untouched (t()-binding preserved)'
  ]);
}

// ══ SEED SSOT ROUTING (2026-08-24) ═══════════════════════════════════════
//
// A --text aimed at an element whose source content is a dotted data
// binding ({project.name}) must land in the model spine's SEED files — the
// SSOT the fixtures are generated from — never as a tsx literal (destroying
// the binding) and never in a fixture alone (derived cache; the repository
// header's own law: edit the seed, keep the fixtures in sync). Every locale
// seed AND its fixture are updated with one surgical byte-span replacement
// each, so the diff stays minimal and the binding stays intact.
//
// Resolution is anchored, never guessed:
//   hint — the binding's last identifier ('name') must equal the JSON key
//   was  — the instance's pre-edit text must equal the value in some
//          locale (whitespace-collapsed comparison)
//   page — when several paths match, candidates whose enclosing slug/
//          href occurs in the edited page's pathname survive
//   nth  — when survivors sit under ONE shared array parent, the ordinal
//          under that parent must equal the edited instance's index
// Fewer or more than exactly one survivor is a loud exit 5 listing what
// was seen: a wrong-path write would be silent data corruption, which
// this grammar never does.

/// One locale slice of a model spine: `<stem>_seed.<locale>.json` plus its
/// generated `<stem>_fixtures.<locale>.json` sibling.
class _SeedPair {
  final String stem;
  final String locale;
  final File seed;
  final File fixtures;
  const _SeedPair(this.stem, this.locale, this.seed, this.fixtures);
}

final _seedNameRe = RegExp('^([A-Za-z0-9_-]+)_seed\\.([a-z]{2})\\.json');

/// Discover every `<stem>_seed.<locale>.json` under <dir>/models that has
/// its generated fixtures sibling.
List<_SeedPair> _discoverSeedPairs(Directory dir) {
  final models = Directory(p.join(dir.path, 'models'));
  if (!models.existsSync()) return const [];
  final out = <_SeedPair>[];
  for (final f in models.listSync(recursive: true).whereType<File>()) {
    final m = _seedNameRe.firstMatch(p.basename(f.path));
    if (m == null) continue;
    final fx = File(p.join(
        f.parent.path, m.group(1)! + '_fixtures.' + m.group(2)! + '.json'));
    if (!fx.existsSync()) continue;
    out.add(_SeedPair(m.group(1)!, m.group(2)!, f, fx));
  }
  return out;
}

/// The routable shape of an expression-backed inner: '{project.name}' →
/// 'name'. Ternaries, calls, templates and subscripts are NOT safely
/// routable — null sends the op down the legacy expression-refusal path.
String? _seedHintOf(String trimmedInner) {
  if (!trimmedInner.startsWith('{') || !trimmedInner.endsWith('}')) {
    return null;
  }
  final body = trimmedInner.substring(1, trimmedInner.length - 1).trim();
  final m = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*'
          r'(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*$')
      .firstMatch(body);
  if (m == null) return null;
  return body.split('.').last;
}

final _wsRunRe = RegExp(r'\s+');

/// Whitespace-collapsed comparison form for value anchoring.
String _normText(String s) => s.replaceAll(_wsRunRe, ' ').trim();

/// Every string leaf path of a decoded JSON document, segments joined
/// with '.' (array indices as their decimal string).
void _walkJsonStrings(
    Object? node, List<String> pre, void Function(List<String>, String) emit) {
  if (node is Map) {
    node.forEach((k, v) => _walkJsonStrings(v, [...pre, '$k'], emit));
  } else if (node is List) {
    for (var i2 = 0; i2 < node.length; i2++) {
      _walkJsonStrings(node[i2], [...pre, '$i2'], emit);
    }
  } else if (node is String) {
    emit(pre, node);
  }
}

/// Byte span (content start, content end) of the JSON string value at
/// [segs], found with a minimal escape-aware scanner — everything outside
/// the span stays verbatim, so the written diff is surgical. Null when the
/// path is missing, malformed, or its value is not a string.
(int, int)? _findJsonStringSpan(String src, List<String> segs) {
  var i = 0;
  (int, int, int)? stringSpan(int at) {
    if (at >= src.length || src[at] != '"') return null;
    var j = at + 1;
    while (j < src.length) {
      final c = src.codeUnitAt(j);
      if (c == 92) { j += 2; continue; } // backslash escape
      if (c == 34) return (at + 1, j, j + 1);
      j++;
    }
    return null;
  }
  void ws() {
    while (i < src.length) {
      final c = src.codeUnitAt(i);
      if (c == 32 || c == 9 || c == 10 || c == 13) { i++; } else { break; }
    }
  }
  (int, int)? span;
  int? parseValue(List<String>? want) {
    ws();
    if (i >= src.length) return null;
    final c = src[i];
    if (c == '"') {
      final s3 = stringSpan(i);
      if (s3 == null) return null;
      if (want != null && want.isEmpty) span = (s3.$1, s3.$2);
      i = s3.$3;
      return i;
    }
    if (c == '{') {
      i++;
      ws();
      if (i < src.length && src[i] == '}') { i++; return i; }
      while (true) {
        ws();
        final ks = stringSpan(i);
        if (ks == null) return null;
        final key = src.substring(ks.$1, ks.$2);
        i = ks.$3;
        ws();
        if (i >= src.length || src[i] != ':') return null;
        i++;
        final childWant = want != null && want.isNotEmpty && want.first == key
            ? want.sublist(1)
            : null;
        if (parseValue(childWant) == null) return null;
        ws();
        if (i >= src.length) return null;
        if (src[i] == ',') { i++; continue; }
        if (src[i] == '}') { i++; return i; }
        return null;
      }
    }
    if (c == '[') {
      i++;
      var idx = 0;
      ws();
      if (i < src.length && src[i] == ']') { i++; return i; }
      while (true) {
        final childWant = want != null && want.isNotEmpty &&
                int.tryParse(want.first) == idx
            ? want.sublist(1)
            : null;
        if (parseValue(childWant) == null) return null;
        idx++;
        ws();
        if (i >= src.length) return null;
        if (src[i] == ',') { i++; continue; }
        if (src[i] == ']') { i++; return i; }
        return null;
      }
    }
    // number / true / false / null literal — the target is never here
    final st = i;
    while (i < src.length && !',}] \t\r\n '.contains(src[i])) {
      i++;
    }
    if (want != null && want.isEmpty) return null;
    return i > st ? i : null;
  }
  parseValue(segs);
  return span;
}

/// JSON-escape [s] for splicing between two quotes (content only).
String _jsonEscape(String s) {
  final b = StringBuffer();
  for (final c in s.codeUnits) {
    if (c == 34) { b.write(r'\"'); }
    else if (c == 92) { b.write(r'\\'); }
    else if (c == 10) { b.write(r'\n'); }
    else if (c == 13) { b.write(r'\r'); }
    else if (c == 9) { b.write(r'\t'); }
    else if (c < 32) { b.write('\\u' + c.toRadixString(16).padLeft(4, '0')); }
    else { b.writeCharCode(c); }
  }
  return b.toString();
}

/// Routes a --text op whose target element's source content is a dotted
/// data binding into the seed/fixtures spine. Returns null when this file
/// does not carry the marker, the binding is not routable, or the artifact
/// has no seed spine (caller falls through to the legacy paths).
CmdResult? routeTextToSeed(
    Directory dir,
    File hit,
    String id,
    String attr,
    String text,
    {String? was, int? nth, String? page}) {
  final src = hit.readAsStringSync();
  if (!src.contains('$attr="$id"')) return null;
  final hint = _seedHintOf(_innerOf(src, id, attr)?.trim() ?? '');
  if (hint == null) return null;
  final pairs = _discoverSeedPairs(dir);
  if (pairs.isEmpty) return null;

  final byStem = <String, Map<String, _SeedPair>>{};
  for (final sp in pairs) {
    byStem.putIfAbsent(sp.stem, () => {})[sp.locale] = sp;
  }

  // Survivors: (stem, seed path segments).
  final resolved = <(String, List<String>)>[];
  final seen = <String>[];

  for (final stem in byStem.keys.toList()..sort()) {
    final locs = byStem[stem]!;
    final locales = locs.keys.toList()..sort();
    final values = <String, Map<String, String>>{};
    Set<String>? common;
    for (final loc in locales) {
      final vals = <String, String>{};
      _walkJsonStrings(jsonDecode(locs[loc]!.seed.readAsStringSync()), const [],
          (path, v) => vals[path.join('.')] = v);
      values[loc] = vals;
      final ks = vals.keys.toSet();
      common = common == null ? ks : common.intersection(ks).toSet();
    }
    var keep = <List<String>>[];
    for (final path in (common ?? const <String>{})) {
      final segs = path.split('.');
      if (segs.last != hint) continue;
      if (was != null && was.isNotEmpty) {
        var anchored = false;
        for (final loc in locales) {
          if (_normText(values[loc]![path] ?? '') == _normText(was)) {
            anchored = true;
          }
        }
        if (!anchored) continue;
      } else if (nth == null) {
        continue; // no anchor at all — refusing to guess
      }
      keep.add(segs);
    }

    // Slug correlation: the edited page's pathname names its project.
    if (keep.length > 1 && page != null && page.isNotEmpty) {
      bool pageHit(List<String> segs) {
        for (var i2 = segs.length - 2; i2 >= 0; i2--) {
          if (int.tryParse(segs[i2]) == null) continue;
          final root = segs.sublist(0, i2 + 1);
          for (final loc in locales) {
            final v = values[loc]!;
            final slug = v[[...root, 'slug'].join('.')];
            final href = v[[...root, 'href'].join('.')];
            if (slug != null && slug.isNotEmpty && page.contains(slug)) {
              return true;
            }
            if (href != null && href.isNotEmpty && page.contains(href)) {
              return true;
            }
          }
        }
        return false;
      }
      final narrowed = keep.where(pageHit).toList();
      if (narrowed.isNotEmpty) keep = narrowed;
    }

    // Ordinal tiebreak: survivors share one array parent and exactly one
    // sits at the edited instance's index.
    if (keep.length > 1 && nth != null) {
      (String, int)? split(List<String> s) {
        for (var i2 = s.length - 1; i2 >= 0; i2--) {
          final n2 = int.tryParse(s[i2]);
          if (n2 != null) return (s.sublist(0, i2).join('.'), n2);
        }
        return null;
      }
      final splits = keep.map(split).toList();
      if (splits.every((x) => x != null) &&
          splits.map((x) => x!.$1).toSet().length == 1) {
        final pick = <List<String>>[];
        for (var k = 0; k < keep.length; k++) {
          if (splits[k]!.$2 == nth) pick.add(keep[k]);
        }
        if (pick.length == 1) keep = pick;
      }
    }

    for (final s in keep) {
      resolved.add((stem, s));
      if (seen.length < 8) {
        var en = values[locales.first]![s.join('.')] ?? '';
        if (en.length > 48) en = en.substring(0, 48) + '…';
        seen.add(stem + '_seed ' + s.join('.') + ' :: ' + en);
      }
    }
  }

  if (resolved.isEmpty) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text refused: "$id" reads seed data ' +
          '(binding ends in "$hint") but no seed path matched' +
          (was == null || was.isEmpty
              ? ' — pass --was <previous text> to anchor the value'
              : ' (stale anchor?)'),
      ...seen.isEmpty ? const ['  no candidates — draft and seed have diverged'] : seen,
    ]);
  }
  if (resolved.length > 1) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text ambiguous for "$id" — ' +
          resolved.length.toString() + ' seed paths match:',
      ...seen,
      'disambiguate with --page <pathname> and/or --nth <instance index>',
    ]);
  }

  final (stem, segs) = resolved.single;
  final locs = byStem[stem]!;
  final touched = <String>[];
  for (final loc in locs.keys.toList()..sort()) {
    final sp = locs[loc]!;
    final seedDoc = jsonDecode(sp.seed.readAsStringSync());
    final fixDoc = jsonDecode(sp.fixtures.readAsStringSync());
    // Fixture wrapper: a derived map over the seed's bare array gets the
    // seed path prefixed with its single root key ('projects').
    final fixSegs = (fixDoc is Map && seedDoc is! Map)
        ? [fixDoc.keys.first.toString(), ...segs]
        : segs;
    final targets = [(sp.seed, segs), (sp.fixtures, fixSegs)];
    for (final (file, pathSegs) in targets) {
      final before = file.readAsStringSync();
      final span = _findJsonStringSpan(before, pathSegs);
      if (span == null) {
        return CmdResult(5, stderrLines: [
          'appbox design patch: seed path "${segs.join(".")}" missing or not a ' +
              'string in ${p.relative(file.path, from: dir.path)}'
        ]);
      }
      final after = before.substring(0, span.$1) +
          _jsonEscape(text) +
          before.substring(span.$2);
      file.writeAsStringSync(after);
      touched.add(p.relative(file.path, from: dir.path));
    }
  }
  final locNames = locs.keys.toList()..sort();
  return CmdResult(0, stdoutLines: [
    'routed $id -> ' + stem + '_seed.' + segs.join('.') +
        ' (' + locNames.join(', ') + ') — ' +
        touched.length.toString() + ' file(s), tsx binding untouched',
  ]);
}


/// `appbox design patch <artifactDir> <id> [--set n=v]… [--rm n]…`
/// `[--style p=v]… [--rm-style p]…`
CmdResult patchMain(List<String> args) {
  final positional = <String>[];
  final attrs = <String, String?>{};
  final style = <String, String?>{};
  String? text;
  String? was;
  int? nth;
  String? page;
  String? elTarget;
  String? usageError;
  final tokens = <String, String?>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? take() => ++i < args.length ? args[i] : null;
    if (a == '--set') {
      final v = take();
      final eq = v?.indexOf('=') ?? -1;
      if (eq < 1) usageError = '--set needs name=value';
      if (eq >= 1) attrs[v!.substring(0, eq)] = v.substring(eq + 1);
    } else if (a == '--rm') {
      final v = take();
      if (v == null) usageError = '--rm needs a name';
      if (v != null) attrs[v] = null;
    } else if (a == '--style') {
      final v = take();
      final eq = v?.indexOf('=') ?? -1;
      if (eq < 1) usageError = '--style needs prop=value';
      if (eq >= 1) style[v!.substring(0, eq)] = v.substring(eq + 1);
    } else if (a == '--rm-style') {
      final v = take();
      if (v == null) usageError = '--rm-style needs a prop';
      if (v != null) style[v] = null;
    } else if (a == '--text') {
      final v = take();
      if (v == null) usageError = '--text needs a value';
      if (v != null) text = v;
    } else if (a == '--el') {
      final v = take();
      if (v == null) usageError = '--el needs a data-el value';
      if (v != null) elTarget = v;
    } else if (a == '--token') {
      final v = take();
      final eq = v?.indexOf('=') ?? -1;
      if (eq < 1) usageError = '--token needs name=value';
      if (eq >= 1) tokens[v!.substring(0, eq)] = v.substring(eq + 1);
    } else if (a == '--rm-token') {
      final v = take();
      if (v == null) usageError = '--rm-token needs a name';
      if (v != null) tokens[v] = null;
    } else if (a == '--was') {
      final v = take();
      if (v == null) usageError = '--was needs a value';
      if (v != null) was = v;
    } else if (a == '--nth') {
      final v = take();
      final n2 = v == null ? null : int.tryParse(v);
      if (n2 == null || n2 < 0) usageError = '--nth needs a 0-based index';
      if (n2 != null && n2 >= 0) nth = n2;
    } else if (a == '--page') {
      final v = take();
      if (v == null) usageError = '--page needs a pathname';
      if (v != null) page = v;
    } else if (a.startsWith('--')) {
      usageError = 'unknown flag $a';
    } else {
      positional.add(a);
    }
  }
  if (text == null && (was != null || nth != null || page != null)) {
    usageError ??= '--was/--nth/--page ride --text';
  }
  final edits = PatchEdits(attrs: attrs, style: style, text: text);
  final tokenOnly = tokens.isNotEmpty &&
      attrs.isEmpty && style.isEmpty && text == null && elTarget == null;
  if (usageError != null ||
      (elTarget == null && !tokenOnly && positional.length != 2) ||
      (elTarget != null && positional.length != 1) ||
      (edits.isEmpty && !tokenOnly)) {
    return CmdResult(2, stderrLines: [
      ?usageError,
      'usage: appbox design patch <artifactDir> <data-arxa-id> '
          '[--set name=value]… [--rm name]… [--style prop=value]… '
          '[--rm-style prop]… [--text value] [--was prev] [--nth i] '
          '[--page pathname]\n'
          '       appbox design patch <artifactDir> --el <data-el> '
          '[same flags] — authored-identity targeting (divergence law)'
    ]);
  }
  final dir = Directory(positional[0]);
  if (!dir.existsSync()) {
    return CmdResult(2,
        stderrLines: ['appbox design patch: no such dir: ${positional[0]}']);
  }
  // ── TOKEN SSOT (2026-08-24): token ops land in the base :root of
  // ui/styles/common/tokens.css — media-query redefinitions stay alone.
  // Works with or without an element target: tokens are document-level.
  if (tokens.isNotEmpty) {
    final candidates = [
      p.join(dir.path, 'ui', 'styles', 'common', 'tokens.css'),
    ];
    File? css;
    for (final c in candidates) {
      if (File(c).existsSync()) { css = File(c); break; }
    }
    css ??= dir
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.css') &&
            f.readAsStringSync().contains(':root'), orElse: () => null as File);
    if (css == null) {
      return CmdResult(5, stderrLines: [
        'appbox design patch: no tokens.css / :root stylesheet found under '
            '${dir.path}'
      ]);
    }
    var cssSrc = css.readAsStringSync();
    final rootAt = cssSrc.indexOf(':root');
    final braceAt = cssSrc.indexOf('{', rootAt);
    final closeAt = cssSrc.indexOf('}', braceAt);
    var block = cssSrc.substring(braceAt + 1, closeAt);
    var touched = 0;
    for (final t in tokens.entries) {
      final name = t.key.startsWith('--') ? t.key : '--' + t.key;
      final lineRe = RegExp('$name\\s*:[^;]*;');
      if (t.value == null) {
        block = block.replaceFirstMapped(lineRe, (_) => '');
      } else if (lineRe.hasMatch(block)) {
        block = block.replaceFirst(lineRe, '$name: ${t.value};');
      } else {
        block = '\n  $name: ${t.value};' + block;
      }
      touched++;
    }
    css.writeAsStringSync(
        cssSrc.substring(0, braceAt + 1) + block + cssSrc.substring(closeAt));
    final rel = p.split(p.relative(css.path, from: dir.path)).join('/');
    return CmdResult(0, stdoutLines: [
      'routed $touched token op(s) -> $rel (base :root)'
    ]);
  }
  final id = elTarget ?? positional[1];
  final attr = elTarget != null ? 'data-el' : 'data-arxa-id';
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.tsx'));
  final hits = <File>[];
  for (final f in files) {
    final src = f.readAsStringSync();
    if (!src.contains('$attr="$id"')) continue;
    hits.add(f);
  }
  if (hits.isEmpty) {
    return CmdResult(3, stderrLines: [
      'appbox design patch: no element carries $attr="$id" '
          'under ${positional[0]}'
    ]);
  }
  if (hits.length > 1) {
    return CmdResult(4, stderrLines: [
      'appbox design patch: id "$id" found in ${hits.length} files '
          '(stamper invariant broken): ${hits.map((f) => f.path).join(', ')}'
    ]);
  }
  // SSOT ROUTING (2026-08-24): a --text aimed at an element whose content
  // is {t('key')} must land in the l10n ARB files - the key IS the SSOT.
  // Rewriting the expression with one locale's literal would silently
  // destroy the i18n binding; refusing would block every rebrand.
  if (edits.text != null) {
    // Seed SSOT route runs FIRST (2026-08-24): a dotted data binding lands
    // in the model spine's seed files — every locale's seed AND its
    // generated fixture. Null = no seed spine here or the binding is not
    // routable; the ARB router and the legacy expression refusal keep
    // covering t()-backed and unsupported shapes.
    final seeded = routeTextToSeed(dir, hits.single, id, attr, edits.text!,
        was: was, nth: nth, page: page);
    if (seeded != null) return seeded;
    for (final f in hits) {
      final routed = routeTextToArbForFile(f, dir, id, attr, edits.text!);
      if (routed != null) return routed;
    }
  }
  final res = patchSource(
      hits.single.readAsStringSync(), id, edits, attr: attr);
  if (res.error != null) {
    return CmdResult(5, stderrLines: ['appbox design patch: ${res.error}']);
  }
  hits.single.writeAsStringSync(res.code);
  final rel = p.split(p.relative(hits.single.path, from: dir.path)).join('/');
  return CmdResult(0, stdoutLines: ['patched $id in $rel']);
}
