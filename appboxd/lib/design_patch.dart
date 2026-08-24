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
    {String attr = 'data-arxa-id'}) {
  final marker = '$attr="$id"';
  var out = html;
  var applied = 0;
  var from = 0;
  while (true) {
    final at = out.indexOf(marker, from);
    if (at < 0) {
      return applied == 0
          ? PatchResult(out, found: false, applied: 0)
          : PatchResult(out, applied: applied);
    }
    final r = _patchAt(out, id, at, edits);
    if (r.error != null) {
      return PatchResult(r.code,
          found: applied > 0, error: r.error, applied: applied);
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

/// `appbox design patch <artifactDir> <id> [--set n=v]… [--rm n]…`
/// `[--style p=v]… [--rm-style p]…`
CmdResult patchMain(List<String> args) {
  final positional = <String>[];
  final attrs = <String, String?>{};
  final style = <String, String?>{};
  String? text;
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
    } else if (a.startsWith('--')) {
      usageError = 'unknown flag $a';
    } else {
      positional.add(a);
    }
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
          '[--rm-style prop]… [--text value]\n'
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
