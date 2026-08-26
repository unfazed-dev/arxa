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
///   --locale xx           SSOT provenance: write ONLY this locale slice
///                         (seed pair / ARB file). Default: inferred from
///                         --was when exactly one locale holds that value,
///                         else every locale (pre-2026-08-24 law).
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

/// Source sites carrying the authored name= anchor [el] under [dir], as
/// (absolutePath, byteOffset, lineNumber). The single scanner behind
/// patchMain's authored-identity resolution AND the draft surface's parity
/// warnings - preview must never promise what commit will refuse.
List<(String, int, int)> nameSiteLocations(Directory dir, String el) {
  if (!dir.existsSync()) return const [];
  final quoteAlt = String.fromCharCode(34) + String.fromCharCode(39);
  final nameRe = RegExp(r'name\s*=\s*([' + quoteAlt + r'])' +
      RegExp.escape(el) + r'\1');
  final out = <(String, int, int)>[];
  for (final f in dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.tsx'))) {
    final src = f.readAsStringSync();
    for (final m in nameRe.allMatches(src)) {
      final line =
          '\n'.allMatches(src.substring(0, m.start)).length + 1;
      out.add((f.path, m.start, line));
    }
  }
  return out;
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
      // PascalCase components (Box, GlassPanel) host name= anchors -
      // rendered identity is case-blind, so the walk is too.
      if ((c >= 97 && c <= 122) || (c >= 65 && c <= 90)) {
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
    if (lt <= 0) break;
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

/// (contentStart, closeStart) of the element whose OPENING TAG contains
/// position [at] - an identity marker or a name= attribute, both of which
/// sit inside the tag. Null when no enclosing host element closes.
(int, int)? _elementInnerSpan(String src, int at) {
  final seg = src.substring(0, at + 1);
  var lt = seg.lastIndexOf('<');
  while (lt >= 0) {
    final m = RegExp(r'<([a-zA-Z][a-zA-Z0-9-]*)').firstMatch(seg.substring(lt));
    if (m != null && !seg.substring(lt, at + 1).contains('>')) {
      final name = m.group(1)!;
      final close = src.indexOf('</$name>', at);
      if (close < 0) return null;
      return (src.indexOf('>', lt) + 1, close);
    }
    lt = seg.lastIndexOf('<', lt - 1);
  }
  return null;
}

/// The inner content of the element whose opening tag contains [at]. Raw -
/// may be a JSX expression.
String? _innerOfAt(String src, int at) {
  final s = _elementInnerSpan(src, at);
  return s == null ? null : src.substring(s.$1, s.$2);
}

/// Routes a --text op whose target element is t()-backed into the l10n ARB
/// files - THE SSOT for every localized string. Handles both the literal
/// form {t('key')} and dynamic templates like {t(`...place`)} - the latter
/// resolved by CONTENT: --was must equal exactly one ARB value, narrowed by
/// the template static tail. [locale] targets one locale .arb only
/// (2026-08-24); without it a resolvable edit updates every locale, as
/// before. Returns null when the element is not brace-wrapped or not a t()
/// call (caller tries other routes); resolvable-shape failures exit 5.
/// One ARB file's surgical single-key write: only the value's byte span
/// is rebuilt, everything outside stays verbatim. False when the key is
/// absent (the caller decides whether that is fatal).
bool _writeOneArbKey(File arb, String key, String newText) {
  final src2 = arb.readAsStringSync();
  final valueRe = RegExp('"${RegExp.escape(key)}"[\\s]*:[\\s]*"(?:[^"\\\\]|\\\\.)*"');
  final newValue =
      '"$key": "${newText.replaceAll('"', r'\"')}"';
  if (!valueRe.hasMatch(src2)) return false;
  arb.writeAsStringSync(src2.replaceFirst(valueRe, newValue));
  return true;
}

/// Locale inference mirrors the seed route: when [was] equals key [k]'s
/// value in exactly ONE locale file, that locale alone is written - an
/// edit of Polish copy must not stamp Polish text over the English SSOT.
List<File> _inferArbTargets(List<File> arbs, List<File> fallback, String k,
    String? locale, String? was) {
  if (locale != null || was == null || was.isEmpty) return fallback;
  final holding = <File>[];
  for (final arb in arbs) {
    if (!arb.path.endsWith('.arb')) continue;
    final doc = jsonDecode(arb.readAsStringSync());
    if (doc is Map &&
        doc[k] is String &&
        _normText(doc[k] as String) == _normText(was)) {
      holding.add(arb);
    }
  }
  return holding.length == 1 ? holding : fallback;
}

final _arbLocaleRe = RegExp(r'(?:^|[_])([a-z]{2})\.arb$');

String? _arbLocaleOf(String basename) =>
    _arbLocaleRe.firstMatch(basename)?.group(1);

CmdResult? routeTextToArbForFile(
    File f, Directory dir, int at, String id, String text,
    {String? was, String? locale}) {
  final src = f.readAsStringSync();
  final inner = _innerOfAt(src, at);
  if (inner == null) return null;
  final trimmed = inner.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return null;
  final body = trimmed.substring(1, trimmed.length - 1).trim();

  // {t('key')} | {t("key")} - optionally a trailing comma inside the call.
  // Manual scan: a regex here would need quote-class juggling this file
  // is better off without.
  String? key;
  String? tail;
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
      } else if (q == '`' && args.endsWith('`')) {
        // Dynamic template: interpolations are unknowable statically, so
        // the static tail (e.g. '.place' in a key-shaped template) narrows
        // a content match instead of carrying it.
        tail = args
            .substring(1, args.length - 1)
            .split(RegExp(r'\$\{[^{}]*\}'))
            .last;
      }
    }
  }
  if (key == null && tail == null) return null;

  final arbDir = Directory(p.join(dir.path, 'l10n'));
  if (!arbDir.existsSync()) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: "$id" reads t()-backed copy but no l10n/ directory exists under ${dir.path}'
    ]);
  }
  final arbs = arbDir.listSync().whereType<File>().toList()
    ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  var targets = arbs.where((a) => a.path.endsWith('.arb')).toList();
  if (locale != null) {
    final named = targets
        .where((a) => _arbLocaleOf(p.basename(a.path)) == locale)
        .toList();
    if (named.isEmpty) {
      return CmdResult(5, stderrLines: [
        'appbox design patch: no l10n/*.arb file for locale "$locale" (found: ${targets.map((a) => p.basename(a.path)).join(', ')})'
      ]);
    }
    targets = named;
  }

  if (key != null) {
    final wts = _inferArbTargets(arbs, targets, key, locale, was);
    final missing = <String>[];
    for (final arb in wts) {
      if (!_writeOneArbKey(arb, key, text)) {
        missing.add(p.basename(arb.path));
      }
    }
    if (missing.isNotEmpty) {
      return CmdResult(5, stderrLines: [
        'appbox design patch: key "$key" missing in: ${missing.join(', ')} - add it there and retry'
      ]);
    }
    return _arbRouted(id, key, wts.length, f, dir, 'literal');
  }

  // Template path: content anchors. Candidates come from EVERY locale flat
  // string entries (@-metadata excluded); the edited locale is then
  // inferred exactly like the seed route infers it.
  if (was == null || was.isEmpty) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text refused: "$id" reads a dynamic t() '
          'template ("$trimmed") - pass --was <previous text> to anchor '
          'which key it feeds'
    ]);
  }
  final normWas = _normText(was);
  // Key universe from EVERY locale; a key is a candidate when ANY locale
  // holds the --was value (the edited language may be any of them).
  final sample = <String, String>{};
  final hitKeys = <String>{};
  for (final arb in arbs) {
    if (!arb.path.endsWith('.arb')) continue;
    final doc = jsonDecode(arb.readAsStringSync());
    if (doc is! Map) continue;
    doc.forEach((k, v) {
      if (k is String && v is String && !k.startsWith('@')) {
        sample.putIfAbsent(k, () => v);
        if (_normText(v) == normWas) hitKeys.add(k);
      }
    });
  }
  final loose = hitKeys.toList();
  var matchedKeys = loose.toList();
  final t = tail!;
  if (matchedKeys.length > 1 && t.isNotEmpty) {
    // Tail narrows; an empty result means every value match disagrees with
    // the binding shape -> stale anchor, refuse below.
    matchedKeys =
        matchedKeys.where((k) => k.endsWith(t)).toList();
  }
  matchedKeys.sort();
  if (matchedKeys.isEmpty) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text refused: no ARB key matches --was for '
          '"$id"${loose.isEmpty ? ' (stale anchor? draft and l10n have diverged)' : ' ending in "$tail"'}'
    ]);
  }
  if (matchedKeys.length > 1) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text ambiguous for "$id" - '
          '${matchedKeys.length} ARB keys hold that value:',
      ...matchedKeys.take(8).map((k) => '  $k :: ${sample[k]}'),
      'disambiguate with a longer --was (the full rendered sentence)',
    ]);
  }
  final k = matchedKeys.single;
  final wts = _inferArbTargets(arbs, targets, k, locale, was);
  final missing = <String>[];
  for (final arb in wts) {
    if (!_writeOneArbKey(arb, k, text)) missing.add(p.basename(arb.path));
  }
  if (missing.isNotEmpty) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: key "$k" missing in: ${missing.join(', ')} - add it there and retry'
    ]);
  }
  final how = t.isEmpty
      ? 'value match'
      : 'template tail "$t" + value match';
  return _arbRouted(id, k, wts.length, f, dir, how);
}

CmdResult _arbRouted(
    String id, String key, int updated, File f, Directory dir, String how) {
  final rel = p.split(p.relative(f.path, from: dir.path)).join('/');
  return CmdResult(0, stdoutLines: [
    'routed $id -> l10n key "$key" ($how; $updated locale(s) updated); '
        '$rel left untouched (binding preserved)'
  ]);
}

/// Fallback for brace expressions the routers decline - CONDITIONALS.
/// Candidates are BOTH quoted literals and t('key') references inside the
/// element own expression; --was matches a literal verbatim or a key
/// through its ARB value in ANY locale. Exactly one candidate acts: the
/// literal branch splices in place, the t() branch writes its l10n entry
/// (locale-inferred like every route). Zero or several refuse loudly with
/// per-candidate detail. Returns null when the element is not a
/// conditional-shaped expression (the caller emits the generic refusal).
CmdResult? _routeConditional(File hit, Directory dir, int at, String id,
    String was, String text) {
  final src = hit.readAsStringSync();
  final span = _elementInnerSpan(src, at);
  if (span == null) return null;
  final inner = src.substring(span.$1, span.$2);
  final trimmed = inner.trim();
  if (!trimmed.startsWith('{') ||
      !trimmed.endsWith('}') ||
      !trimmed.contains('?')) {
    return null;
  }
  // Quoted literals.
  final bs = String.fromCharCode(92);
  final lits = <(int, int, String)>[];
  var k2 = 0;
  while (k2 < inner.length) {
    final q = inner[k2];
    if (q != "'" && q != '"') {
      k2++;
      continue;
    }
    var e = k2 + 1;
    while (e < inner.length && inner[e] != q) {
      if (inner[e] == bs) e++;
      e++;
    }
    if (e >= inner.length) break; // unterminated - stop scanning
    if (e > k2 + 1) lits.add((k2, e, inner.substring(k2 + 1, e)));
    k2 = e + 1;
  }
  String unq(String raw) => raw
      .replaceAll(bs + bs, bs)
      .replaceAll("$bs'", "'")
      .replaceAll('$bs"', '"');
  final normWas = _normText(was);
  final litHits = was.isEmpty
      ? <(int, int, String)>[]
      : lits
          .where((l) =>
              _normText(l.$3) == normWas ||
              _normText(unq(l.$3)) == normWas)
          .toList();
  // t() references inside the expression. Manual scan: 't(' also ends
  // words like format(), so the preceding char must not be an identifier
  // or member character.
  final keyRefs = <String>[];
  var pos = 0;
  while (true) {
    final at3 = trimmed.indexOf('t(', pos);
    if (at3 < 0) break;
    final prev = at3 == 0 ? ' ' : trimmed[at3 - 1];
    if (!RegExp(r'[A-Za-z0-9_$.]').hasMatch(prev)) {
      var j = at3 + 2;
      while (j < trimmed.length && trimmed[j] == ' ') {
        j++;
      }
      if (j < trimmed.length && (trimmed[j] == "'" || trimmed[j] == '"')) {
        final q3 = trimmed[j];
        final e3 = trimmed.indexOf(q3, j + 1);
        if (e3 > j + 1) {
          final cand = trimmed.substring(j + 1, e3);
          if (RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(cand)) {
            keyRefs.add(cand);
            pos = e3 + 1;
            continue;
          }
        }
      }
    }
    pos = at3 + 2;
  }
  // Which referenced keys hold the --was value in ANY locale?
  var keyHits = <String>[];
  if (keyRefs.isNotEmpty && was.isNotEmpty) {
    final arbDir = Directory(p.join(dir.path, 'l10n'));
    if (arbDir.existsSync()) {
      // Any-locale semantics: a key matches when ANY locale holds the
      // --was value - first-locale-wins would miss the edited language.
      final vals = <String, Set<String>>{};
      for (final arb in arbDir.listSync().whereType<File>()) {
        if (!arb.path.endsWith('.arb')) continue;
        final doc = jsonDecode(arb.readAsStringSync());
        if (doc is! Map) continue;
        doc.forEach((k, v) {
          if (k is String && v is String && keyRefs.contains(k)) {
            (vals[k] ??= <String>{}).add(v);
          }
        });
      }
      keyHits = keyRefs
          .where((k) =>
              vals.containsKey(k) &&
              vals[k]!.any((v) => _normText(v) == normWas))
          .toList();
    }
  }
  final total = litHits.length + keyHits.length;
  if (total == 0) {
    if (was.isEmpty) {
      return CmdResult(5, stderrLines: [
        'appbox design patch: --text refused: "$id" is a conditional '
            'expression - pass --was <branch text> to pick the branch'
      ]);
    }
    final clip =
        trimmed.length > 72 ? '${trimmed.substring(0, 72)}...' : trimmed;
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text refused: the conditional on "$id" has '
          'no branch matching --was ("$clip")'
    ]);
  }
  if (total > 1) {
    final parts = <String>[
      for (final l in litHits) 'branch literal "${unq(l.$3)}"',
      for (final k in keyHits) 'l10n key "$k"',
    ];
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text ambiguous for "$id": $total branches '
          'match --was:',
      ...parts,
    ]);
  }
  if (litHits.isNotEmpty) {
    final m = litHits.single;
    final q = inner[m.$1];
    final escaped = text.replaceAll(bs, bs + bs).split(q).join(bs + q);
    final out = src.substring(0, span.$1 + m.$1) +
        q + escaped + q +
        src.substring(span.$1 + m.$2 + 1);
    hit.writeAsStringSync(out);
    final rel = p.split(p.relative(hit.path, from: dir.path)).join('/');
    final line =
        '\n'.allMatches(src.substring(0, span.$1 + m.$1)).length + 1;
    return CmdResult(0, stdoutLines: [
      'routed $id -> $rel:$line conditional branch - expression structure '
          'preserved'
    ]);
  }
  // Single t() branch: the ARB SSOT write, locale-inferred like every
  // other route.
  final k = keyHits.single;
  final arbDir = Directory(p.join(dir.path, 'l10n'));
  final arbs = arbDir.listSync().whereType<File>().toList()
    ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  final targets = arbs.where((a) => a.path.endsWith('.arb')).toList();
  final wts = _inferArbTargets(arbs, targets, k, null, was);
  final missing = <String>[];
  for (final arb in wts) {
    if (!_writeOneArbKey(arb, k, text)) missing.add(p.basename(arb.path));
  }
  if (missing.isNotEmpty) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: key "$k" missing in: ${missing.join(', ')} - add it there and retry'
    ]);
  }
  return CmdResult(0, stdoutLines: [
    'routed $id -> l10n key "$k" (conditional branch; ${wts.length} '
        'locale(s) updated) - expression structure preserved'
  ]);
}

// ══ SEED SSOT ROUTING (2026-08-24) ═══════════════════════════════════════
//
// A --text aimed at an element whose source content is a dotted data
// binding ({project.name}) must land in the model spine's SEED files — the
// SSOT the fixtures are generated from — never as a tsx literal (destroying
// the binding) and never in a fixture alone (derived cache; the repository
// header's own law: edit the seed, keep the fixtures in sync). The edited
// locale's seed AND fixture are updated with one surgical byte-span
// replacement each, so the diff stays minimal and the binding stays intact.
// Locale targeting (2026-08-24): an explicit or inferred locale writes ONLY
// that locale pair; an unknowable locale keeps the every-locale law.
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

/// Discover every `<stem>_seed.<locale>.json` under `<dir>/models` that has
/// its generated fixtures sibling.
List<_SeedPair> _discoverSeedPairs(Directory dir) {
  final models = Directory(p.join(dir.path, 'models'));
  if (!models.existsSync()) return const [];
  final out = <_SeedPair>[];
  for (final f in models.listSync(recursive: true).whereType<File>()) {
    final m = _seedNameRe.firstMatch(p.basename(f.path));
    if (m == null) continue;
    final fx = File(p.join(
        f.parent.path, '${m.group(1)!}_fixtures.${m.group(2)!}.json'));
    if (!fx.existsSync()) continue;
    out.add(_SeedPair(m.group(1)!, m.group(2)!, f, fx));
  }
  return out;
}

/// The routable shape of an expression-backed inner: '{project.name}' ->
/// 'name'; subscript spellings normalize first ({row['t']} -> row.t,
/// amended 2026-08-24). Ternaries, calls and templates stay unroutable
/// here - null sends the op to the later routes (template lookup, branch
/// splice, loud refusal).
final _subscriptRe =
    RegExp(r"\[\s*'([^']*)'\s*\]|" r'\[\s*"([^"]*)"\s*\]');

String? _seedHintOf(String trimmedInner) {
  if (!trimmedInner.startsWith('{') || !trimmedInner.endsWith('}')) {
    return null;
  }
  var body = trimmedInner.substring(1, trimmedInner.length - 1).trim();
  body = body.replaceAllMapped(_subscriptRe, (m) => '.${(m[1] ?? m[2])!}');
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
    else if (c < 32) { b.write('\\u${c.toRadixString(16).padLeft(4, '0')}'); }
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
    int at,
    String id,
    String text,
    {String? was, int? nth, String? page, String? locale}) {
  final src = hit.readAsStringSync();
  final hint = _seedHintOf(_innerOfAt(src, at)?.trim() ?? '');
  if (hint == null) return null;
  final pairs = _discoverSeedPairs(dir);
  if (pairs.isEmpty) return null;

  final byStem = <String, Map<String, _SeedPair>>{};
  for (final sp in pairs) {
    byStem.putIfAbsent(sp.stem, () => {})[sp.locale] = sp;
  }
  final stemValues = <String, Map<String, Map<String, String>>>{};

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
    stemValues[stem] = values;

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
        if (en.length > 48) en = '${en.substring(0, 48)}…';
        seen.add('${stem}_seed ${s.join('.')} :: $en');
      }
    }
  }

  if (resolved.isEmpty) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text refused: "$id" reads seed data (binding ends in "$hint") but no seed path matched${was == null || was.isEmpty
              ? ' — pass --was <previous text> to anchor the value'
              : ' (stale anchor?)'}',
      ...seen.isEmpty ? const ['  no candidates — draft and seed have diverged'] : seen,
    ]);
  }
  if (resolved.length > 1) {
    return CmdResult(5, stderrLines: [
      'appbox design patch: --text ambiguous for "$id" — ${resolved.length} seed paths match:',
      ...seen,
      'disambiguate with --page <pathname> and/or --nth <instance index>',
    ]);
  }

  final (stem, segs) = resolved.single;
  final locs = byStem[stem]!;
  final allLocales = locs.keys.toList()..sort();
  var writeLocales = allLocales.toList();
  if (locale != null) {
    if (!locs.containsKey(locale)) {
      return CmdResult(5, stderrLines: [
        'appbox design patch: locale "$locale" has no slice in the "$stem" seed spine (${allLocales.join(', ')})'
      ]);
    }
    writeLocales = [locale];
  } else if (was != null && was.isNotEmpty) {
    // Locale inference (2026-08-24): the pre-edit text matching exactly ONE
    // locale stored value names the language being edited - editing Polish
    // copy no longer stamps that Polish text over every other locale SSOT.
    // Unresolvable (0 or 2+ matches) keeps the older every-locale law.
    final vals = stemValues[stem]!;
    final matching = allLocales
        .where((l) => _normText(vals[l]![segs.join('.')] ?? '') ==
            _normText(was))
        .toList();
    if (matching.length == 1) writeLocales = matching;
  }
  final touched = <String>[];
  for (final loc in writeLocales) {
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
          'appbox design patch: seed path "${segs.join(".")}" missing or not a ' 'string in ${p.relative(file.path, from: dir.path)}'
        ]);
      }
      final after = before.substring(0, span.$1) +
          _jsonEscape(text) +
          before.substring(span.$2);
      file.writeAsStringSync(after);
      touched.add(p.relative(file.path, from: dir.path));
    }
  }
  final others =
      allLocales.where((l) => !writeLocales.contains(l)).toList();
  final scope = writeLocales.join(', ') +
      (others.isEmpty ? '' : '; also in spine: ${others.join(', ')}');
  return CmdResult(0, stdoutLines: [
    'routed $id -> ${stem}_seed.${segs.join('.')} ($scope) - ${touched.length} file(s), tsx binding untouched',
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
  String? locale;
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
    } else if (a == '--locale') {
      final v = take();
      if (v == null || !RegExp(r'^[a-z]{2}$').hasMatch(v)) {
        usageError = '--locale needs a two-letter code';
      }
      if (v != null && RegExp(r'^[a-z]{2}$').hasMatch(v)) locale = v;
    } else if (a.startsWith('--')) {
      usageError = 'unknown flag $a';
    } else {
      positional.add(a);
    }
  }
  if (text == null &&
      (was != null || nth != null || page != null || locale != null)) {
    usageError ??= '--was/--nth/--page/--locale ride --text';
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
          '[--page pathname] [--locale xx]\n'
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
      final name = t.key.startsWith('--') ? t.key : '--${t.key}';
      final lineRe = RegExp('$name\\s*:[^;]*;');
      if (t.value == null) {
        block = block.replaceFirstMapped(lineRe, (_) => '');
      } else if (lineRe.hasMatch(block)) {
        block = block.replaceFirst(lineRe, '$name: ${t.value};');
      } else {
        block = '\n  $name: ${t.value};$block';
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

  // -- Target resolution: the stamp marker first; a --el op with no stamp
  // anywhere falls back to the AUTHORED anchor - the primitives name=
  // attribute that renders as data-el (2026-08-24). Render-time identity
  // becomes source-findable: exactly one name= site is the law; zero or
  // several refuse loudly with locations.
  File? hit;
  var at = -1;
  var nameAnchored = false;
  final stampHits = <File>[];
  for (final f in files) {
    if (f.readAsStringSync().contains('$attr="$id"')) stampHits.add(f);
  }
  if (stampHits.length > 1) {
    return CmdResult(4, stderrLines: [
      'appbox design patch: id "$id" found in ${stampHits.length} files '
          '(stamper invariant broken): '
          '${stampHits.map((f) => f.path).join(', ')}'
    ]);
  }
  if (stampHits.length == 1) {
    hit = stampHits.single;
    final src = hit.readAsStringSync();
    at = src.indexOf('$attr="$id"');
    if (src.indexOf('$attr="$id"', at + 1) >= 0) {
      return CmdResult(4, stderrLines: [
        'appbox design patch: $attr="$id" appears twice in '
            '${p.relative(hit.path, from: dir.path)} (stamper invariant '
            'broken)'
      ]);
    }
  } else if (elTarget != null) {
    final sites = <(File, int, int)>[
      for (final s2 in nameSiteLocations(dir, elTarget!))
        (File(s2.$1), s2.$2, s2.$3),
    ];
    if (sites.isEmpty) {
      return CmdResult(3, stderrLines: [
        'appbox design patch: no element carries data-el="$id" and no '
            'source carries name="$id" under ${positional[0]}'
      ]);
    }
    if (sites.length > 1) {
      final locs = <String>[];
      for (final s2 in sites) {
        locs.add('  ${p.relative(s2.$1.path, from: dir.path)}:${s2.$3}');
      }
      return CmdResult(4, stderrLines: [
        'appbox design patch: authored identity "$id" resolves to '
            '${sites.length} name= sites - refusing to guess:',
        ...locs,
      ]);
    }
    hit = sites.single.$1;
    at = sites.single.$2;
    nameAnchored = true;
  } else {
    return CmdResult(3, stderrLines: [
      'appbox design patch: no element carries $attr="$id" '
          'under ${positional[0]}'
    ]);
  }

  // -- TEXT ROUTES (locale-targeted, 2026-08-24): brace-backed content
  // never becomes a literal. Order: seed spine (dotted/subscript
  // bindings) -> l10n ARB (t() literals and templates) -> conditional-
  // branch splice -> the loud expression refusal. Plain-literal elements
  // fall through to the structured patch below.
  if (edits.text != null) {
    final innerTrim = (_innerOfAt(hit.readAsStringSync(), at) ?? '').trim();
    if (innerTrim.startsWith('{') && innerTrim.endsWith('}')) {
      final seeded = routeTextToSeed(dir, hit, at, id, edits.text!,
          was: was, nth: nth, page: page, locale: locale);
      if (seeded != null) return seeded;
      final routed = routeTextToArbForFile(hit, dir, at, id, edits.text!,
          was: was, locale: locale);
      if (routed != null) return routed;
      if (innerTrim.contains('?')) {
        final branched =
            _routeConditional(hit, dir, at, id, was ?? '', edits.text!);
        if (branched != null) return branched;
      }
      return CmdResult(5, stderrLines: [
        'appbox design patch: --text refused: "$id" is expression-backed '
            '("$innerTrim") - its text lives in a data source (l10n ARB, '
            'seed fixtures), not as a literal here',
        if (innerTrim.contains('?'))
          'conditionals route by --was: a branch literal splices in place; '
              "a branch t('key') writes that l10n entry",
      ]);
    }
  }
  final res = _patchAt(hit.readAsStringSync(), id, at, edits);
  if (res.error != null) {
    return CmdResult(5, stderrLines: ['appbox design patch: ${res.error}']);
  }
  hit.writeAsStringSync(res.code);
  final rel = p.split(p.relative(hit.path, from: dir.path)).join('/');
  return CmdResult(0, stdoutLines: [
    'patched $id${nameAnchored ? ' (name-anchored)' : ''} in $rel'
  ]);
}
