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
///
/// Loud bails, by design: id not found (exit 3), id found in more than one
/// file (exit 4 — the stamper's uniqueness invariant is broken), style is a
/// `{...}` expression rather than a quoted string (exit 5 — merging into an
/// expression needs a JS evaluator, which this deliberately is not), or a
/// value containing a double quote (exit 2).
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

  const PatchEdits({this.attrs = const {}, this.style = const {}});

  bool get isEmpty => attrs.isEmpty && style.isEmpty;
}

/// Outcome of patching one source text.
class PatchResult {
  /// The patched source (identical to the input when [found] is false).
  final String code;

  /// Whether the id was found and the edits applied.
  final bool found;

  /// Set when the target was found but an edit could not be applied
  /// (currently: style held a `{...}` expression).
  final String? error;

  const PatchResult(this.code, {this.found = true, this.error});
}

final _wsRe = RegExp(r'\s');

/// Apply [edits] to the element carrying [id] in [src]. Pure.
PatchResult patchSource(String src, String id, PatchEdits edits) {
  final marker = 'data-arxa-id="$id"';
  final at = src.indexOf(marker);
  if (at < 0) return PatchResult(src, found: false);
  if (src.indexOf(marker, at + 1) >= 0) {
    return PatchResult(src,
        found: false, error: 'id "$id" appears twice in one source');
  }

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

  return PatchResult(
      '${src.substring(0, nameEnd)}$tag${src.substring(tagEnd)}');
}

/// `appbox design patch <artifactDir> <id> [--set n=v]… [--rm n]…`
/// `[--style p=v]… [--rm-style p]…`
CmdResult patchMain(List<String> args) {
  final positional = <String>[];
  final attrs = <String, String?>{};
  final style = <String, String?>{};
  String? usageError;
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
    } else if (a.startsWith('--')) {
      usageError = 'unknown flag $a';
    } else {
      positional.add(a);
    }
  }
  final edits = PatchEdits(attrs: attrs, style: style);
  if (usageError != null ||
      positional.length != 2 ||
      edits.isEmpty) {
    return CmdResult(2, stderrLines: [
      ?usageError,
      'usage: appbox design patch <artifactDir> <data-arxa-id> '
          '[--set name=value]… [--rm name]… [--style prop=value]… '
          '[--rm-style prop]…'
    ]);
  }
  final dir = Directory(positional[0]);
  if (!dir.existsSync()) {
    return CmdResult(2,
        stderrLines: ['appbox design patch: no such dir: ${positional[0]}']);
  }
  final id = positional[1];
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.tsx'));
  final hits = <File>[];
  PatchResult? res;
  for (final f in files) {
    final src = f.readAsStringSync();
    if (!src.contains('data-arxa-id="$id"')) continue;
    hits.add(f);
    res = patchSource(src, id, edits);
  }
  if (hits.isEmpty) {
    return CmdResult(3, stderrLines: [
      'appbox design patch: no element carries data-arxa-id="$id" '
          'under ${positional[0]}'
    ]);
  }
  if (hits.length > 1) {
    return CmdResult(4, stderrLines: [
      'appbox design patch: id "$id" found in ${hits.length} files '
          '(stamper invariant broken): ${hits.map((f) => f.path).join(', ')}'
    ]);
  }
  if (res!.error != null) {
    return CmdResult(5, stderrLines: ['appbox design patch: ${res.error}']);
  }
  hits.single.writeAsStringSync(res.code);
  final rel = p.split(p.relative(hits.single.path, from: dir.path)).join('/');
  return CmdResult(0, stdoutLines: ['patched $id in $rel']);
}
