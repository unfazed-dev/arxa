/// Machine-derived semantic annotation — the `data-el` + inspect-metadata
/// layer for artifacts that were authored without it (the energize gap:
/// W7's widget-dir exemption let raw elements pass lint with no identity).
///
/// The law this implements (DESIGN-ARCHITECTURE.md "Inspect metadata",
/// design_tools.dart rule 5): anything interactive or content-bearing carries
/// `data-el` plus `data-inspect-role/style/fn`; the element is the inspect
/// island's source of truth.
///
/// Everything this pass emits is DERIVED, and it says so: every fn carries
/// `data-inspect-fn-provenance="inferred"` — D9's derive + confirm doctrine.
/// A machine cannot write "what it does for the user"; it can only guess from
/// aria-labels, text content, and tag semantics. The inferred marker keeps
/// coverage (how much is annotated) separable from confidence (how much a
/// human confirmed), and the designer's editorial pass confirms or rewrites
/// later. An already-annotated element (data-el or inspectAttrs spread) is
/// NEVER touched — the authored layer outranks the derived one, always.
///
/// Derivation rules (deterministic, in priority order):
///   role  — an explicit role= attribute, else the tag (a→link, button→button,
///           h1-h6→heading, img→media, svg→icon, input/select/textarea→
///           form field, …);
///   label — aria-label, else direct text content (the W7 snippet walk, so
///           expression debris like `))}` never leaks in), else first class
///           token, else the tag;
///   style — the class attribute verbatim (it is the style shorthand a reader
///           gets for free), else the tag;
///   fn    — aria-label if present, else a minimal clause built from role +
///           label. Always marked inferred.
///
/// Scope: elements that are interactive (rule C's regex) OR bear direct text
/// — exactly W7/D7's mandatory set, not every element (annotating every
/// container would flood the inspect readout). Scans widget dirs too: the
/// exemption means identity isn't REQUIRED there, not that it's banned.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_stamp.dart' show openingTagEnd;
import 'design_tools.dart'
    show CmdResult, htmlElementTags, interactiveElementRe, svgElementTags;
import 'gate_design_widgets.dart' show directTextSnippet;

/// Outcome of annotating one source text.
class AnnotateResult {
  final String code;
  final int annotated;
  final int carried;
  const AnnotateResult(this.code, this.annotated, this.carried);
}

final _annotatableTags = <String>{...htmlElementTags, ...svgElementTags};
final _hasIdentityRe = RegExp(r'\bdata-el\b|\binspectAttrs\b');
final _ariaRe = RegExp(r'''\baria-label\s*=\s*"([^"]*)"''');
final _roleAttrRe = RegExp(r'''\brole\s*=\s*"(button|link|tab|switch)"''');
final _classRe = RegExp(r'''\bclass\s*=\s*"([^"]*)"''');
final _hrefRe = RegExp(r'''\bhref\s*=\s*"([^"]*)"''');

const _tagRoles = <String, String>{
  'a': 'link', 'button': 'button', 'input': 'form field',
  'select': 'form field', 'textarea': 'form field', 'summary': 'disclosure',
  'nav': 'nav', 'h1': 'heading', 'h2': 'heading', 'h3': 'heading',
  'h4': 'heading', 'h5': 'heading', 'h6': 'heading', 'img': 'media',
  'svg': 'icon', 'form': 'form', 'ul': 'list', 'ol': 'list', 'li': 'list row',
  'table': 'table', 'label': 'label',
};

String _sanitize(String v, [int max = 60]) {
  var s = v
      .replaceAll('"', "'")
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > max) s = '${s.substring(0, max - 1)}…';
  return s;
}

/// Derive and insert the semantic set on qualifying elements in [src]. Pure.
AnnotateResult annotateSource(String src) {
  final inserts = <int, String>{}; // offset (after tag name) → attribute text
  var carried = 0;
  var i = 0;
  final len = src.length;
  while (i < len - 1) {
    final c = src.codeUnitAt(i);
    final d = src.codeUnitAt(i + 1);
    if (c == 96) {
      // template literal — data, not elements (design_stamp law)
      var k = i + 1;
      while (k < len) {
        if (src.codeUnitAt(k) == 92) {
          k += 2;
          continue;
        }
        if (src.codeUnitAt(k) == 96) break;
        k++;
      }
      i = k < len ? k + 1 : len;
      continue;
    }
    if (c == 47 && d == 42) {
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
        (i == 0 || src.codeUnitAt(i - 1) == 10 || _onlySpaceBack(src, i))) {
      final end = src.indexOf('\n', i + 2);
      i = end < 0 ? len : end + 1;
      continue;
    }
    if (c == 60 && d >= 97 && d <= 122) {
      var j = i + 1;
      while (j < len &&
          ((src.codeUnitAt(j) >= 97 && src.codeUnitAt(j) <= 122) ||
              (src.codeUnitAt(j) >= 65 && src.codeUnitAt(j) <= 90) ||
              (src.codeUnitAt(j) >= 48 && src.codeUnitAt(j) <= 57) ||
              src.codeUnitAt(j) == 45)) {
        j++;
      }
      final name = src.substring(i + 1, j);
      if (!_annotatableTags.contains(name)) {
        i = j;
        continue;
      }
      final end = openingTagEnd(src, j);
      if (end < 0) {
        i = j;
        continue;
      }
      final tagText = src.substring(j, end);
      if (_hasIdentityRe.hasMatch(tagText)) {
        carried++;
        i = end + 1;
        continue;
      }
      final openTag = src.substring(i, end + 1);
      final text = directTextSnippet(src, end + 1);
      final interactive = interactiveElementRe.hasMatch(openTag);
      if (!interactive && text == null) {
        i = end + 1; // not inspect-mandatory — leave it bare
        continue;
      }
      final role = _roleAttrRe.firstMatch(tagText)?.group(1) ??
          _tagRoles[name] ??
          (text != null ? 'text' : 'container');
      final aria = _ariaRe.firstMatch(tagText)?.group(1);
      final cls = _classRe.firstMatch(tagText)?.group(1);
      // Label fallback chain: aria-label, direct text, href (a link's
      // destination IS its identity — "link:a" from a bare tag fallback is
      // junk and duplicates across every textless link), first class token,
      // then the tag.
      final label = _sanitize(
          aria ??
              text ??
              (name == 'a' ? _hrefRe.firstMatch(tagText)?.group(1) : null) ??
              (cls?.split(' ').first ?? name),
          40);
      final style = _sanitize(cls ?? name);
      final fn = _sanitize(aria ??
          (interactive
              ? '${role == 'button' || role == 'link' ? '$role: ' : ''}$label'
              : 'Shows: $label'));
      inserts[j] = ' data-el="$role:$label" data-inspect-role="$role"'
          ' data-inspect-style="$style" data-inspect-fn="$fn"'
          ' data-inspect-fn-provenance="inferred"';
      i = end + 1;
      continue;
    }
    i++;
  }

  if (inserts.isEmpty) return AnnotateResult(src, 0, carried);
  final out = StringBuffer();
  var cursor = 0;
  for (final at in inserts.keys.toList()..sort()) {
    out.write(src.substring(cursor, at));
    out.write(inserts[at]);
    cursor = at;
  }
  out.write(src.substring(cursor));
  return AnnotateResult(out.toString(), inserts.length, carried);
}

bool _onlySpaceBack(String s, int i) {
  var k = i - 1;
  while (k >= 0) {
    final c = s.codeUnitAt(k);
    if (c == 10) return true;
    if (c != 32 && c != 9) return false;
    k--;
  }
  return true;
}

/// `appbox design annotate <artifactDir>` — derive the semantic layer on
/// every qualifying element lacking one, in every .tsx under the dir.
CmdResult annotateMain(List<String> args) {
  if (args.isEmpty) {
    return CmdResult(2, stderrLines: [
      'appbox design annotate: missing <artifactDir> '
          '(e.g. ~/.appbox/projects/<name>/design)'
    ]);
  }
  final dir = Directory(args.first);
  if (!dir.existsSync()) {
    return CmdResult(2,
        stderrLines: ['appbox design annotate: no such dir: ${args.first}']);
  }
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.tsx'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    return CmdResult(2,
        stderrLines: ['appbox design annotate: no .tsx under ${args.first}']);
  }
  final out = <String>[];
  var totalAnnotated = 0, totalCarried = 0;
  for (final f in files) {
    final src = f.readAsStringSync();
    final res = annotateSource(src);
    if (res.annotated > 0) f.writeAsStringSync(res.code);
    totalAnnotated += res.annotated;
    totalCarried += res.carried;
    if (res.annotated > 0) {
      final rel = p.split(p.relative(f.path, from: dir.path)).join('/');
      out.add('$rel: ${res.annotated} annotated, ${res.carried} carried');
    }
  }
  out.add('annotate: $totalAnnotated derived (provenance=inferred), '
      '$totalCarried already-annotated carried, ${files.length} files');
  return CmdResult(0, stdoutLines: out);
}
