/// Designer-skill tools ported to Dart (Task 19): client-JS lint (ADR-0002),
/// ladder check, wiring checks, pseudolocalize, vendor fetch, doctor.
///
/// Each runtime is a faithful port of the `.mjs` original under
/// skills/appbox-designer/runtime/ — exit codes and stdout/stderr contracts
/// are preserved. `shoot.mjs` / `console-check.mjs` are deliberately NOT
/// ported (superseded by `appbox lens shoot` / `appbox lens check`); the
/// `verify-*.mjs` debug scripts are dropped (`lens check` covers them). See
/// plan §19.
///
/// SRI uses SHA-384; appboxd has no crypto package with sha384 (only
/// crypto_aead's sha256), so `sri()` spawns `openssl dgst -sha384 -binary` —
/// a macOS base tool. Recorded as a deliberate choice (kimitail: swap in a
/// pure-Dart sha384 if a no-spawn environment ever needs it).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:appboxd/cdp.dart';
import 'package:appboxd/crypto_aead.dart';
import 'package:appboxd/design_server/l10n.dart';
import 'package:appboxd/gate_design_styles.dart' show gateDesignStyles;
import 'package:appboxd/gate_design_widgets.dart' show gateDesignWidgets;

// The l10n primitives are part of the design-tools public surface (pseudolocalize
// uses parsePlural/parseArb; Task 20 extends the l10n submodule further).
export 'package:appboxd/design_server/l10n.dart' show parsePlural, Plural, parseArb;

/// Outcome of a design verb: exit code + the stdout/stderr lines it would
/// print. The CLI layer (`design_cli.dart`) flushes these to the real sinks;
/// tests assert on both the code and the text.
class CmdResult {
  final int exitCode;
  final List<String> stdoutLines;
  final List<String> stderrLines;
  const CmdResult(this.exitCode, {this.stdoutLines = const [], this.stderrLines = const []});
}

// ══ lint ═══════════════════════════════════════════════════════════════

class LintFinding {
  final String file;
  final String message;
  LintFinding(this.file, this.message);
  @override
  String toString() => '$file: $message';
}

/// Strip comments before scanning (commented code is not a violation).
/// Handles HTML (`<!-- -->`) and TSX/JS (`/* */` blocks — which also covers
/// the JSX `{/* … */}` form — plus `//` line comments). Line-comment
/// stripping is anchored to line-start to avoid matching `//` inside strings
/// (URLs, attribute values).
String stripComments(String html) => html
    .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

/// The HTML host-element vocabulary, shared by W7's scan (gate_design_widgets)
/// and the data-arxa-id stamper (design_stamp). A lowercase JSX opening tag is
/// only treated as markup when its name is in this set — TS generics and
/// comparisons produce lowercase `<name` shapes that are not elements.
const htmlElementTags = <String>{
  'a', 'abbr', 'address', 'area', 'article', 'aside', 'audio', 'b', 'base',
  'bdi', 'bdo', 'blockquote', 'br', 'button', 'canvas', 'caption', 'cite',
  'code', 'col', 'colgroup', 'data', 'datalist', 'dd', 'del', 'details', 'dfn',
  'dialog', 'div', 'dl', 'dt', 'em', 'embed', 'fieldset', 'figcaption',
  'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'head',
  'header', 'hgroup', 'hr', 'html', 'i', 'iframe', 'img', 'input', 'ins',
  'kbd', 'label', 'legend', 'li', 'link', 'main', 'map', 'mark', 'menu',
  'meta', 'meter', 'nav', 'noscript', 'object', 'ol', 'optgroup', 'option',
  'output', 'p', 'param', 'picture', 'pre', 'progress', 'q', 'rp', 'rt',
  'ruby', 's', 'samp', 'script', 'section', 'select', 'slot', 'small',
  'source', 'span', 'strong', 'style', 'sub', 'summary', 'sup', 'table',
  'tbody', 'td', 'template', 'textarea', 'tfoot', 'th', 'thead', 'time',
  'title', 'tr', 'track', 'u', 'ul', 'var', 'video', 'wbr',
};

/// The SVG element vocabulary. Kept SEPARATE from [htmlElementTags] because
/// W7's authoring gate scopes itself to HTML host semantics, while the
/// data-arxa-id stamper's ratified coverage is EVERY element — an `<svg>` root
/// is grabbable in the overlay, and an interactive one (role="button", e.g.
/// an icon close button) is exactly what design patch must address.
const svgElementTags = <String>{
  'svg', 'g', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline',
  'polygon', 'text', 'tspan', 'defs', 'use', 'symbol', 'marker', 'clipPath',
  'mask', 'pattern', 'image', 'foreignObject', 'desc', 'title', 'stop',
  'linearGradient', 'radialGradient',
};

/// The ADR-0002 rules, ported rule-for-rule from lint.mjs, widened by
/// ADR-0009 (client-JS law v2): scripts resolve to the vendored set, the
/// vendorSrc() helper, an artifact app module (/assets/app/…), or carry
/// type="application/json" (island config payloads). Negative lookaheads
/// kept from the source regex (double-quote-specific allowlisting — matching
/// the original's byte-for-byte semantics). The `vendorSrc(` lookahead was
/// added when script tags moved from literal `src="/assets/vendor/…"` to
/// the vendorSrc() helper for cache-busting.
final _lintRules = <(RegExp, String)>[
  (RegExp(r'<script(?![^>]*src="/assets/vendor/)(?![^>]*vendorSrc\()'
      r'(?![^>]*src="/assets/app/)'
      r'(?![^>]*type="application/json")[^>]*>',
      caseSensitive: false),
   'non-vendor <script> tag'),
  (RegExp(r'\bhx-on[:\s=]', caseSensitive: false), 'hx-on handler'),
  // Both quote styles — a single-quoted hx-vals carrying `js:` is legal HTML
  // and must not slip past the ban.
  (RegExp(r"""\bhx-(vals|headers)\s*=\s*['"]js:""", caseSensitive: false),
   'js:-prefixed attribute'),
  (RegExp(r"""\bhx-trigger\s*=\s*['"][^'"]*\[""", caseSensitive: false),
   '[expr] trigger filter'),
];

/// Rule 5 — inspect metadata, per DESIGN-ARCHITECTURE.md "Inspect metadata":
/// the set is mandatory on anything carrying `data-el`; `data-inspect-motion`
/// may legitimately be absent (it means "none"), the other three never omit.
///
/// This was a documented MUST that nothing enforced, so every one of a real
/// project's surfaces violated it and the inspect island had nothing to bind
/// to — hover and click silently did nothing. A rule that cannot fail is the
/// same defect as a rule that is not written down.
///
/// Per-tag rather than per-file: the other four rules ask "does this file
/// contain X", this one asks "does this element carry its siblings".
final _tagRe = RegExp(r'<[a-zA-Z][^>]*?>', dotAll: true);
const _inspectRequired = ['data-inspect-role', 'data-inspect-style', 'data-inspect-fn'];

/// `isSurface` scopes the stricter half. A *designed screen* that annotates
/// nothing is the failure that let inspect rot; the studio's own chrome links
/// are not designed elements of a client app, so only files under `surfaces/`
/// are held to "if you render interactive elements, annotate them".
///
/// D7 — the coverage bar is **C**: EVERY interactive element carries `data-el`.
/// The bar it replaces was literally "at least one" (`interactive > 0 &&
/// annotated == 0`), which `home.html` passed with one annotation on eleven
/// elements. `coverageB` drops to **B** — only the element KINDS a reviewer
/// expects to be inspectable — the bar you sit at while a surface is being
/// brought up, not the bar you ship.
///
/// Rule C's interactive set is what designers actually author, not what the
/// first cut could see: `<a href>|<button>` missed every form control,
/// ARIA-promoted div, focusable and htmx-driven element on the page. Applied
/// per TAG inside the `_tagRe` loop, so a `<button hx-post>` satisfying two
/// alternatives still counts once, and a nested match counts once per opening
/// tag rather than once per enclosing element.
final _interactiveRe = RegExp(
    r"""^<(?:a\s[^>]*\bhref|button|input|select|textarea|summary|label)\b"""
    r"""|\brole\s*=\s*["'](?:button|link|tab|switch)["']"""
    r"""|\btabindex\s*=\s*["']\d"""
    r"""|\bhx-(?:get|post|put|patch|delete|trigger|target|swap|confirm)\b""",
    caseSensitive: true, dotAll: true);

/// Rule B — the `coverageB` target: the element KINDS a reviewer expects to be
/// inspectable. It is a strict SUBSET of C, deliberately: a lower bar that
/// flagged something the higher bar did not would be incoherent, and an
/// earlier cut that matched `class~="card|hero"` did exactly that — C sees
/// interactive elements, and a decorative `<div class="card">` is not one.
/// The vocabulary in use (`button` 9 · `card` 6 · `hero` 5 · `summary` 4) is
/// already covered by the tags below: portalo's cards are `<a href>` anchors
/// and its summaries are `<summary>`.
final _interactiveBRe = RegExp(
    r"""^<(?:a\s[^>]*\bhref|button|summary|input|select|textarea)\b"""
    r"""|\brole\s*=\s*["'](?:button|link)["']""",
    caseSensitive: true, dotAll: true);

/// D9 — a DERIVED `data-inspect-fn`. `fn` is prose ("Opens the category
/// listing"); `role`, `style` and `data-el` are mechanical. A generated `fn` is
/// therefore a guess and must say so, which is the house *derive + confirm*
/// pattern already worn three times: `_edgeFeedback` stamps `inferred: true`,
/// derived flows carry `provenance: 'inferred'`, `emitRegistry` carries
/// `statesProvenance`. The lint ACCEPTS an inferred fn — it is not missing —
/// and reports it on the advisory channel, never as a finding, so coverage
/// (how much is annotated) and confidence (how much is confirmed) stay
/// separable numbers.
const _inspectFnProvenance = 'data-inspect-fn-provenance';
final _inferredFnRe = RegExp(
    """\\b$_inspectFnProvenance\\s*=\\s*["']inferred["']""",
    caseSensitive: false);

/// D10 — a declared state is a JSX conditional on the `state` prop in the
/// SAME surface file: `{state === 'loading' && (…)}` or the ternary
/// `{state === 'empty' ? (…) : (…)}`. `?state=loading` swaps regions in
/// place: separate variant files duplicate every annotation with no sync
/// mechanism, and a viewer-side overlay has none at all. The registry
/// declares, the surface must branch — and a branch nobody declared is that
/// drift read the other way.
final _stateBranchRe = RegExp(
    r"""\bstate\s*={2,3}\s*["']([a-z]+)["']""",
    caseSensitive: false);

/// D13 — retry is an affordance, not a fourth state. An `error`/`empty` region
/// needs BOTH affordances, because the pull gesture is not discoverable on an
/// error screen and the button alone throws away the gesture; and it must
/// SCROLL, because `RefreshIndicator` cannot detect a pull inside an
/// unscrollable box — a bare `Center()` silently defeats the pull it
/// advertises. The region names itself with `data-state`; these markers are
/// the contract the designer emits against.
const _stateRegionAttr = 'data-state';
const _scrollMarker = 'data-scroll';
const _pullMarker = 'data-refresh';
const _retryMarker = 'data-retry';

/// D18 — widget-coverage: every visible interactive or text leaf must sit
/// inside a [data-el] widget boundary (or carry one itself), so inspect hover
/// always resolves to an authored widget — never the screen fallback. Checks
/// ancestry via a lightweight nesting walk over the token stream.
final _coverageLeafTags = {
  'button', 'a', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p',
  'input', 'select', 'textarea', 'label', 'svg',
};
/// Matches both literal `data-el=` and `inspectAttrs(` spread (the ONE source
/// of widget identity in the studio — see primitives.tsx).
final _hasElOrAttrsRe = RegExp(r'\bdata-el\s*=|inspectAttrs\(');
/// HTML void elements that don't push to the nesting stack.
const _coverageVoidTags = {
  'br', 'img', 'input', 'meta', 'link', 'hr', 'area', 'base',
  'col', 'embed', 'source', 'track', 'wbr',
};
final _tagTokenRe = RegExp(
    r'(</?)([a-zA-Z][a-zA-Z0-9]*)([^>]*?)(/?)>', dotAll: true);

/// Findings for [src]. [declaredStates] turns D10 on (null = no registry
/// reachable, rule off); [notes] collects the advisory, non-failing D9 channel.
List<String> inspectFindings(String src,
    {bool isSurface = false,
    bool coverageB = false,
    List<String>? declaredStates,
    List<String>? notes}) {
  final out = <String>[];
  final hasEl = RegExp(r'\bdata-el\s*=');
  final interactive = coverageB ? _interactiveBRe : _interactiveRe;
  var unannotated = 0;
  for (final m in _tagRe.allMatches(src)) {
    final tag = m[0]!;
    if (!hasEl.hasMatch(tag)) {
      // D7 rule C/B — an interactive element with no `data-el` is invisible to
      // inspect. Counted here rather than over the whole file so that one tag
      // is one element however many alternatives it happens to satisfy.
      if (isSurface && interactive.hasMatch(tag)) unannotated++;
      continue;
    }
    final missing = _inspectRequired.where((a) => !tag.contains(a)).toList();
    if (missing.isEmpty) continue;
    final name = RegExp(r'''data-el\s*=\s*["']([^"']{0,40})''').firstMatch(tag)?[1] ?? '?';
    out.add('[data-el="$name"] missing ${missing.join(", ")}');
  }
  if (isSurface && unannotated > 0) {
    out.add('$unannotated interactive element(s) carry no data-el — inspect '
        'has nothing to bind to (coverage bar ${coverageB ? "B" : "C"})');
  }
  // D9 — inferred fns are counted, never failed. An authored fn contributes
  // nothing here, so the two are distinguishable at a glance.
  final inferred = _inferredFnRe.allMatches(src).length;
  if (inferred > 0) {
    notes?.add('$inferred data-inspect-fn value(s) marked inferred — derived, '
        'not authored; confirm before shipping');
  }
  if (isSurface && declaredStates != null) {
    final branched =
        _stateBranchRe.allMatches(src).map((m) => m[1]!.toLowerCase()).toSet();
    for (final s in declaredStates) {
      if (!branched.contains(s)) {
        out.add("registry declares state '$s' but the surface has no "
            "`state === '$s'` branch");
      }
    }
    for (final s in branched) {
      if (!declaredStates.contains(s)) {
        out.add("surface branches on state '$s' that the registry does not "
            'declare');
      }
    }
  }
  if (isSurface) out.addAll(_retryFindings(src));
  if (isSurface) out.addAll(_widgetCoverageFindings(src));
  return out;
}

/// D13's two rules over the `error`/`empty` regions of [src]. A region is the
/// slice from its `data-state="…"` opening tag to the next one (or EOF) —
/// regex depth, like every other rule in this file, and sufficient because a
/// state region is a sibling block and never nests inside another.
List<String> _retryFindings(String src) {
  final out = <String>[];
  final regions = RegExp(
          """<[a-zA-Z][^>]*\\b$_stateRegionAttr\\s*=\\s*["'](error|empty)["'][^>]*>""",
          caseSensitive: false, dotAll: true)
      .allMatches(src)
      .toList();
  for (var i = 0; i < regions.length; i++) {
    final m = regions[i];
    final state = m[1]!.toLowerCase();
    final region =
        src.substring(m.start, i + 1 < regions.length ? regions[i + 1].start : src.length);
    if (!RegExp("""\\b$_scrollMarker\\s*=\\s*["'](?!none)""", caseSensitive: false)
        .hasMatch(m[0]!)) {
      out.add("'$state' region is not scrollable ($_scrollMarker missing) — "
          'RefreshIndicator cannot detect a pull inside an unscrollable box');
    }
    final affordances = <String>[
      if (RegExp("""\\b$_pullMarker\\s*=\\s*["']pull["']""", caseSensitive: false)
          .hasMatch(region))
        'pull-to-refresh',
      if (RegExp('\\b$_retryMarker\\b', caseSensitive: false).hasMatch(region))
        'retry control',
    ];
    if (affordances.length < 2) {
      out.add("'$state' region offers "
          '${affordances.isEmpty ? "no retry affordance" : affordances.single} '
          '— BOTH $_pullMarker="pull" and a $_retryMarker control are required; '
          'the pull gesture is not discoverable on an error screen');
    }
  }
  return out;
}

/// D18 — widget-coverage nesting walk. Returns a finding for every target leaf
/// (button, a, h1–h6, p, input, select, textarea, label, svg) that has no
/// `data-el` on self and no `data-el`/`inspectAttrs(` on any open ancestor.
/// Not a full HTML parser — sufficient for well-formed TSX, same scope as the
/// other regex rules in this file.
List<String> _widgetCoverageFindings(String src) {
  final out = <String>[];
  // Stack of (tagName, hasDataEl) for currently-open elements.
  final stack = <(String, bool)>[];
  for (final m in _tagTokenRe.allMatches(src)) {
    final isClose = m[1] == '</';
    final tag = m[2]!.toLowerCase();
    final attrs = m[3]!;
    final selfClose = m[4] == '/';
    if (isClose) {
      // Pop to the matching tag (tolerates minor malformed nesting).
      for (var i = stack.length - 1; i >= 0; i--) {
        if (stack[i].$1 == tag) {
          stack.removeRange(i, stack.length);
          break;
        }
      }
      continue;
    }
    final hasEl = _hasElOrAttrsRe.hasMatch(attrs);
    if (!hasEl && _coverageLeafTags.contains(tag)) {
      final inWidget = stack.any((s) => s.$2);
      if (!inWidget) {
        out.add('<$tag> has no data-el on self or any ancestor — '
            'inspect hover falls through to screen fallback');
      }
    }
    if (!selfClose && !_coverageVoidTags.contains(tag)) {
      stack.add((tag, hasEl));
    }
  }
  return out;
}
/// renders. The join is filename → the registry id ending `.<short>`: registry
/// `surface` is null until the designer fills it, so the name is the only link
/// that exists at lint time. Returns null — D10 off — for a partial
/// (`_name.tsx`), when no registry is reachable, or when no entry matches, so
/// a bare directory of loose templates stays lintable.
List<String>? _declaredStates(String htmlPath, Map<String, List<dynamic>?> cache) {
  final short = p.basenameWithoutExtension(htmlPath);
  if (short.startsWith('_')) return null;
  final reg = _nearestRegistry(p.dirname(htmlPath), cache);
  if (reg == null) return null;
  for (final e in reg) {
    if (e is! Map) continue;
    final id = e['id'];
    if (id is! String || !id.endsWith('.$short')) continue;
    final st = e['states'];
    return st is List ? st.whereType<String>().toList() : const <String>[];
  }
  return null;
}

/// Walk up from [dir] for `intake/registry.json` (same shape as
/// `_findRepoRoot`), memoised per directory — a 12-surface project would
/// otherwise read and parse the same registry twelve times.
List<dynamic>? _nearestRegistry(String dir, Map<String, List<dynamic>?> cache) =>
    cache.putIfAbsent(dir, () {
      var d = Directory(dir);
      while (true) {
        final f = File(p.join(d.path, 'intake', 'registry.json'));
        if (f.existsSync()) {
          try {
            final j = jsonDecode(f.readAsStringSync());
            return j is List ? j : null;
          } catch (_) {
            return null;
          }
        }
        final parent = d.parent;
        if (parent.path == d.path) return null;
        d = parent;
      }
    });

List<File> _walk(Directory d) => d
    .listSync(recursive: true)
    .whereType<File>()
    .toList();

/// ADR-0009 form 3 — app-module references: `src="/assets/app/<name>.js"`
/// must resolve to a real file under the artifact's assets/app/ carrying the
/// island header (a leading /* or // comment — the "why this exists at all"
/// discipline the first-party islands already follow).
final _appModuleRe = RegExp(r'src="/assets/app/([A-Za-z0-9_./-]+\.js)"');

/// Vendor references for the weight ceiling: both the literal
/// src="/assets/vendor/…" form and the vendorSrc('name') helper form.
final _vendorSrcRe = RegExp(r'src="/assets/vendor/([A-Za-z0-9_./-]+)"');
final _vendorCallRe = RegExp(r"""vendorSrc\(\s*['"]([^'"]+)['"]""");

/// Scan every `.html`/`.tsx` template under [artifactDir] for the lint rules.
/// Returns findings in walk order, rule order within each file (mirrors
/// lint.mjs). [coverageB] drops D7's bar from C to B; [notes] collects the
/// advisory D9 channel, which never affects the exit code.
List<LintFinding> lintArtifact(String artifactDir,
    {bool coverageB = false, List<LintFinding>? notes}) {
  final findings = <LintFinding>[];
  final registries = <String, List<dynamic>?>{};
  final appRefs = <String, String>{}; // module name -> first referencing file
  final vendorRefs = <String>{};
  for (final f in _walk(Directory(artifactDir))) {
    if (!f.path.endsWith('.html') && !f.path.endsWith('.tsx')) continue;
    final src = stripComments(f.readAsStringSync());
    for (final (re, msg) in _lintRules) {
      if (re.hasMatch(src)) {
        findings.add(LintFinding(f.path, msg));
      }
    }
    for (final m in _appModuleRe.allMatches(src)) {
      appRefs.putIfAbsent(m[1]!, () => f.path);
    }
    for (final m in _vendorSrcRe.allMatches(src)) {
      if (m[1]!.endsWith('.js')) vendorRefs.add(m[1]!);
    }
    for (final m in _vendorCallRe.allMatches(src)) {
      if (m[1]!.endsWith('.js')) vendorRefs.add(m[1]!);
    }
    final isSurface = f.path.contains('${p.separator}surfaces${p.separator}');
    final fileNotes = <String>[];
    for (final msg in inspectFindings(src,
        isSurface: isSurface,
        coverageB: coverageB,
        declaredStates: isSurface ? _declaredStates(f.path, registries) : null,
        notes: fileNotes)) {
      findings.add(LintFinding(f.path, msg));
    }
    for (final msg in fileNotes) {
      notes?.add(LintFinding(f.path, msg));
    }
  }
  // ADR-0009 form 3 — every referenced app module exists and carries the
  // island header. A src that resolves to nothing is a 404 at runtime and a
  // lint failure at design time.
  for (final entry in appRefs.entries) {
    final mod = File(p.join(artifactDir, 'assets', 'app', entry.key));
    if (!mod.existsSync()) {
      findings.add(LintFinding(
          entry.value, 'app module not found: assets/app/${entry.key}'));
      continue;
    }
    final head = mod.readAsStringSync().trimLeft();
    if (!head.startsWith('/*') && !head.startsWith('//')) {
      findings.add(LintFinding(entry.value,
          'app module missing island header (why-this-exists comment): '
          'assets/app/${entry.key}'));
    }
  }
  // ADR-0009 §weight — the commission ceiling, when declared, is enforced
  // over what the artifact's HTML actually loads (referenced vendor .js +
  // app modules — the same narrowing eject performs).
  findings.addAll(_clientJsCeilingFindings(artifactDir, appRefs, vendorRefs, notes));
  return findings;
}

/// The ceiling seam: an optional `client-js.json` at the artifact root
/// carrying `{"ceilingKb": N}`. The commission names the number; this file
/// is its machine copy (same pattern as the layout template → registry).
/// Unresolvable vendor bytes (pub-cache binary, no repo root) degrade to a
/// note — a ceiling that cannot be measured is reported, never guessed.
List<LintFinding> _clientJsCeilingFindings(String artifactDir,
    Map<String, String> appRefs, Set<String> vendorRefs, List<LintFinding>? notes) {
  final ceilingFile = File(p.join(artifactDir, 'client-js.json'));
  if (!ceilingFile.existsSync()) return const [];
  num? ceilingKb;
  try {
    final j = jsonDecode(ceilingFile.readAsStringSync());
    if (j is Map) ceilingKb = num.tryParse('${j['ceilingKb']}');
  } catch (_) {}
  if (ceilingKb == null) {
    return [
      LintFinding(ceilingFile.path,
          'client-js.json present but no numeric ceilingKb — fix or remove')
    ];
  }
  final repo = _findRepoRoot();
  if (repo == null) {
    notes?.add(LintFinding(ceilingFile.path,
        'ceilingKb=$ceilingKb declared but vendor dir unresolvable (no repo '
        'root) — weight not verified'));
    return const [];
  }
  final vendorDir = Directory(p.join(
      repo, 'skills', 'appbox-designer', 'runtime', 'vendor'));
  var total = 0;
  final missing = <String>[];
  for (final v in vendorRefs) {
    final f = File(p.join(vendorDir.path, v));
    if (f.existsSync()) {
      total += f.lengthSync();
    } else {
      missing.add(v);
    }
  }
  for (final name in appRefs.keys) {
    total += File(p.join(artifactDir, 'assets', 'app', name)).lengthSync();
  }
  final kb = total / 1024;
  if (kb > ceilingKb) {
    return [
      LintFinding(ceilingFile.path,
          'client JS weight ${kb.toStringAsFixed(1)}KB exceeds the declared '
          'ceiling ${ceilingKb}KB')
    ];
  }
  notes?.add(LintFinding(ceilingFile.path,
      'client JS weight ${kb.toStringAsFixed(1)}KB within the declared '
      'ceiling ${ceilingKb}KB'));
  return const [];
}

/// `appbox design lint <artifact-dir> [--coverage-b]` — exit 0 clean /
/// 1 findings / 2 usage. `--coverage-b` drops D7's inspection bar from C
/// (every interactive element annotated) to B (button · card · hero · summary
/// and kin only); the default is C. D9's inferred-fn notes ride stdout in both
/// outcomes — an inferred annotation is reported, never failed, so it can
/// never move the exit code.
CmdResult designLint(List<String> args) {
  var coverageB = false;
  final rest = <String>[];
  for (final a in args) {
    if (a == '--coverage-b') {
      coverageB = true;
      continue;
    }
    rest.add(a);
  }
  if (rest.isEmpty) {
    return CmdResult(2, stderrLines: const ['usage: appbox design lint <artifact-dir>']);
  }
  final dir = p.absolute(rest.first);
  final notes = <LintFinding>[];
  final findings = lintArtifact(dir, coverageB: coverageB, notes: notes);
  final widgetFindings = gateDesignWidgets(dir, notes: notes);
  final styleFindings = gateDesignStyles(dir, notes: notes);
  final noteLines = notes.map((n) => 'note: $n').toList();
  if (findings.isNotEmpty ||
      widgetFindings.isNotEmpty ||
      styleFindings.isNotEmpty) {
    final lines = <String>[];
    if (findings.isNotEmpty) {
      lines.add('client-JS lint failed:');
      lines.addAll(findings.map((f) => f.toString()));
    }
    if (widgetFindings.isNotEmpty) {
      lines.add('widget/panel gate failed (W1–W9):');
      lines.addAll(widgetFindings.map((f) => f.toString()));
    }
    if (styleFindings.isNotEmpty) {
      lines.add('style gate failed (S1–S4):');
      lines.addAll(styleFindings.map((f) => f.toString()));
    }
    return CmdResult(1, stdoutLines: noteLines, stderrLines: lines);
  }
  return CmdResult(0, stdoutLines: [
    'lint clean: every script resolves (vendor/island/app module), no inline handlers in $dir',
    'widget/panel gate clean: W1–W9 in $dir',
    'style gate clean: S1–S4 in $dir',
    ...noteLines,
  ]);
}

// ══ check-ladder ════════════════════════════════════════════════════════

/// Pure core of check_ladder.mjs: cross-check the parsed config against the
/// doctrine doc text. Returns the problem strings (the CLI indents + exits).
List<String> checkLadderFromInputs(
    {required String cfg, required String docText}) {
  final config = jsonDecode(cfg) as Map<String, dynamic>;
  final rungs = (config['rungs'] as Map).cast<String, dynamic>();
  final boundaries = (config['boundaries'] as List).cast<num>();
  final docLines = docText.split('\n');
  final problems = <String>[];

  // Every config rung must appear in the doc's table with the same width.
  for (final entry in rungs.entries) {
    final name = entry.key;
    final width = (entry.value as Map)['width'];
    String? row;
    for (final l in docLines) {
      if (l.contains('`$name`') && l.trimLeft().startsWith('|')) {
        row = l;
        break;
      }
    }
    if (row == null) {
      problems.add('doc has no table row for rung "$name"');
      continue;
    }
    if (!row.contains('$width')) {
      problems.add('doc row for "$name" does not carry width $width: ${row.trim()}');
    }
  }

  // Every rung named in the doc's table must exist in the config.
  final docRung = RegExp(r'\|\s*`([a-z]+)`\s*\|\s*\*\*(\d+)\*\*');
  for (final l in docLines) {
    final trimmed = l.trimLeft();
    if (!trimmed.startsWith('|')) continue;
    final m = docRung.firstMatch(trimmed);
    if (m == null) continue;
    final name = m.group(1)!;
    final width = m.group(2)!;
    if (!rungs.containsKey(name)) {
      problems.add('doc names rung "$name" (${width}px) that ladder.json does not define');
    }
  }

  // No rung may sit on a class boundary — the branch would be ambiguous.
  for (final entry in rungs.entries) {
    final width = (entry.value as Map)['width'] as num;
    if (boundaries.any((b) => b == width)) {
      problems.add('rung "${entry.key}" sits ON boundary $width — renders are ambiguous there');
    }
  }

  return problems;
}

/// `appbox design check-ladder [--config <p>] [--doc <p>]` — exit 0/1.
/// Defaults resolve the skill's runtime config + doctrine doc from the repo
/// root (the one config the whole design stage reads).
CmdResult designCheckLadder(List<String> args) {
  String? configPath;
  String? docPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--config' && i + 1 < args.length) {
      configPath = args[++i];
    } else if (args[i] == '--doc' && i + 1 < args.length) {
      docPath = args[++i];
    } else {
      return CmdResult(2,
          stderrLines: ['usage: appbox design check-ladder [--config <p>] [--doc <p>]']);
    }
  }
  final repo = _findRepoRoot() ?? Directory.current.path;
  configPath ??= '$repo/skills/appbox-designer/runtime/ladder.json';
  docPath ??= '$repo/skills/appbox-designer/references/viewport-ladder.md';
  final problems = checkLadderFromInputs(
      cfg: File(configPath).readAsStringSync(),
      docText: File(docPath).readAsStringSync());
  if (problems.isNotEmpty) {
    return CmdResult(1, stderrLines: problems.map((p) => '  $p').toList());
  }
  // Summary mirrors check_ladder.mjs: name=width, space-separated, config order.
  final rungs = (jsonDecode(File(configPath).readAsStringSync())['rungs']
          as Map)
      .cast<String, dynamic>();
  final summary = rungs.entries
      .map((e) => '${e.key}=${(e.value as Map)['width']}')
      .join(' ');
  return CmdResult(0, stdoutLines: ['ladder ok: $summary']);
}

// ══ check-wiring ═══════════════════════════════════════════════════════

const _wiringProps = ['fragments', 'mutations-posted', 'urls-resolve', 'targets-exist'];

/// Pure-ish core of check_wiring.mjs: read the artifact once, run one property
/// walker. Returns the problem strings (the CLI joins + exits).
List<String> checkWiringArtifact(String artifactDir, String property) {
  final dir = p.absolute(artifactDir);
  String rel(String f) => p.relative(f, from: dir);
  final files = _walk(Directory(dir));
  final markup = files
      .where((f) => f.path.endsWith('.html') || f.path.endsWith('.tsx'))
      .map((f) => (f, stripComments(f.readAsStringSync())))
      .toList();
  // app.routes.js spreads the per-shell routes.<shell>.js tables — parse
  // them all, or routes defined there are invisible to the joins below.
  final routeFiles = files.where((f) {
    final b = p.basename(f.path);
    return b == 'app.routes.js' || (b.startsWith('routes.') && b.endsWith('.js'));
  });
  final routeRe = RegExp(r"\[\s*'(GET|POST|PUT|PATCH|DELETE)'\s*,\s*'([^']+)'");
  final routes = <(String, String)>[];
  final postedBy = <String>{};
  for (final f in routeFiles) {
    for (final line in f.readAsLinesSync()) {
      final m = routeRe.firstMatch(line);
      if (m == null) continue;
      routes.add((m.group(1)!, m.group(2)!));
      // A route whose only sender is statically unresolvable (a facade-
      // computed hx-post like {{ c.composerAction }}, or a named island's
      // htmx.ajax) declares it on the route line: // posted-by: <sender>.
      if (line.contains('posted-by:')) postedBy.add('${m.group(1)} ${m.group(2)}');
    }
  }
  // Segment-wise route match: a `:param` segment matches any one segment.
  bool routeHits(String pattern, String url) {
    final pp = pattern.split('/'), up = url.split('/');
    if (pp.length != up.length) return false;
    for (var i = 0; i < pp.length; i++) {
      if (pp[i].startsWith(':')) continue;
      if (pp[i] != up[i]) return false;
    }
    return true;
  }
  final problems = <String>[];

  switch (property) {
    case 'fragments':
      for (final f in files.where((f) => f.path.endsWith('_viewmodel.js'))) {
        final src = f.readAsStringSync();
        final named = RegExp(r"""const VIEW\s*=\s*['"]([^'"]+)['"]""").firstMatch(src);
        // View refs use .html paths for registry parity; the actual file may
        // be .tsx (post-migration). Try the literal path first, then .tsx.
        String resolveView(String ref) {
          final literal = p.join(dir, ref);
          if (File(literal).existsSync()) return literal;
          final tsx = literal.replaceAll(RegExp(r'\.html$'), '.tsx');
          if (File(tsx).existsSync()) return tsx;
          return literal; // let the existsSync check below report it
        }
        final view = named != null
            ? resolveView(named.group(1)!)
            : resolveView(f.path.replaceAll(RegExp(r'_viewmodel\.js$'), '_view.html'));
        // Fragment refs are view refs: `${VIEW}#macro` or 'path.html#macro'.
        // Data strings like '#21BFE9' (hex colors) are not renders.
        final wantedRe =
            RegExp(r"""[`'"][^`'"]*(?:\.html|\$\{VIEW\})#(\w+)[`'"]""");
        final wanted = wantedRe
            .allMatches(src)
            .map((m) => m.group(1)!)
            .toSet();
        if (wanted.isEmpty) continue;
        if (!File(view).existsSync()) {
          problems.add('${rel(f.path)}: renders a fragment, but ${rel(view)} does not exist');
          continue;
        }
        final tpl = File(view).readAsStringSync();
        for (final n in wanted) {
          // TSX: export function Name / export const Name (PascalCase).
          // Viewmodels reference fragments by lowercase name (#tick → Tick).
          // Legacy: {% macro name %}
          final isTsx = view.endsWith('.tsx');
          final found = isTsx
              ? RegExp('export\\s+(?:default\\s+)?(?:function|const)\\s+${RegExp.escape(n[0].toUpperCase() + n.substring(1))}\\b').hasMatch(tpl)
              : RegExp('\\{%-?\\s*macro\\s+${RegExp.escape(n)}\\s*\\(').hasMatch(tpl);
          if (!found) {
            problems.add('${rel(f.path)}: renders "#$n", but ${rel(view)} defines no such ${isTsx ? 'component' : 'macro'}');
          }
        }
      }

    case 'mutations-posted':
      // Senders: hx-* attributes plus plain form actions (body is
      // hx-boost="true", so a plain form IS an htmx post). Templated values
      // are kept: a {{ }} segment is a wildcard (it can render a literal —
      // {{ c.base }}/answer — or a route :param — /build/stages/{{ s.id }}).
      final sent = <(String, String)>[];
      final sendRe = RegExp(r'hx-(get|post|put|patch|delete)\s*=\s*"([^"]+)"',
          caseSensitive: false);
      final formTagRe = RegExp(r'<form\b[^>]*>', caseSensitive: false);
      final formMethodRe = RegExp(r'method\s*=\s*"post"', caseSensitive: false);
      final formActionRe = RegExp(r'action\s*=\s*"([^"]+)"', caseSensitive: false);
      for (final (_, t) in markup) {
        for (final m in sendRe.allMatches(t)) {
          sent.add((m.group(1)!.toUpperCase(), m.group(2)!.split('?')[0]));
        }
        for (final tag in formTagRe.allMatches(t)) {
          final attrs = tag.group(0)!;
          if (!formMethodRe.hasMatch(attrs)) continue;
          final a = formActionRe.firstMatch(attrs);
          if (a != null) sent.add(('POST', a.group(1)!.split('?')[0]));
        }
      }
      bool sendHits(String sendUrl, String pattern) {
        final sp = sendUrl.split('/'), pp = pattern.split('/');
        // Segment-wise: a {{ }} send segment or a :param route segment is a
        // wildcard (/design/undo/chat posts /design/undo/:stack).
        var segHit = sp.length == pp.length;
        if (segHit) {
          for (var i = 0; i < sp.length; i++) {
            if (sp[i].contains('{{') || pp[i].startsWith(':')) continue;
            if (sp[i] != pp[i]) { segHit = false; break; }
          }
        }
        if (segHit) return true;
        // A templated segment can span route segments ({{ c.base }}/answer
        // renders /intake/answer): regex the send against a concrete route
        // instance. Anchored sends only — a whole-URL {{ }} sender proves
        // nothing (those routes name their sender: // posted-by:).
        if (!sp.any((s) => s.isNotEmpty && !s.contains('{{'))) return false;
        final concrete =
            pp.map((s) => s.startsWith(':') ? 'p' : s).join('/');
        final re = RegExp(
            '^${sp.map((s) => s.contains('{{') ? '.+' : RegExp.escape(s)).join('/')}' r'$');
        return re.hasMatch(concrete);
      }

      for (final (method, path) in routes) {
        if (method == 'GET') continue;
        final reachable = postedBy.contains('$method $path') ||
            sent.any((s) => s.$1 == method && sendHits(s.$2, path));
        if (!reachable) {
          problems.add('$method $path is a route no markup sends to — it is either '
              'dead, or its sender is dynamic (name it: // posted-by: <sender>)');
        }
      }

    case 'urls-resolve':
      final urlRe = RegExp(r'(?:hx-(?:get|post|put|patch|delete)|href)\s*=\s*"(/[^"{]*)"',
          caseSensitive: false);
      for (final (f, t) in markup) {
        for (final m in urlRe.allMatches(t)) {
          final u = m.group(1)!.split('?')[0].split('#')[0];
          if (u.startsWith('/assets/') || u.startsWith('/_ds/')) continue;
          // v2 layout: styles and runtime files live under /ui/ and the
          // design server serves any artifact file — allow them only when
          // the file actually exists in the artifact (stronger than the
          // /assets/ blanket, which covers skill-runtime vendor files).
          if (u.startsWith('/ui/')) {
            final artifactFile = File(p.join(dir, u.substring(1)));
            if (artifactFile.existsSync()) continue;
          }
          if (!routes.any((r) => routeHits(r.$2, u))) {
            problems.add('${rel(f.path)}: "$u" matches no route in the route tables');
          }
        }
      }

    case 'targets-exist':
      // Ids may be templated (panel-{{ spec.side }}-body): a {{ }} segment
      // is a wildcard when matching an hx-target against them. An unanchored
      // templated value ({{ s.id }}) proves nothing — it is not evidence.
      // (Leading \s so data-id is not mistaken for an element id.)
      // An id also counts when it is HANDED to a widget that emits it. The
      // panel base writes `id="{{ pid }}"` — unanchored, so it is no evidence
      // on its own — and every caller supplies the literal in its spec
      // (`id: 'design-viewer'`). Without this the demoted design viewer, and
      // any other panel given a non-default id, is invisible here while being
      // perfectly real in the DOM.
      final ids = <String>[];
      final idRe = RegExp(r'\sid\s*=\s*"([^"]+)"');
      final specIdRe = RegExp(r"""\bid\s*:\s*'([^'{]+)'""");
      // The panel BASE derives its ids, so literals that prove existence
      // come in two more shapes (same doctrine as the spec-id rule above):
      // 1. pid = id ?? 'panel-<role>' - a literal role prop proves panel-<role>.
      //    inspectAttrs' role: 'panel' bag key collides harmlessly: it mints
      //    panel-panel, an id nothing ever targets.
      // 2. PID consts ('const PID = ...') in the thin panel widgets, whose
      //    section ids the base derives as <pid>-<section>.
      final roleRe = RegExp(r"""\srole\s*[:=]\s*["']([a-z-]+)["']""");
      final pidConstRe = RegExp(r"""PID\s*=\s*["']([a-z-]+)["']""");
      for (final (_, t) in markup) {
        for (final m in idRe.allMatches(t)) {
          ids.add(m.group(1)!);
        }
        for (final m in specIdRe.allMatches(t)) {
          ids.add(m.group(1)!);
        }
        for (final m in roleRe.allMatches(t)) {
          ids.add('panel-${m.group(1)}');
        }
        for (final m in pidConstRe.allMatches(t)) {
          ids.add(m.group(1)!);
        }
      }
      // A literal panel pid proves its derived section family exists (the
      // base emits <pid>-body/-top/-bottom unconditionally).
      ids.addAll([
        for (final id in ids.where(
                (i) => i.startsWith('panel-') && !i.contains('{{')).toSet()) ...[
          '$id-body',
          '$id-top',
          '$id-bottom',
        ],
      ]);
      bool idHits(String target) => ids.any((id) {
            if (!id.contains('{{')) return id == target;
            final parts = id.split(RegExp(r'\{\{[^}]*\}\}'));
            if (!parts.any((s) => s.isNotEmpty)) return false;
            final re = RegExp(
                '^${parts.map(RegExp.escape).join('[^"]*')}' r'$');
            return re.hasMatch(target);
          });
      final targetRe = RegExp(r'hx-target\s*=\s*"#([^"\s]+)"');
      for (final (f, t) in markup) {
        for (final m in targetRe.allMatches(t)) {
          if (!idHits(m.group(1)!)) {
            problems.add('${rel(f.path)}: hx-target="#${m.group(1)}" — no element in the artifact carries that id');
          }
        }
      }
  }

  return problems;
}

/// `appbox design check-wiring <artifact-dir> <property>` — exit 2 usage /
/// 1 problems / 0 ok.
CmdResult designCheckWiring(List<String> args) {
  if (args.length < 2 || !_wiringProps.contains(args[1])) {
    return CmdResult(2, stderrLines: [
      'usage: appbox design check-wiring <artifact-dir> <${_wiringProps.join('|')}>',
    ]);
  }
  final problems = checkWiringArtifact(args[0], args[1]);
  if (problems.isNotEmpty) {
    return CmdResult(1, stderrLines: problems);
  }
  return CmdResult(0, stdoutLines: ['${args[1]}: ok']);
}

// ══ pseudolocalize ═════════════════════════════════════════════════════

/// ASCII → accented lookalikes. Copied verbatim from pseudolocalize.mjs — it
/// is data, not code.
const _look = {
  'a': 'å', 'e': 'ë', 'i': 'ï', 'o': 'ö', 'u': 'ü', 'y': 'ÿ',
  'A': 'Å', 'E': 'Ë', 'I': 'Ï', 'O': 'Ö', 'U': 'Ü', 'Y': 'Ÿ',
  'c': 'ç', 'n': 'ñ', 's': 'š', 'z': 'ž', 'l': 'ł', 'r': 'ř', 't': 'ţ', 'd': 'ð',
  'C': 'Ç', 'N': 'Ñ', 'S': 'Š', 'Z': 'Ž', 'L': 'Ł', 'R': 'Ř', 'T': 'Ţ', 'D': 'Ð',
};

/// `~` + U+0337 (combining solidus overlay) + `~`. Built from code points so
/// the literal cannot drift from the .mjs source bytes (the golden confirms
/// U+0337, not U+0338).
final _padUnit = String.fromCharCode(0x7E) +
    String.fromCharCode(0x337) +
    String.fromCharCode(0x7E);

String _expand(String text) {
  final mapped = text.replaceAllMapped(
      RegExp(r'[a-zA-Z]'), (m) => _look[m[0]] ?? m[0]!);
  // Padding grows ~35%: max(2, ceil(len*0.35/3)) repetitions of the pad unit.
  final n = (text.length * 0.35 / 3).ceil();
  final pads = n < 2 ? 2 : n;
  final pad = _padUnit * pads;
  return '[!! $mapped $pad !!]';
}

/// Transform text, preserving `{var}` placeholders byte-for-byte. The
/// `\x00N\x00` sentinel survives `_expand` (no ASCII letters to map).
String plocText(String s) {
  final ph = <String>[];
  final stripped = s.replaceAllMapped(RegExp(r'\{[^{}]+\}'), (m) {
    ph.add(m[0]!);
    return '\x00${ph.length - 1}\x00';
  });
  return _expand(stripped)
      .replaceAllMapped(RegExp(r'\x00(\d+)\x00'), (m) => ph[int.parse(m[1]!)]);
}

/// Plural values: transform each option body, keep keywords and braces.
/// Non-strings pass through untouched.
Object plocValue(Object v) {
  if (v is! String) return v;
  final plural = parsePlural(v);
  if (plural == null) return plocText(v);
  final body = plural.options.entries
      .map((e) => '${e.key}{${plocText(e.value)}}')
      .join(' ');
  return '{${plural.varName}, plural, $body}';
}

/// Identifier fields templates compose into catalog keys or CSS classes —
/// wrapping them breaks the lookup and paints the key literal on screen.
const _enumKeys = {
  'id', 'status', 'state', 'severity', 'stage', 'priority', 'kind', 'tone',
  'badge', 'from',
};

/// Recursively transform a seed: ENUM_KEYS and `_`-prefixed keys stay
/// byte-identical; everything else (human text) expands. JSON `null` values
/// pass through untouched (seeds use them for empty slots like `artifact`).
Object? plocSeed(Object? value, String key) {
  if (value is String) {
    return (_enumKeys.contains(key) || key.startsWith('_')) ? value : plocText(value);
  }
  if (value is List) {
    return value.map((v) => plocSeed(v, key)).toList();
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry(k, plocSeed(v, k.toString())));
  }
  return value;
}

/// Write the qps-ploc arb + seed files for [artifactDir]. Returns the count
/// written (0 = nothing to do → CLI exits 66). Mirrors pseudolocalize.mjs.
int pseudolocalizeDir(String artifactDir) {
  final dir = p.absolute(artifactDir);
  var wrote = 0;

  final enArb = File(p.join(dir, 'l10n', 'app_en.arb'));
  if (enArb.existsSync()) {
    final src = parseArb(enArb.path);
    final out = <String, dynamic>{};
    for (final entry in src.entries) {
      out[entry.key] = entry.key.startsWith('@') ? entry.value : plocValue(entry.value);
    }
    out['@@locale'] = 'qps-ploc'; // after the loop: en's @@locale must not win
    final target = File(p.join(dir, 'l10n', 'app_qps-ploc.arb'));
    target.writeAsStringSync(
        "${const JsonEncoder.withIndent('  ').convert(out)}\n");
    print('wrote ${p.relative(target.path, from: dir)} (${src.length} keys)');
    wrote++;
  } else {
    print('no l10n/app_en.arb — nothing to pseudolocalize there');
  }

  final modelsDir = Directory(p.join(dir, 'models'));
  if (modelsDir.existsSync()) {
    for (final model in modelsDir.listSync().whereType<Directory>()) {
      for (final f in model.listSync().whereType<File>()) {
        if (!RegExp(r'_seed\.en\.json$').hasMatch(p.basename(f.path))) continue;
        final seed = jsonDecode(f.readAsStringSync());
        final target = File(f.path.replaceAll(
            RegExp(r'_seed\.en\.json$'), '_seed.qps-ploc.json'));
        target.writeAsStringSync(
            "${const JsonEncoder.withIndent('  ').convert(plocSeed(seed, ''))}\n");
        print('wrote ${p.relative(target.path, from: dir)} — regenerate fixtures to emit it');
        wrote++;
      }
    }
  }

  return wrote;
}

/// `appbox design pseudolocalize <artifact-dir>` — exit 64 usage / 66 nothing /
/// 0 wrote.
CmdResult designPseudolocalize(List<String> args) {
  if (args.isEmpty) {
    return CmdResult(64,
        stderrLines: const ['usage: appbox design pseudolocalize <artifact-dir>']);
  }
  final wrote = pseudolocalizeDir(args.first);
  if (wrote == 0) {
    return CmdResult(66, stderrLines: const [
      'nothing pseudolocalized — no l10n/app_en.arb and no *_seed.en.json found',
    ]);
  }
  return CmdResult(0);
}

// ══ vendor-fetch ═══════════════════════════════════════════════════════

/// Htmx core is the one pinned library: its SRI is recorded so a tampered or
/// re-published file fails loudly. Copied from vendor/fetch.mjs.
const _htmxPin = '2.0.10';
const _htmxIntegrity =
    'sha384-H5SrcfygHmAuTDZphMHqBJLc3FhssKjG7w/CeCpFReSfwBWDTKpkzPP8c+cLsK+V';

/// htmx 4 — morph is core (no idiomorph-ext); SSE is the bundled `hx-sse`
/// extension. Shipped as a separate vendor file (`htmx4.min.js`) so htmx 2
/// artifacts keep loading `htmx.min.js` unchanged. Pinned ≥ #3606 (morph swaps
/// not initializing new elements — closed 2026-01-20; fixed in beta6,
/// released 2026-07-23).
const _htmx4Pin = '4.0.0-beta6';
const _htmx4Integrity =
    'sha384-6lyVbhrs13b9z7mLOpt/N6R76rtkEBWgCjAXRs/DSWyi2AMnQSs10ijWk+PI8n7W';

/// alien-signals — the signals runtime for island-kit.js (Phase 3c). Its
/// algorithm is ported into Vue core 3.6; effectScope gives one stopScope()
/// per island. The npm package ships multi-file ESM, so vendor-fetch bundles
/// it with esbuild. 1.9 kB gzip.
const _alienSignalsPin = '3.2.1';
const _alienSignalsIntegrity =
    'sha384-JEXjCHkGjEBJBD27oeiXrrFMeKb53WEpVqm7qQ2qz8CXrmtvoYHM1bSyArrNlwcT';

class _Pkg {
  final String pkg;
  final String? version;
  final List<String> candidates;
  final String out;
  final bool expect; // htmx: SRI must match the recorded pin
  final String? expectPin; // override the function-level pin (multi-version)
  // ADR-0009 category tag — the manifest's role column. Open set, closed
  // vocabulary: hypermedia · state-framework · motion-framework · rich-media ·
  // data-viz · reactive-primitive. Adding a CATEGORY is an ADR-level decision;
  // adding a package inside an existing one is a row here.
  final String category;
  const _Pkg(this.pkg, this.candidates, this.out,
      {this.version, this.expect = false, this.expectPin,
      this.category = 'hypermedia'});
}

/// Lucide is pinned like htmx/leaflet: @latest drift would silently rewrite
/// the whole icon set and its manifest row. The tarball is fetched (not a CDN
/// file), so the loop special-cases it — the marker row keeps the manifest
/// order stable across re-runs.
const _lucidePin = '1.27.0';

/// ADR-0009 v2 — the state/motion framework pair. Alpine is the htmx-native
/// local-state layer; hx-alpine-compat is its official htmx-4 bridge
/// (settle-phase init, morph state carry, history serialization). GSAP is the
/// motion framework — every plugin public since the Webflow acquisition
/// (3.13), so ScrollTrigger + SplitText are plain npm files. All three pinned:
/// a framework the templates depend on must fail loudly, not drift.
const _alpinePin = '3.16.1';
const _gsapPin = '3.15.0';

/// Order pins the manifest row order: re-running vendor-fetch must rewrite
/// manifest.json + SRI.md byte-identically.
const _packages = [
  _Pkg('htmx.org', ['dist/htmx.min.js'], 'htmx.min.js',
      version: _htmxPin, expect: true),
  _Pkg('htmx-ext-preload', ['dist/preload.min.js', 'dist/preload.js'], 'preload.min.js'),
  _Pkg('htmx-ext-head-support', ['dist/head-support.min.js', 'dist/head-support.js'], 'head-support.js'),
  _Pkg('htmx-ext-sse', ['dist/sse.min.js', 'dist/sse.js'], 'sse.js'),
  _Pkg('htmx-ext-client-side-templates',
      ['dist/client-side-templates.min.js', 'dist/client-side-templates.js'],
      'client-side-templates.js'),
  _Pkg('mustache', ['mustache.min.js', 'mustache.js'], 'mustache.min.js'),
  _Pkg('lucide-static', [], 'lucide/icons/*.svg', version: _lucidePin),
  _Pkg('@google/model-viewer', ['dist/model-viewer.min.js'],
      'model-viewer.min.js', version: '4.3.1', category: 'rich-media'),
  _Pkg('@lottiefiles/dotlottie-wc', ['dist/dotlottie-wc.js'], 'dotlottie-wc.js',
      version: '0.9.24', category: 'rich-media'),
  _Pkg('@lottiefiles/dotlottie-web', ['dist/dotlottie-player.wasm'],
      'dotlottie-player.wasm', version: '0.78.2', category: 'rich-media'),
  _Pkg('@lottiefiles/lottie-player', ['dist/lottie-player.js'],
      'lottie-player.js', version: '2.0.12', category: 'rich-media'),
  _Pkg('@rive-app/canvas-single', ['rive.js'], 'rive.js', version: '2.39.1',
      category: 'rich-media'),
  _Pkg('three', ['build/three.module.min.js'], 'three.module.min.js',
      version: '0.185.1', category: 'rich-media'),
  _Pkg('three', ['build/three.core.min.js'], 'three.core.min.js',
      version: '0.185.1', category: 'rich-media'),
  // Leaflet is pinned like htmx: the runtime vendor copy is hand-checked and
  // the manifest rows must survive a re-fetch unchanged. Its images/ sprites
  // are NOT fetched (they ride along unpinned, same as the lucide SVGs did
  // before the tarball step) — re-adding them means an npm-tarball extract.
  _Pkg('leaflet', ['dist/leaflet.js'], 'leaflet/leaflet.js', version: '1.9.4',
      category: 'rich-media'),
  _Pkg('leaflet', ['dist/leaflet.css'], 'leaflet/leaflet.css', version: '1.9.4',
      category: 'rich-media'),
  // The htmx `morph` extension ships INSIDE the idiomorph package — there is no
  // `htmx-ext-morph` on npm (registry 404). The previous entry named that
  // non-existent package and was `optional: true`, so every vendor-fetch run
  // printed "– skipped" and carried on green while morph.js never landed.
  // Pinned and NOT optional: a swap style the templates depend on must fail
  // loudly if it cannot be vendored. `idiomorph-ext.min.js` is the combined
  // build (morphing core + the htmx extension registration) — one script tag.
  _Pkg('idiomorph', ['dist/idiomorph-ext.min.js'], 'idiomorph-ext.min.js',
      version: '0.7.4'),
  // htmx 4 — morph is core; SSE ships as the bundled `hx-sse` extension.
  // Separate output name so htmx 2 artifacts keep loading `htmx.min.js`.
  _Pkg('htmx.org', ['dist/htmx.min.js'], 'htmx4.min.js',
      version: _htmx4Pin, expect: true, expectPin: _htmx4Integrity),
  _Pkg('htmx.org', ['dist/ext/hx-sse.min.js', 'dist/ext/hx-sse.js'],
      'hx-sse.min.js', version: _htmx4Pin),
  // alien-signals: the signals runtime for island-kit.js (Phase 3c). The npm
  // package ships multi-file ESM (index.mjs imports system.mjs), so vendor-fetch
  // bundles it with esbuild into a single self-contained ESM file (~1.9 kB gzip).
  _Pkg('alien-signals', [], 'alien-signals.min.js', version: _alienSignalsPin,
      category: 'reactive-primitive'),
  // ADR-0009 v2 — state framework (Alpine + its htmx-4 bridge).
  _Pkg('alpinejs', ['dist/cdn.min.js'], 'alpine.min.js',
      version: _alpinePin, category: 'state-framework'),
  _Pkg('htmx.org', ['dist/ext/hx-alpine-compat.js'], 'hx-alpine-compat.js',
      version: _htmx4Pin, category: 'state-framework'),
  // ADR-0009 v2 — motion framework (GSAP core + the two plugins the
  // choreography layer leans on).
  _Pkg('gsap', ['dist/gsap.min.js'], 'gsap.min.js',
      version: _gsapPin, category: 'motion-framework'),
  _Pkg('gsap', ['dist/ScrollTrigger.min.js'], 'ScrollTrigger.min.js',
      version: _gsapPin, category: 'motion-framework'),
  _Pkg('gsap', ['dist/SplitText.min.js'], 'SplitText.min.js',
      version: _gsapPin, category: 'motion-framework'),
];

// ══ local patches on vendored files ════════════════════════════════════

/// A deliberate local edit carried on top of an upstream vendored file.
///
/// A patched vendor file has two silent failure modes and this repo hit both
/// at once in `de28917a`: `vendor-fetch` re-downloads the file and reverts the
/// edit without a word, and the SRI.md note warning about exactly that is
/// itself destroyed by the same command — SRI.md is regenerated wholesale at
/// the end of [vendorFetch], so a hand-written section in it survives until
/// the next run and no longer. A note that its own subject deletes is not a
/// safety net.
///
/// So the patch lives here as data instead. [vendorFetch] re-applies it on
/// every run, and [vendorSriDoc] renders it into SRI.md — which makes the
/// prose a product of this registry rather than something a run can quietly
/// drop. Adding a patch is one entry here; nothing else needs touching.
class VendorPatch {
  /// Manifest `file` name this applies to — matches `_Pkg.out`.
  final String file;

  /// Exact upstream text to replace. Must occur EXACTLY once in the download:
  /// 0 or 2+ occurrences is upstream drift and fails the fetch rather than
  /// guessing which site was meant.
  final String find;

  /// What [find] becomes. Must not be a substring of [find] or vice versa, or
  /// the already-applied check below cannot tell the two states apart.
  final String replace;

  /// Rendered into SRI.md verbatim. This is the ONLY place the reasoning
  /// lives now, so it carries the full provenance — including what was never
  /// verified. A generated doc loses whatever this field omits.
  final String why;

  const VendorPatch(
      {required this.file,
      required this.find,
      required this.replace,
      required this.why});
}

/// Empty since 2026-08-21, deliberately — and the machinery stays.
///
/// The one patch this registry ever held (model-viewer's far-plane multiplier,
/// 1×→60×) was investigated to ground: the file was vendored pristine, the 60
/// appeared as an uncommitted working-tree edit with no symptom recorded
/// anywhere in the repo, the value mathematically cannot cause or fix model
/// clipping (`far = 2 × max(farRadius(), maximumRadius)` covers the furthest
/// geometry under either multiplier), nothing the repo ships sets
/// `camera-orbit`/`max-camera-orbit`/`skybox-image` so no reachable scene
/// enters the one regime where the value acts — and measured there, 60× is the
/// WORSE arm (z-fighting through thin geometry, 3,561 px). Full evidence:
/// `docs/research/model-viewer-far-plane-verification.md`. The vendored file
/// is back at the pristine 4.3.1 bytes, verified against the recorded
/// upstream hash.
const vendorPatches = <VendorPatch>[];

/// Re-apply every [vendorPatches] entry for [file] to [bytes].
///
/// Three outcomes, not two. `find` present once → patch it. `find` absent but
/// `replace` already there → already patched, hand the bytes back unchanged.
/// Neither → throw. Collapsing the last two into "anchor missing = drift"
/// would report false drift on a file that is already correct, which is how a
/// loud check turns into a check people learn to ignore.
List<int> applyVendorPatches(String file, List<int> bytes,
    {List<VendorPatch>? registry}) {
  final patches =
      (registry ?? vendorPatches).where((p) => p.file == file).toList();
  if (patches.isEmpty) return bytes;
  // latin1 round-trips arbitrary bytes 1:1 where utf8 would not; the anchors
  // are ASCII, so matching is unaffected and re-encoding cannot corrupt the
  // rest of a 1MB minified bundle.
  var text = latin1.decode(bytes);
  for (final patch in patches) {
    final hits = patch.find.allMatches(text).length;
    if (hits == 1) {
      text = text.replaceFirst(patch.find, patch.replace);
      continue;
    }
    if (hits == 0 && text.contains(patch.replace)) continue; // already applied
    throw Exception(
        'local patch for $file no longer applies: the anchor occurs $hits '
        'times (expected exactly 1) and the patched form is absent. Upstream '
        'changed — re-derive the patch in vendorPatches; do NOT drop it. '
        'Anchor: ${patch.find}');
  }
  return latin1.encode(text);
}

/// Render SRI.md from [manifest] plus [vendorPatches].
///
/// Split out of [vendorFetch] so the committed file can be diffed against its
/// own generator with no network: `design_tools_test.dart` renders this from
/// the committed manifest.json and compares byte-for-byte. That test is what
/// makes the patch section impossible to lose — a hand-edit to SRI.md, or a
/// patch that stops being rendered, fails before anyone re-runs the fetch.
String vendorSriDoc(List<Map<String, String>> manifest,
    {List<VendorPatch>? registry}) {
  final b = StringBuffer()
    ..write('# Vendored client libraries (the `fetch.mjs` updater was archived;'
        ' re-vendor htmx + extensions via `appbox design vendor-fetch`)\n\n')
    ..write('| file | package | version | category | integrity |\n|---|---|---|---|---|\n')
    ..write(manifest
        .map((m) => '| ${m['file']} | ${m['package']} | ${m['version']} '
            '| ${m['category']} | `${m['integrity']}` |')
        .join('\n'))
    ..write('\n\n')
    ..write('`leaflet/images/*.png` (marker + layers control sprites, referenced by\n'
        '`leaflet.css` relative to itself) ride along unpinned — like the lucide SVGs\n'
        'they are never loaded as a subresource with an integrity attribute.\n');

  final shipped = manifest.map((m) => m['file']).toSet();
  final applied = (registry ?? vendorPatches)
      .where((p) => shipped.contains(p.file))
      .toList();
  if (applied.isEmpty) return b.toString();

  // Paragraphs are emitted unwrapped, one per line, so the generated section
  // never depends on where a Dart string literal happened to break.
  b.write('\n## Local patches — files that DIVERGE from the upstream release\n\n'
      'Each entry below is re-applied automatically by `appbox design '
      'vendor-fetch`, and this section is generated from the `vendorPatches` '
      'registry in `design_tools.dart` — so neither the patch nor this note '
      'can be lost to a re-run. If an anchor stops matching, the fetch FAILS '
      'rather than silently shipping upstream behaviour.\n\n'
      'The `integrity` column above is the hash of each file **as patched, on '
      'disk**; the upstream hash is recorded per patch below, so the '
      'divergence stays visible instead of being flattened into one number.\n');
  for (final patch in applied) {
    final row = manifest.firstWhere((m) => m['file'] == patch.file);
    b.write('\n### ${patch.file} — ${row['package']} ${row['version']}\n\n'
        '${patch.why}\n\n'
        '```js\n// upstream\n${patch.find}\n// patched\n${patch.replace}\n```\n\n'
        '- upstream integrity: `${row['upstreamIntegrity'] ?? '(unrecorded)'}`\n'
        '- patched integrity (the `integrity` column above): '
        '`${row['integrity']}`\n');
  }
  return b.toString();
}

/// Compute the SRI hash of [buf] via `openssl dgst -sha384 -binary`. macOS
/// ships openssl as a base tool; appboxd has no sha384 in-tree.
/// (kimitail: swap for a pure-Dart sha384 if a no-spawn env needs it.)
Future<String> sri(List<int> buf) async {
  final proc = await Process.start('openssl', ['dgst', '-sha384', '-binary']);
  proc.stdin.add(buf);
  await proc.stdin.close();
  final out = <int>[];
  await for (final chunk in proc.stdout) {
    out.addAll(chunk);
  }
  await proc.exitCode;
  return 'sha384-${base64.encode(out)}';
}

/// One row of the vendor manifest. Shape pinned by fetch.mjs, extended by
/// ADR-0009: `{file, package, version, integrity, category}`.
///
/// [integrity] always describes the file actually written to disk. When a
/// [VendorPatch] changed it, [upstreamIntegrity] carries the hash of the
/// pristine download — its presence IS the "this file diverges" flag, so
/// there is no separate boolean that can fall out of sync with it.
Map<String, String> manifestEntry(
    {required String file,
    required String pkg,
    required String version,
    required String integrity,
    String? upstreamIntegrity,
    String category = 'hypermedia'}) =>
    {'file': file, 'package': pkg, 'version': version, 'integrity': integrity,
      'upstreamIntegrity': ?upstreamIntegrity,
      'category': category};

Future<List<int>?> _httpGet(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final buf = <int>[];
    await for (final c in res) {
      buf.addAll(c);
    }
    return buf;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<String> _latestVersion(String npmBase, String pkg) async {
  final buf = await _httpGet('$npmBase/$pkg/latest');
  if (buf == null) throw Exception('npm registry: $pkg unreachable');
  return (jsonDecode(utf8.decode(buf)) as Map)['version'] as String;
}

/// Minimal ustar reader (npm tarballs here have no GNU longname entries).
/// Ported from fetch.mjs's `untar`.
List<(String, List<int>)> _untar(List<int> buf) {
  final files = <(String, List<int>)>[];
  var off = 0;
  while (off + 512 <= buf.length) {
    final h = buf.sublist(off, off + 512);
    if (h.every((b) => b == 0)) break;
    String str(int a, int b) =>
        utf8.decode(h.sublist(a, b)).replaceAll(RegExp('\u0000.*'), '');
    final size = int.tryParse(str(124, 136).trim(), radix: 8) ?? 0;
    off += 512;
    // typeflag at 156: '0' or NUL = regular file.
    if ((h[156] == 48 || h[156] == 0) && size > 0) {
      final prefix = str(345, 500);
      final name = '${prefix.isEmpty ? '' : '$prefix/'}${str(0, 100)}';
      files.add((name, buf.sublist(off, off + size)));
    }
    off += (size / 512).ceil() * 512;
  }
  return files;
}

/// Fetch + pin the vendored client libraries. [baseUrl] replaces the jsdelivr
/// CDN root and [registryBase] the npm registry root, so tests can point at a
/// local `HttpServer`. [htmxIntegrity] overrides the recorded pin (tests pass a
/// digest computed from the bytes they serve).
/// [only] narrows the run to the named npm packages. It exists so a test can
/// drive ONE package end-to-end against a local HttpServer: a full run needs a
/// valid lucide tarball and a working esbuild, which no fake server can
/// provide, and without this seam the patch re-application below would be
/// untested code. Not exposed on the CLI — it rewrites manifest.json and
/// SRI.md to the narrowed subset, which is only ever right in a temp dir.
Future<CmdResult> vendorFetch(String vendorDir,
    {String? baseUrl,
    String? registryBase,
    String? htmxIntegrity,
    Set<String>? only,
    List<VendorPatch>? registry}) async {
  final cdn = baseUrl ?? 'https://cdn.jsdelivr.net/npm';
  final npm = registryBase ?? 'https://registry.npmjs.org';
  final expectPin = htmxIntegrity ?? _htmxIntegrity;
  Directory(vendorDir).createSync(recursive: true);
  final out = <String>[];
  final err = <String>[];
  final manifest = <Map<String, String>>[];

  for (final pkg in _packages) {
    if (only != null && !only.contains(pkg.pkg)) continue;
    // Lucide icon set: every SVG inlined server-side, no per-file SRI; the
    // manifest records the tarball hash instead. Handled inline (not after the
    // loop) so the manifest row order survives a re-run byte-identically.
    if (pkg.pkg == 'lucide-static') {
      try {
        final v = pkg.version!;
        final tgz = await _httpGet('$npm/lucide-static/-/lucide-static-$v.tgz');
        if (tgz == null) {
          throw Exception('npm registry: lucide-static tarball unreachable');
        }
        final icons = _untar(GZipCodec().decode(tgz))
            .where(
                (e) => RegExp(r'^package/icons/[a-z0-9-]+\.svg$').hasMatch(e.$1))
            .toList();
        if (icons.length < 1000) {
          throw Exception('suspiciously few icons extracted: ${icons.length}');
        }
        final lucideDir = Directory(p.join(vendorDir, 'lucide', 'icons'));
        if (lucideDir.existsSync()) lucideDir.deleteSync(recursive: true);
        lucideDir.createSync(recursive: true);
        for (final (name, data) in icons) {
          File(p.join(lucideDir.path, p.basename(name))).writeAsBytesSync(data);
        }
        manifest.add(manifestEntry(
            file: pkg.out, pkg: pkg.pkg, version: v,
            integrity: await sri(tgz), category: pkg.category));
        out.add('✓ ${pkg.out} ← lucide-static@$v (${icons.length} icons)');
      } catch (e) {
        err.add('✗ lucide-static: $e');
        return CmdResult(1, stdoutLines: out, stderrLines: err);
      }
      continue;
    }
    // alien-signals: multi-file ESM (index.mjs imports system.mjs). Download
    // both, bundle with esbuild into a single self-contained ESM file. The npm
    // package has no dist/ — only esm/ and cjs/.
    if (pkg.pkg == 'alien-signals') {
      try {
        final v = pkg.version!;
        final tmpDir = Directory.systemTemp.createTempSync('alien-signals');
        try {
          for (final part in ['index.mjs', 'system.mjs']) {
            final buf = await _httpGet('$cdn/alien-signals@$v/esm/$part');
            if (buf == null) throw Exception('esm/$part unreachable');
            File(p.join(tmpDir.path, part)).writeAsBytesSync(buf);
          }
          final outFile = File(p.join(vendorDir, pkg.out));
          outFile.parent.createSync(recursive: true);
          final result = await Process.run('npx', [
            'esbuild',
            p.join(tmpDir.path, 'index.mjs'),
            '--bundle',
            '--format=esm',
            '--minify',
            '--outfile=${outFile.path}',
          ]);
          if (result.exitCode != 0) {
            throw Exception('esbuild failed: ${result.stderr}');
          }
          final buf = outFile.readAsBytesSync();
          final integrity = await sri(buf);
          if (integrity != _alienSignalsIntegrity) {
            throw Exception(
                'integrity mismatch! got $integrity, expected $_alienSignalsIntegrity');
          }
          manifest.add(manifestEntry(
              file: pkg.out, pkg: pkg.pkg, version: v, integrity: integrity,
              category: pkg.category));
          out.add('✓ ${pkg.out} ← alien-signals@$v (${buf.length} bytes, esbuild bundled)');
        } finally {
          tmpDir.deleteSync(recursive: true);
        }
      } catch (e) {
        err.add('✗ alien-signals: $e');
        return CmdResult(1, stdoutLines: out, stderrLines: err);
      }
      continue;
    }
    try {
      final v = pkg.version ?? await _latestVersion(npm, pkg.pkg);
      List<int>? buf;
      for (final cand in pkg.candidates) {
        buf = await _httpGet('$cdn/${pkg.pkg}@$v/$cand');
        if (buf != null) break;
      }
      if (buf == null) {
        throw Exception('no candidate file found: ${pkg.candidates.join(", ")}');
      }
      // Pin check runs on the PRISTINE download — a local patch must never be
      // able to make a tampered upstream file hash correctly.
      final upstream = await sri(buf);
      final expected = pkg.expectPin ?? expectPin;
      if (pkg.expect && upstream != expected) {
        throw Exception('integrity mismatch! got $upstream, expected $expected');
      }
      // Re-apply local edits before writing. This is the whole reason
      // vendorPatches exists: without it every run silently reverts them.
      final patched = applyVendorPatches(pkg.out, buf, registry: registry);
      // `identical` is false when the already-patched branch hands back a
      // re-encoded copy, so compare hashes too: without this, a download that
      // ARRIVES pre-patched would record upstreamIntegrity == integrity — a
      // divergence flag on a file that does not diverge. Unreachable from a
      // real CDN, reachable from a mirror that serves a patched build.
      final integrity =
          identical(patched, buf) ? upstream : await sri(patched);
      final unpatched = integrity == upstream;
      final outFile = File(p.join(vendorDir, pkg.out));
      outFile.parent.createSync(recursive: true); // leaflet/* lives in a subdir
      outFile.writeAsBytesSync(patched);
      manifest.add(manifestEntry(
          file: pkg.out, pkg: pkg.pkg, version: v, integrity: integrity,
          upstreamIntegrity: unpatched ? null : upstream,
          category: pkg.category));
      out.add('✓ ${pkg.out} ← ${pkg.pkg}@$v (${patched.length} bytes'
          '${unpatched ? '' : ', local patch re-applied'})');
    } catch (e) {
      // No optional/skip branch by design. The one entry that used it named a
      // package that does not exist on npm, so every run printed "– skipped"
      // and still exited 0 — the vendored file was missing for as long as the
      // entry existed and nothing went red. A vendored asset is either pinned
      // in the manifest or it is a failure.
      err.add('✗ ${pkg.pkg}: $e');
      return CmdResult(1, stdoutLines: out, stderrLines: err);
    }
  }

  File(p.join(vendorDir, 'manifest.json'))
      .writeAsStringSync("${const JsonEncoder.withIndent('  ').convert(manifest)}\n");
  File(p.join(vendorDir, 'SRI.md'))
      .writeAsStringSync(vendorSriDoc(manifest, registry: registry));
  out.add('');
  out.add('${manifest.length} libraries vendored → $vendorDir');
  return CmdResult(0, stdoutLines: out, stderrLines: err);
}

/// `appbox design vendor-fetch [--vendor <dir>]` — exit 0 vendored / 1 failed.
Future<CmdResult> designVendorFetch(List<String> args) async {
  String? vendorDir;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--vendor' && i + 1 < args.length) {
      vendorDir = args[++i];
    } else {
      return CmdResult(2,
          stderrLines: const ['usage: appbox design vendor-fetch [--vendor <dir>]']);
    }
  }
  final repo = _findRepoRoot() ?? Directory.current.path;
  vendorDir ??= '$repo/skills/appbox-designer/runtime/vendor';
  return vendorFetch(vendorDir);
}

// ══ doctor ════════════════════════════════════════════════════════════

/// One preflight row. Post-port semantics: the .mjs checked node/playwright
/// deps that no longer exist; this checks the Dart toolchain the gates now use.
class DoctorRow {
  final bool ok;
  final String name;
  final String detail;
  final String fix;
  const DoctorRow(this.ok, this.name, this.detail, this.fix);
}

class DoctorReport {
  final List<DoctorRow> rows;
  DoctorReport(this.rows);

  int get exitCode => rows.any((r) => !r.ok) ? 1 : 0;

  List<String> get stdoutLines {
    final out = <String>[];
    for (final r in rows) {
      out.add("${r.ok ? '  ok  ' : '  MISS'} ${r.name.padRight(28)} ${r.detail}");
    }
    final failed = rows.where((r) => !r.ok).length;
    if (failed > 0) {
      out.add('');
      out.add('$failed missing. To fix:');
      final seen = <String>{};
      for (final r in rows) {
        if (!r.ok && seen.add(r.fix)) out.add('  ${r.fix}');
      }
      out.add('');
      out.add('The render and console gates cannot run until these are present.');
      out.add('Do not proceed and report the design as verified — it will not be.');
    } else {
      out.add('');
      out.add('all present — render and console gates can run');
    }
    return out;
  }
}

/// Real probes for the Dart toolchain. [runtimeDir] is the skill's runtime/
/// (where the vendored libs + ladder.json live).
List<DoctorRow> _realRows(String runtimeDir) {
  final rows = <DoctorRow>[];

  // Dart ≥ 3.12 (SDK this port targets).
  var dartOk = false;
  var dartDetail = 'dart not on PATH';
  try {
    final r = Process.runSync('dart', ['--version']);
    if (r.exitCode == 0) {
      final out = (r.stderr as String).trim().isEmpty
          ? (r.stdout as String).trim()
          : (r.stderr as String).trim();
      final m = RegExp(r'(\d+)\.(\d+)').firstMatch(out);
      if (m != null) {
        final major = int.parse(m.group(1)!);
        final minor = int.parse(m.group(2)!);
        dartOk = major > 3 || (major == 3 && minor >= 12);
        dartDetail = 'found ${m.group(0)}';
      } else {
        dartDetail = out;
      }
    }
  } catch (e) {
    dartDetail = e.toString();
  }
  rows.add(DoctorRow(
      dartOk, 'dart ≥ 3.12', dartDetail, 'install Dart 3.12+ (dart.dev)'));

  // Chrome (the lens/render gate driver).
  var chromeOk = false;
  var chromeDetail = 'chrome not found';
  try {
    final exe = CdpClient.defaultChromePath();
    chromeOk = File(exe).existsSync();
    chromeDetail = chromeOk ? 'chrome present' : 'chrome not at $exe';
  } catch (e) {
    chromeDetail = e.toString();
  }
  rows.add(DoctorRow(chromeOk, 'chrome (headless)', chromeDetail,
      'install Google Chrome'));

  // ffmpeg (the lens video/motion probes).
  var ffOk = false;
  var ffDetail = 'ffmpeg not on PATH';
  try {
    final r = Process.runSync('ffmpeg', ['-version']);
    ffOk = r.exitCode == 0;
    if (ffOk) ffDetail = 'ffmpeg present';
  } catch (_) {}
  rows.add(DoctorRow(
      ffOk, 'ffmpeg', ffDetail, 'brew install ffmpeg (or your package manager)'));

  // Vendored client libraries + ladder config.
  final htmx = File(p.join(runtimeDir, 'vendor', 'htmx.min.js'));
  rows.add(DoctorRow(htmx.existsSync(), 'runtime/vendor/htmx.min.js',
      htmx.existsSync() ? 'present' : 'missing',
      'restore the vendored client libraries — they are committed, not installed'));

  final ladder = File(p.join(runtimeDir, 'ladder.json'));
  var ladderDetail = 'missing';
  if (ladder.existsSync()) {
    final rungs = (jsonDecode(ladder.readAsStringSync())['rungs'] as Map);
    ladderDetail = 'rungs: ${rungs.keys.join(", ")}';
  }
  rows.add(DoctorRow(ladder.existsSync(), 'runtime/ladder.json', ladderDetail,
      'restore runtime/ladder.json — the viewport ladder is config, not code'));

  return rows;
}

/// Run the doctor probes. [probes] injects rows for tests; the default runs
/// the real Dart-toolchain probes against [runtimeDir] (the skill runtime, or
/// repo-root-relative when null).
DoctorReport doctorCheck({Iterable<DoctorRow>? probes, String? runtimeDir}) {
  final rows = probes?.toList() ?? _realRows(runtimeDir ?? skillRuntimeDir());
  return DoctorReport(rows);
}

/// The designer skill's runtime/ dir resolved from the appbox INSTALLATION,
/// not the CWD: CWD walk-up first (in-repo use unchanged), then the running
/// script's location (the PATH wrapper runs
/// `dart run /…/app-box/appboxd/bin/appbox.dart` from any folder — a
/// from-scratch project must not make doctor report the checkout's own
/// committed runtime as missing).
String skillRuntimeDir() =>
    p.join(_findRepoRoot() ?? scriptRepoRoot() ?? Directory.current.path,
        'skills', 'appbox-designer', 'runtime');

/// Locates the appbox checkout that is executing, wherever the user's CWD
/// sits. Two anchors, most-reliable first: this library's own package URI
/// (resolves under both `dart run` and `dart test`), then the running
/// script's file. Walk-up stops at the repo marker config/appbox.config.json.
///
/// Public because the design server's resource resolvers (worker assets,
/// runtime vendor, icons, node_modules) share the same requirement: skills
/// invoke `appbox` from a client checkout or ~/.appbox, and a CWD walk never
/// reaches app-box from there.
String? scriptRepoRoot() {
  for (final anchor in <Uri?>[
    () {
      try {
        return Isolate.resolvePackageUriSync(
            Uri.parse('package:appboxd/design_tools.dart'));
      } catch (_) {
        return null;
      }
    }(),
    Platform.script,
  ]) {
    if (anchor == null || anchor.scheme != 'file') continue;
    var dir = File.fromUri(anchor).parent;
    while (true) {
      if (File(p.join(dir.path, 'config', 'appbox.config.json'))
          .existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  return null; // AOT/compiled contexts without a source-file anchor
}

/// `appbox design doctor` — exit 0 all-present / 1 missing.
CmdResult designDoctor(List<String> args) {
  final report = doctorCheck();
  return CmdResult(report.exitCode, stdoutLines: report.stdoutLines);
}

// ══ eject (Task 20.5) ═══════════════════════════════════════════════════
// Ported from skills/appbox-designer/runtime/eject.mjs. Same steps (copy the
// artifact; narrow vendor/ to the libs its HTML actually loads, with the
// htmx-required HARD FAIL; write the narrowed manifest) — but the .mjs's
// package.json + node-runtime copy + smoke.test.mjs become a README carrying
// a checked `appbox design serve . --no-watch` line: ejected artifacts run on
// the same Dart design server, no node anywhere.

/// `/assets/vendor/<path>.(js|css)` references in artifact HTML — subpaths
/// included, so e.g. `leaflet/leaflet.js` and `leaflet/leaflet.css` match.
/// (eject.mjs §2b.)
final _vendorRefRe = RegExp(r'/assets/vendor/([\w./-]+\.(?:js|css))');

/// Recursive copy of a directory tree (files only; parents auto-created).
/// Dart stdlib has no recursive copy — this is `cpSync(src, dst, {recursive})`.
void _copyTree(String src, String dst) {
  final srcDir = Directory(src);
  if (!srcDir.existsSync()) return;
  for (final f in srcDir.listSync(recursive: true).whereType<File>()) {
    final rel = p.relative(f.path, from: src);
    final target = File(p.join(dst, rel))..parent.createSync(recursive: true);
    f.copySync(target.path);
  }
}

/// Copy all *.js, *.d.ts, and *.tsx files from [srcDir] to [dstDir], preserving
/// relative paths. TSX is included so render.tsx and icon.tsx ship in the eject.
void _copyJsTree(Directory srcDir, String dstDir) {
  if (!srcDir.existsSync()) return;
  for (final f in _walk(srcDir)) {
    if (!f.path.endsWith('.js') && !f.path.endsWith('.d.ts') && !f.path.endsWith('.tsx')) continue;
    final rel = p.relative(f.path, from: srcDir.path);
    final target = File(p.join(dstDir, rel))..parent.createSync(recursive: true);
    f.copySync(target.path);
  }
}

/// esbuild invocation for the eject path: prefer the skill's lockfile-pinned
/// binary (skills/appbox-designer/runtime devDependency), fall back to npx
/// with an exact pinned version — never a floating `npx esbuild`.
(String, List<String>) _esbuildCmd(String repo) {
  final local = p.join(repo, 'skills', 'appbox-designer', 'runtime',
      'node_modules', '.bin', 'esbuild');
  if (File(local).existsSync()) return (local, const []);
  return ('npx', const ['--yes', 'esbuild@0.25.12']);
}

/// `appbox design eject <artifact-dir> <out-dir>` — exit 2 usage / 1 vendor
/// or htmx-required fail / 0 ejected. Ported from eject.mjs; the .mjs's
/// node-runtime + package.json + smoke.test.mjs are replaced by a README.
Future<CmdResult> designEject(List<String> args) async {
  // Parse --target=node|cloudflare|vercel (default node) and --kits=dir,dir.
  String? target;
  final kits = <String>[];
  final positional = <String>[];
  void addKits(String v) =>
      kits.addAll(v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--target' && i + 1 < args.length) {
      target = args[++i];
    } else if (args[i].startsWith('--target=')) {
      target = args[i].substring(9);
    } else if (args[i] == '--kits' && i + 1 < args.length) {
      addKits(args[++i]);
    } else if (args[i].startsWith('--kits=')) {
      addKits(args[i].substring(7));
    } else {
      positional.add(args[i]);
    }
  }
  if (positional.length < 2) {
    return CmdResult(2,
        stderrLines: const [
          'usage: appbox design eject <artifact-dir> <out-dir> '
              '[--target=node|cloudflare|vercel] [--kits=a,b]'
        ]);
  }
  target ??= 'node';
  if (!const ['node', 'cloudflare', 'vercel'].contains(target)) {
    return CmdResult(2,
        stderrLines: ['unknown target: $target (use node, cloudflare, or vercel)']);
  }
  final artifact = p.absolute(positional[0]);
  final out = p.absolute(positional[1]);
  final repo = _findRepoRoot() ?? Directory.current.path;
  final vendorDir =
      p.join(repo, 'skills', 'appbox-designer', 'runtime', 'vendor');

  // Project name from the artifact basename (eject.mjs's slugify).
  final slug = p
      .basename(artifact)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final name = slug.isEmpty ? 'artifact' : slug;

  // 1. The artifact itself.
  _copyTree(artifact, out);

  // 1-phase scan: detect [hx-island] usage + wanted vendor refs in one walk.
  final islandRe = RegExp(r'hx-island="([^"]+)"');
  final islandNames = <String>{};
  final wanted = <String>{};
  for (final f in _walk(Directory(artifact))) {
    if (!f.path.endsWith('.html') && !f.path.endsWith('.tsx')) continue;
    final html = f.readAsStringSync();
    for (final m in islandRe.allMatches(html)) {
      islandNames.add(m.group(1)!);
    }
    for (final m in _vendorRefRe.allMatches(html)) {
      wanted.add(m.group(1)!);
    }
  }
  final hasIslands = islandNames.isNotEmpty;
  // alien-signals is imported by island-kit.js (not referenced in HTML), so the
  // narrowing scan misses it. Force-include when islands are present.
  if (hasIslands) wanted.add('alien-signals.min.js');

  // Both guards fail the eject rather than shipping: an empty vendor/ would
  // turn this trim into an outage, and the symptom — every interaction inert,
  // nothing in the console — is the failure this stack is worst at surfacing.
  final available = Directory(vendorDir).existsSync()
      ? Directory(vendorDir)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.relative(f.path, from: vendorDir).replaceAll('\\', '/'))
          .where((n) => n.endsWith('.js') || n.endsWith('.css'))
          .toSet()
      : <String>{};
  final missing = wanted.where((f) => !available.contains(f)).toList()..sort();
  if (missing.isNotEmpty) {
    return CmdResult(1, stderrLines: [
      'markup loads libraries that are not vendored: ${missing.join(', ')}',
    ]);
  }
  // Accept either htmx 2 (htmx.min.js) or htmx 4 (htmx4.min.js).
  if (!wanted.any((f) => f == 'htmx.min.js' || f == 'htmx4.min.js')) {
    return CmdResult(1,
        stderrLines: const [
          'no artifact HTML loads htmx (htmx.min.js for 2.x or '
          'htmx4.min.js for 4.x) — refusing to eject',
        ]);
  }

  // Warn (not fail) when the artifact loads htmx 2: production eject expects
  // htmx 4 (morph is core, SSE ships as the bundled hx-sse extension).
  final warnings = <String>[];
  if (wanted.contains('htmx.min.js') && !wanted.contains('htmx4.min.js')) {
    warnings.add(
        '⚠ artifact loads htmx 2.x (htmx.min.js) — production eject expects '
        'htmx 4 (htmx4.min.js). Morphing is core in v4; SSE is the bundled '
        'hx-sse extension.');
  }

  final outVendor =
      Directory(p.join(out, 'runtime', 'vendor'))..createSync(recursive: true);
  // A referenced path under a subdirectory (leaflet/leaflet.js) rides with its
  // whole subdir — leaflet.css references its marker sprites in images/
  // relative to itself, so per-file copying would ship a map with no markers.
  final copiedDirs = <String>{};
  for (final f in wanted) {
    final slash = f.indexOf('/');
    if (slash < 0) {
      File(p.join(vendorDir, f)).copySync(p.join(outVendor.path, f));
    } else if (copiedDirs.add(f.substring(0, slash))) {
      _copyTree(
          p.join(vendorDir, f.substring(0, slash)),
          p.join(outVendor.path, f.substring(0, slash)));
    }
  }
  // Non-node targets serve static files from a platform static root
  // (Cloudflare's [assets] binding directory, Vercel's public/) — serveStatic
  // is node-only, so mirror the narrowed vendor set where /assets/vendor/*
  // actually resolves. Lucide/manifest stay out: icons are server-side
  // (preload on Workers, fs elsewhere).
  if (target != 'node') {
    final assetsVendor = p.join(out, 'assets', 'vendor');
    final mirrored = <String>{};
    for (final f in wanted) {
      final slash = f.indexOf('/');
      if (slash < 0) {
        final dest = File(p.join(assetsVendor, f))
          ..parent.createSync(recursive: true);
        File(p.join(vendorDir, f)).copySync(dest.path);
      } else if (mirrored.add(f.substring(0, slash))) {
        _copyTree(p.join(vendorDir, f.substring(0, slash)),
            p.join(assetsVendor, f.substring(0, slash)));
      }
    }
  }
  // Lucide icons are used server-side by the icon() template function — never
  // referenced in HTML, so the narrowing scan misses them. Always include them.
  final lucideSrc = Directory(p.join(vendorDir, 'lucide'));
  if (lucideSrc.existsSync()) {
    _copyTree(lucideSrc.path, p.join(outVendor.path, 'lucide'));
  }

  // Provenance travels with the copy: the same rows, narrowed to what shipped.
  final manifest =
      jsonDecode(File(p.join(vendorDir, 'manifest.json')).readAsStringSync())
          as List;
  final narrowed = manifest
      .whereType<Map>()
      .where((e) => wanted.contains(e['file']))
      .toList();
  File(p.join(outVendor.path, 'manifest.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(narrowed)}\n');

  // 3. JS runtime scaffold (eject web productionization — Phase 1).
  //    The runtime modules + entry points ship as templates under the skill's
  //    runtime/eject/. Eject copies them and generates the target-specific
  //    config. The artifact contract is untouched — all machinery lives here.
  final ejectSrc = p.join(repo, 'skills', 'appbox-designer', 'runtime', 'eject');

  // 3a. Runtime modules (shared across targets).
  _copyJsTree(Directory(p.join(ejectSrc, 'runtime')), p.join(out, 'runtime'));

  // 3a-bis. Islands machinery (Phase 3 — eject-only).
  //   Client-side loader (islands.js) + binding layer (island-kit.js) go to
  //   out/assets/. Each referenced island is bundled by esbuild into
  //   out/assets/islands/<name>.js with sha384 SRI. The manifest + module
  //   script are injected into the ejected base.html so the browser loads
  //   zero island JS until a condition fires.
  if (hasIslands) {
    final islandsSrc = Directory(p.join(ejectSrc, 'assets'));
    if (islandsSrc.existsSync()) {
      _copyJsTree(islandsSrc, p.join(out, 'assets'));
    }

    // Bundle each island with esbuild → out/assets/islands/<name>.js (ESM).
    final esbuild = _esbuildCmd(repo);
    final islandManifest = <String, Map<String, String>>{};
    final islandsOut =
        Directory(p.join(out, 'assets', 'islands'))..createSync(recursive: true);
    for (final islandName in islandNames) {
      final src = p.join(vendorDir, '${islandName}_island.js');
      if (!File(src).existsSync()) continue; // developer-added island (no vendor source)
      final chunk = p.join(islandsOut.path, '$islandName.js');
      final result = await Process.run(
          esbuild.$1, [...esbuild.$2, src, '--bundle', '--format=esm', '--minify', '--outfile=$chunk']);
      if (result.exitCode != 0) {
        return CmdResult(1, stderrLines: [
          'esbuild failed for island "$islandName": ${result.stderr}',
        ]);
      }
      islandManifest[islandName] = {
        'src': '/assets/islands/$islandName.js',
        'integrity': await sri(File(chunk).readAsBytesSync()),
      };
    }

    // Inject island manifest + module script into the ejected base.tsx.
    // esbuild bundles base.tsx (via the view → shell → base import chain) after
    // this step, so the injection lands in the final render.js.
    if (islandManifest.isNotEmpty) {
      // Fail loudly: a missing anchor would silently ship inert islands (the
      // failure mode this stack is worst at surfacing).
      final baseTsx = File(p.join(out, 'ui', 'common', 'base.tsx'));
      if (!baseTsx.existsSync()) {
        return CmdResult(1, stderrLines: const [
          'islands referenced but ui/common/base.tsx is missing — nowhere to '
              'inject the island manifest',
        ]);
      }
      final src = baseTsx.readAsStringSync();
      if (!src.contains('<div id="toasts"')) {
        return CmdResult(1, stderrLines: const [
          'island-manifest injection anchor <div id="toasts" not found in '
              'ui/common/base.tsx — add it to the shell or drop the islands',
        ]);
      }
      final manifestJson =
          const JsonEncoder.withIndent('  ').convert(islandManifest);
      final scriptContent = '<script type="application/json" id="island-manifest">'
          '$manifestJson</script>\n'
          '<script type="module" src="/assets/islands.js"></script>\n';
      final injection = '{raw(`$scriptContent`)}\n        ';
      baseTsx.writeAsStringSync(
          src.replaceFirst('<div id="toasts"', '$injection<div id="toasts"'));
    }
  }

  // 3b. Entry point + config per target.
  final isWorkers = target == 'cloudflare';
  final isVercel = target == 'vercel';
  final entrySrc = isWorkers
      ? p.join(ejectSrc, 'worker.js')
      : p.join(ejectSrc, isVercel ? 'vercel.js' : 'server.js');
  if (File(entrySrc).existsSync()) {
    File(p.join(out, isWorkers ? 'worker.js' : 'server.js'))
        .writeAsStringSync(File(entrySrc).readAsStringSync());
  }

  // 3c. package.json — target-specific deps.
  File(p.join(out, 'package.json'))
      .writeAsStringSync(_ejectPackageJson(name, target));

  // 3d. Target config.
  if (isWorkers) {
    File(p.join(out, 'wrangler.toml'))
        .writeAsStringSync(_ejectWrangler(name));
    // Workers have no fs — bundle templates/l10n/fixtures/icons into preload.js
    // and emit a target-specific fixture_reader.js.
    File(p.join(out, 'runtime', 'preload.js'))
        .writeAsStringSync(_generatePreload(artifact, vendorDir));
    final cfReader =
        File(p.join(out, 'services', 'repositories', 'fixture_reader.js'));
    if (cfReader.existsSync()) {
      // The replacement swaps ONLY the fs-backed readFixture. Artifacts may
      // author pure helpers after it (energize's anchorInternalHrefs — the
      // facades import it; dropping it killed the worker bundle, eject gap 1)
      // — carry that tail over verbatim.
      final tail = _fixtureReaderPureTail(cfReader.readAsStringSync());
      cfReader.writeAsStringSync(_cfFixtureReader + tail);
    }
    // Style barrels serve at /ui/styles/<owner>/ (the styles law) but the
    // [assets] binding root is ./assets — mirror them in and let worker.js
    // delegate the /ui/styles prefix (energize eject gap 3).
    final uiStyles = p.join(out, 'ui', 'styles');
    if (Directory(uiStyles).existsSync()) {
      _copyTree(uiStyles, p.join(out, 'assets', 'styles'));
    }
  } else {
    // Node/Vercel stub so icon.tsx's './preload.js' import resolves at bundle
    // and typecheck time; the cloudflare target writes the real bundle above.
    File(p.join(out, 'runtime', 'preload.js')).writeAsStringSync(_preloadStub);
  }
  if (isVercel) {
    // Vercel's zero-config Hono preset: server.js's default export becomes the
    // Function (no vercel.json needed) and static files serve from public/
    // only — relocate the asset tree (incl. the mirrored vendor set).
    final assets = Directory(p.join(out, 'assets'));
    if (assets.existsSync()) {
      Directory(p.join(out, 'public')).createSync();
      assets.renameSync(p.join(out, 'public', 'assets'));
    }
  }

  // 3e. Route manifest codegen + tsconfig (Phase 4: typing — the moat).
  _generateRouteManifest(artifact, out);
  final tsconfigSrc = p.join(ejectSrc, 'tsconfig.json');
  if (File(tsconfigSrc).existsSync()) {
    File(p.join(out, 'tsconfig.json')).writeAsStringSync(File(tsconfigSrc).readAsStringSync());
  }

  // 3e-bis. TSX render module — generate render.tsx from the artifact's .tsx
  // view inventory, then bundle to render.js via esbuild. The source render.tsx
  // (copied by _copyJsTree) is overwritten with the generated version.
  // helpers.js imports ./render.js at runtime; TypeScript resolves ./render.js
  // → ./render.tsx for typecheck via moduleResolution: "bundler".
  final generatedRender = generateRenderTsx(artifact);
  File(p.join(out, 'runtime', 'render.tsx')).writeAsStringSync(generatedRender);

  // Dead legacy template modules — nothing imports them in the TSX tree.
  for (final dead in ['templates.js', 'nunjucks.d.ts']) {
    final deadFile = File(p.join(out, 'runtime', dead));
    if (deadFile.existsSync()) deadFile.deleteSync();
  }

  // Bundle render.tsx → render.js (Node can't import .tsx directly). hono and
  // node:* stay external — they resolve from node_modules / Node built-ins.
  final renderJsPath = p.join(out, 'runtime', 'render.js');
  final esbuild = _esbuildCmd(repo);
  final esbuildResult = await Process.run(esbuild.$1, [
    ...esbuild.$2,
    p.join(out, 'runtime', 'render.tsx'),
    '--bundle', '--format=esm',
    '--outfile=$renderJsPath',
    '--external:hono', '--external:hono/*', '--external:node:*',
    // Keep preload.js out of the Workers render bundle — worker.js imports it
    // directly; inlining would ship the icon/fixture blob twice. (Node/Vercel
    // bundle the tiny stub, so no external needed there.)
    if (isWorkers) '--external:./preload.js',
  ]);
  if (esbuildResult.exitCode != 0) {
    return CmdResult(1, stderrLines: [
      'esbuild failed to bundle render.tsx:',
      esbuildResult.stderr.toString(),
    ]);
  }

  // 3f. Kit facades + .env.example (Phase 5: kits for web).
  final kitDeps = _emitKitsAndEnv(out, repo, target, kits);
  if (kitDeps.isNotEmpty) {
    // Merge kit npm deps into the generated package.json.
    final pkgPath = File(p.join(out, 'package.json'));
    final pkg = jsonDecode(pkgPath.readAsStringSync()) as Map<String, dynamic>;
    (pkg['dependencies'] as Map<String, dynamic>).addAll(kitDeps);
    pkgPath.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(pkg)}\n');
  }

  // 4. README — target-aware productionization guide.
  File(p.join(out, 'README.md')).writeAsStringSync(_ejectReadmeV2(name, target));

  return CmdResult(0,
      stdoutLines: [
        'ejected $artifact → $out (target: $target)',
        if (hasIslands) ...[
          'islands: ${islandNames.join(', ')} → bundled to assets/islands/ (lazy-loaded)',
        ],
        if (isWorkers) ...[
          'next: cd $out && npm install && npx wrangler dev',
        ] else ...[
          'next: cd $out && npm install && npm start',
        ],
      ],
      stderrLines: warnings);
}

/// Ejected-artifact package.json — target-specific deps.
String _ejectPackageJson(String name, String target) {
  final deps = <String, String>{
    'hono': '^4.12.31',
    'zod': '^3.24.0',
  };
  final devDeps = <String, String>{
    'typescript': '^5.7.0',
    '@types/node': '^22.0.0',
  };
  String startScript;
  switch (target) {
    case 'cloudflare':
      devDeps['wrangler'] = '^4.0.0'; // deploy tool, not a runtime dep
      startScript = 'wrangler dev';
      break;
    case 'vercel':
      devDeps['vercel'] = '^41.0.0'; // deploy tool, not a runtime dep
      startScript = 'vercel dev';
      break;
    default:
      deps['@hono/node-server'] = '^2.0.11';
      startScript = 'node server.js';
  }
  final pkg = {
    'name': name,
    'version': '1.0.0',
    'private': true,
    'type': 'module',
    'scripts': {
      'start': startScript,
      // tsconfig already sets noEmit — the flag would just restate it.
      'typecheck': 'tsc -p .',
    },
    'dependencies': deps,
    'devDependencies': devDeps,
  };
  return '${const JsonEncoder.withIndent('  ').convert(pkg)}\n';
}

/// wrangler.toml for the Cloudflare Workers target.
String _ejectWrangler(String name) => '''name = "$name"
compatibility_date = "2026-08-06"
# nodejs_compat: the runtime modules import node builtins statically
# (node:url/node:path in router.js + icon.tsx, node:fs in l10n.js,
# node:async_hooks in timers.js). Without the flag workerd fails at module
# load ("No such module node:url") before any request runs. The imports
# resolve but fs is never CALLED on Workers — templates/l10n/icons/fixtures
# come from runtime/preload.js instead.
compatibility_flags = ["nodejs_compat"]
main = "worker.js"

[assets]
directory = "./assets"
binding = "ASSETS"

# Env vars: add secrets/vars from credentials.catalog.json (Phase 5 kits).
# [vars]
# STRIPE_PUBLISHABLE_KEY = "set me"
# Run `wrangler secret put STRIPE_SECRET_KEY` for server secrets.
''';

/// Node/Vercel stub for runtime/preload.js — the cloudflare target writes the
/// real bundle (l10n catalogs, fixtures, Lucide icons). The stub keeps
/// icon.tsx's `./preload.js` import resolvable at esbuild-bundle and
/// `tsc --checkJs` time; `preload = null` means "use the filesystem".
const _preloadStub = '''
// preload.js — node/vercel stub. The cloudflare target replaces this file at
// eject time with the real bundle (arb catalogs, fixtures, Lucide icons).
/** @type {{ arb?: Record<string, unknown>, fixtures?: Record<string, unknown>, iconSvg?: Record<string, string> } | null} */
export const preload = null;
''';

/// Cloudflare Workers fixture_reader.js — reads from preload (no node:fs).
const _cfFixtureReader = r"""
// Cloudflare Workers fixture reader — reads from runtime/preload.js (no node:fs).
// Replaces the node version (which uses readFileSync) at eject time for the
// cloudflare target. Same export: readFixture(relFromThisFile) → parsed JSON.
import { preload } from '../../runtime/preload.js';

const cache = new Map();

/** @param {string} relFromThisFile @returns {unknown} */
export function readFixture(relFromThisFile) {
  if (cache.has(relFromThisFile)) return cache.get(relFromThisFile);
  const key = relFromThisFile.replace(/^(\.\.\/)+/, '');
  const data = /** @type {Record<string, unknown>} */ (preload.fixtures)[key];
  if (!data) throw new Error('fixture not bundled: ' + relFromThisFile);
  cache.set(relFromThisFile, data);
  return data;
}
""";

/// The artifact-authored pure tail of a fixture_reader: everything after
/// the closing brace of `readFixture` (helpers, consts, comments). The CF
/// replacement keeps only readFixture semantics; the tail is pure JS with no
/// node:fs dependency, so it rides along verbatim. Empty when the artifact
/// authors no helpers (hello-hda) — the common case.
String _fixtureReaderPureTail(String src) {
  final start = src.indexOf('export function readFixture');
  if (start < 0) return '';
  final open = src.indexOf('{', start);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        final tail = src.substring(i + 1).trim();
        return tail.isEmpty ? '' : '\n\n$tail\n';
      }
    }
  }
  return '';
}

/// Generates runtime/preload.js for the cloudflare target — bundles ARB
/// catalogs, fixture JSON, and Lucide icons into a single ESM module so the
/// Worker has no filesystem dependency. (TSX templates are compiled into
/// render.js by esbuild — no template source bundling needed.)
String _generatePreload(String artifactDir, String vendorDir) {
  final arb = <String, dynamic>{};
  final fixtures = <String, dynamic>{};
  final iconSvg = <String, String>{};

  final l10nDir = Directory(p.join(artifactDir, 'l10n'));
  if (l10nDir.existsSync()) {
    for (final f in l10nDir.listSync().whereType<File>()) {
      final m = RegExp(r'^app_(.+)\.arb$').firstMatch(p.basename(f.path));
      if (m == null) continue;
      final src = f.readAsStringSync().split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      final entries = jsonDecode(src) as Map<String, dynamic>;
      arb[m.group(1)!] = Map.fromEntries(entries.entries.where((e) => !e.key.startsWith('@')));
    }
  }

  final modelsDir = Directory(p.join(artifactDir, 'models'));
  if (modelsDir.existsSync()) {
    for (final f in _walk(modelsDir)) {
      if (!f.path.endsWith('.json')) continue;
      final rel = p.relative(f.path, from: artifactDir).replaceAll('\\', '/');
      fixtures[rel] = jsonDecode(f.readAsStringSync());
    }
  }

  final iconsDir = Directory(p.join(vendorDir, 'lucide', 'icons'));
  if (iconsDir.existsSync()) {
    for (final f in iconsDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.svg')) continue;
      iconSvg[p.basenameWithoutExtension(f.path)] = f.readAsStringSync();
    }
  }

  final preload = {
    'arb': arb,
    'fixtures': fixtures,
    'iconSvg': iconSvg,
  };
  return 'export const preload = ${const JsonEncoder().convert(preload)};\n';
}

/// Generates runtime/render.tsx from the artifact's .tsx view inventory.
/// Scans for *_view.tsx files, finds default + named exports, builds a static
/// registry mapping .html view paths → TSX components.
String generateRenderTsx(String artifactDir, {String? projectDir}) {
  final views = <TsxView>[];

  // Scan artifact for *_view.tsx files (studio views).
  for (final f in _walk(Directory(artifactDir))) {
    if (!f.path.endsWith('_view.tsx')) continue;
    final rel = p.relative(f.path, from: artifactDir).replaceAll('\\', '/');
    final htmlKey = rel.replaceAll('.tsx', '.html');
    final src = f.readAsStringSync();

    // Default export: `export default Foo` or `export default const Foo`
    final defaultRe = RegExp(r'export\s+default\s+(?:const\s+)?(\w+)');
    final defaultName = defaultRe.firstMatch(src)?.group(1);

    // Named exports (fragments): `export function Foo` or `export const Foo`
    final fragRe = RegExp(r'export\s+(?:const|function)\s+([A-Z]\w+)');
    final fragments = <String>[];
    for (final m in fragRe.allMatches(src)) {
      final name = m.group(1)!;
      if (name != defaultName) fragments.add(name);
    }

    views.add(TsxView(htmlKey, rel, defaultName, fragments));
  }

  // Scan project surfaces for *.tsx partials (e.g. portalo home, product, etc.).
  // Registered as ui/project/<name>.html to match build_facade.js's partial key.
  if (projectDir != null) {
    final surfacesDir = Directory(p.join(projectDir, 'design', 'surfaces'));
    if (surfacesDir.existsSync()) {
      for (final f in _walk(surfacesDir)) {
        if (!f.path.endsWith('.tsx')) continue;
        final name = p.basenameWithoutExtension(f.path);
        final htmlKey = 'ui/project/$name.html';
        final rel = 'ui/project/$name.tsx'; // matches the copy path in _buildRenderBundle
        final src = f.readAsStringSync();

        final fragRe = RegExp(r'export\s+(?:const|function)\s+([A-Z]\w+)');
        final fragments = <String>[];
        for (final m in fragRe.allMatches(src)) {
          fragments.add(m.group(1)!);
        }
        // Project partials use named exports only (no default export).
        // All exports go into fragments; the registry treats the first as
        // the default component (see registry generation below).
        views.add(TsxView(htmlKey, rel, null, fragments));
      }
    }
  }

  final buf = StringBuffer()
    ..writeln("// render.tsx — auto-generated at eject time from the artifact's")
    ..writeln("// .tsx view inventory. DO NOT EDIT — re-run eject to regenerate.")
    ..writeln("import type { FC } from 'hono/jsx';");

  for (final v in views) {
    final prefix = viewAliasPrefix(v.relPath);
    if (v.defaultName != null && v.fragments.isEmpty) {
      buf.writeln("import ${v.defaultName} from '../${v.relPath}';");
    } else if (v.defaultName != null) {
      final aliased = v.fragments.map((f) => '$f as $prefix$f').join(', ');
      buf.writeln("import ${v.defaultName}, { $aliased } from '../${v.relPath}';");
    } else if (v.fragments.isNotEmpty) {
      final aliased = v.fragments.map((f) => '$f as $prefix$f').join(', ');
      buf.writeln("import { $aliased } from '../${v.relPath}';");
    }
  }

  buf
    ..writeln()
    ..writeln('type ComponentMap = { default: FC<Record<string, unknown>>; [fragment: string]: FC<Record<string, unknown>> };')
    ..writeln()
    ..writeln('const registry: Record<string, ComponentMap> = {');

  for (final v in views) {
    final prefix = viewAliasPrefix(v.relPath);
    buf.write("  '${v.htmlKey}': {");
    if (v.defaultName != null) {
      buf.write(' default: ${v.defaultName} as unknown as FC<Record<string, unknown>>,');
    } else if (v.fragments.isNotEmpty) {
      // Project partials: no default export — first named export acts as default.
      buf.write(' default: $prefix${v.fragments.first} as unknown as FC<Record<string, unknown>>,');
    }
    for (final frag in v.fragments) {
      final key = frag[0].toLowerCase() + frag.substring(1);
      buf.write(' $key: $prefix$frag as unknown as FC<Record<string, unknown>>,');
    }
    buf.writeln(' },');
  }

  buf
    ..writeln('};')
    ..writeln()
    ..writeln(r'''export function render(viewRef: string, ctx: Record<string, unknown>) {
  const hash = viewRef.indexOf('#');
  const file = hash === -1 ? viewRef : viewRef.slice(0, hash);
  const macro = hash === -1 ? undefined : viewRef.slice(hash + 1);

  const entry = registry[file];
  if (!entry) throw new Error('Unknown view: ' + file);
  const component = macro ? entry[macro] : entry.default;
  if (!component) throw new Error('Unknown fragment: ' + macro);
  return component(ctx);
}''');

  return buf.toString();
}

class TsxView {
  final String htmlKey;
  final String relPath;
  final String? defaultName;
  final List<String> fragments;
  TsxView(this.htmlKey, this.relPath, this.defaultName, this.fragments);
}

/// Derives a unique PascalCase prefix from a view file path for import aliasing.
/// `ui/views/.../brief/brief_view.tsx` → `BriefView`
String viewAliasPrefix(String relPath) {
  final base = p.basenameWithoutExtension(relPath);
  return base.split('_').map((s) => s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1)).join('');
}

/// Route-manifest codegen (Phase 4 — the moat). Parses app.routes.js's route
/// table (a static array — parse, don't eval) and emits runtime/routes.js +
/// runtime/routes.d.ts: typed helpers so viewmodels write
/// `routes.timer.tick()` instead of string literals. Renaming a route in
/// app.routes.js breaks typecheck (the falsifiability test).
void _generateRouteManifest(String artifactDir, String out) {
  final routesFile = File(p.join(artifactDir, 'app.routes.js'));
  if (!routesFile.existsSync()) return;
  // Strip comments before matching so a route-shaped line inside a comment
  // (e.g. a commented-out route kept for reference) can't emit a false route.
  // kimitail: naive strip — a `//` or `/*` inside a string literal would
  // truncate it; route tables don't carry such strings (paths start with '/').
  final src = routesFile
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  // Extract [METHOD, PATH] pairs from the route table — regex, not eval.
  final routeRe = RegExp(r"""['"]([A-Z]+)['"]\s*,\s*['"]([^'"]+)['"]""");
  final paths = <String>{};
  for (final m in routeRe.allMatches(src)) {
    paths.add(m.group(2)!);
  }
  final sorted = paths.toList()..sort();
  if (sorted.isEmpty) return;

  // Build a nested tree from path segments.
  final root = <String, dynamic>{};
  for (final path in sorted) {
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) {
      root['index'] = path;
      continue;
    }
    var node = root;
    for (var i = 0; i < segs.length; i++) {
      final seg = segs[i];
      final isLast = i == segs.length - 1;
      final key = seg.startsWith(':') ? seg.substring(1) : seg;
      if (isLast) {
        node[key] = path;
      } else {
        // A shorter route (/timer) may have set this as a String leaf —
        // promote it to a namespace with an 'index' entry.
        if (node[key] is String) {
          node[key] = <String, dynamic>{'index': node[key]};
        }
        node[key] ??= <String, dynamic>{};
        node = node[key] as Map<String, dynamic>;
      }
    }
  }

  // Object keys must be valid JS identifiers — quote anything else (e.g.
  // hyphenated path segments: /order-items → "order-items": …). Applies to
  // both the .js and the .d.ts output, leaves and namespaces alike.
  String jsKey(String key) =>
      RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(key) ? key : '"$key"';

  // Shared tree walker — leaf callback formats the terminal line; closeSep
  // distinguishes `,` (JS) from `;` (.d.ts).
  String emitNode(Map<String, dynamic> node, String indent, String closeSep,
      String Function(String key, String pathStr, List<String> params, String indent) leaf) {
    final buf = StringBuffer();
    for (final e in node.entries) {
      if (e.value is String) {
        final pathStr = e.value as String;
        final params = RegExp(r':(\w+)').allMatches(pathStr).map((m) => m.group(1)!).toList();
        buf.writeln(leaf(e.key, pathStr, params, indent));
      } else {
        buf.writeln('$indent${jsKey(e.key)}: {');
        buf.write(emitNode(e.value as Map<String, dynamic>, '$indent  ', closeSep, leaf));
        buf.writeln('$indent}$closeSep');
      }
    }
    return buf.toString();
  }

  String jsLeaf(String key, String pathStr, List<String> params, String indent) {
    if (params.isEmpty) return '$indent${jsKey(key)}: () => "$pathStr",';
    final args = params.join(', ');
    final tmpl = pathStr.replaceAllMapped(RegExp(r':(\w+)'), (m) => '\${${m.group(1)}}');
    return '$indent${jsKey(key)}: ($args) => `$tmpl`,';
  }

  String tsLeaf(String key, String pathStr, List<String> params, String indent) {
    if (params.isEmpty) return '$indent${jsKey(key)}: () => "$pathStr";';
    final typed = params.map((p) => '$p: string').join(', ');
    return '$indent${jsKey(key)}: ($typed) => string;';
  }

  final runtimeDir = Directory(p.join(out, 'runtime'))..createSync(recursive: true);
  File(p.join(runtimeDir.path, 'routes.js')).writeAsStringSync(
    '// Auto-generated route manifest — do not edit.\n'
    '// Regenerate via `appbox design eject`.\n\n'
    'export const routes = {\n${emitNode(root, '  ', ',', jsLeaf)}};\n',
  );
  File(p.join(runtimeDir.path, 'routes.d.ts')).writeAsStringSync(
    '// Auto-generated route types — do not edit.\n\n'
    'export declare const routes: {\n${emitNode(root, '  ', ';', tsLeaf)}};\n',
  );
}

/// Emits kit facades + .env.example for declared kits (Phase 5). Returns the
/// npm deps to merge into package.json. Reads kit-registry.json + credentials
/// catalog to wire env vars and copy the right facades.
Map<String, String> _emitKitsAndEnv(String out, String repo, String target, List<String> kits) {
  final kitDeps = <String, String>{};
  if (kits.isEmpty && target != 'cloudflare' && target != 'vercel') return kitDeps;

  // Read config files.
  final kitRegPath = p.join(repo, 'config', 'kit-registry.json');
  final credPath = p.join(repo, 'config', 'credentials.catalog.json');
  if (!File(kitRegPath).existsSync() || !File(credPath).existsSync()) return kitDeps;

  final kitReg = jsonDecode(File(kitRegPath).readAsStringSync()) as Map<String, dynamic>;
  final credCatalog = jsonDecode(File(credPath).readAsStringSync()) as Map<String, dynamic>;

  // Build credential lookup: key → entry.
  final creds = <String, Map<String, dynamic>>{};
  for (final c in (credCatalog['credentials'] as List).whereType<Map>()) {
    final entry = Map<String, dynamic>.from(c);
    if (entry['key'] != null) creds[entry['key'] as String] = entry;
  }

  final envLines = <String>[];
  final publishableKeys = <String>[];
  final kitFacadesDir = p.join(repo, 'skills', 'appbox-designer', 'runtime', 'kit-facades');

  // Process each declared kit.
  for (final kitDir in kits) {
    Map<String, dynamic>? web;
    for (final k in (kitReg['kits'] as List).whereType<Map>()) {
      if (k['dir'] == kitDir && k['web'] != null) {
        web = Map<String, dynamic>.from(k['web'] as Map);
        break;
      }
    }
    if (web == null) continue;

    // Copy facade into ejected tree.
    final facade = web['facade'] as String;
    final src = File(p.join(kitFacadesDir, facade));
    if (src.existsSync()) {
      final destDir = Directory(p.join(out, 'services', 'facades'))..createSync(recursive: true);
      File(p.join(destDir.path, facade)).writeAsStringSync(src.readAsStringSync());
    }

    // Parse npm spec: "package@^version" → {package: ^version}.
    final npm = web['npm'] as String;
    final at = npm.lastIndexOf('@');
    if (at > 0) kitDeps[npm.substring(0, at)] = npm.substring(at + 1);

    // Collect env vars from the kit's envFrom list.
    for (final key in (web['envFrom'] as List).whereType<String>()) {
      final cred = creds[key];
      if (cred == null) continue;
      final kind = cred['kind'] ?? 'secret';
      final url = cred['url'] ?? '';
      envLines.add('# $key ($kind)${url.isNotEmpty ? ' — $url' : ''}');
      envLines.add('$key=${kind == 'publishable' ? 'set-me' : ''}');
      envLines.add('');
      if (kind == 'publishable' && !publishableKeys.contains(key)) {
        publishableKeys.add(key);
      }
    }
  }

  // Publishable (client-safe) keys also land in a generated config module —
  // .env.example documents them, but a viewmodel needs them as VALUES to hand
  // to a template (e.g. a map token rendered into an island's state). Secrets
  // never appear here. The caller passes env explicitly (process.env on node,
  // ctx.env on Workers) so the module stays runtime-agnostic.
  if (publishableKeys.isNotEmpty) {
    final entries = publishableKeys
        .map((k) => '  $k: env.$k ?? \'\',')
        .join('\n');
    File(p.join(out, 'runtime', 'client_config.js')).writeAsStringSync(
      '// Auto-generated client config — publishable (browser-safe) values only.\n'
      '// Regenerate via `appbox design eject`. Secrets never appear here.\n'
      '\n'
      '/**\n'
      ' * @param {Record<string, string | undefined>} env - process.env on node, ctx.env on Workers\n'
      ' * @returns {Record<string, string>} publishable config, safe to render into a page\n'
      ' */\n'
      'export const clientConfig = (env) => ({\n$entries\n});\n',
    );
  }

  // Deploy credentials for the target.
  final deployKeys = target == 'cloudflare'
      ? ['CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID']
      : target == 'vercel'
          ? ['VERCEL_TOKEN', 'VERCEL_ORG_ID', 'VERCEL_PROJECT_ID']
          : <String>[];
  for (final key in deployKeys) {
    if (envLines.any((l) => l.startsWith('$key='))) continue;
    final cred = creds[key];
    if (cred == null) continue;
    envLines.add('# $key (secret) — ${cred['url'] ?? ''}');
    envLines.add('$key=');
    envLines.add('');
  }

  if (envLines.isNotEmpty) {
    File(p.join(out, '.env.example')).writeAsStringSync(
      '# Environment variables for the ejected app.\n'
      '# Copy to .env and fill in. Secrets: never commit .env.\n\n'
      '${envLines.join('\n')}\n',
    );
  }

  return kitDeps;
}

/// Ejected-artifact README — target-aware productionization guide.
String _ejectReadmeV2(String name, String target) {
  final isWorkers = target == 'cloudflare';
  final isVercel = target == 'vercel';
  final runCmd = isWorkers ? 'npx wrangler dev' : 'npm start';
  final deployCmd = isWorkers
      ? 'npx wrangler deploy'
      : isVercel
          ? 'npx vercel deploy'
          : 'deploy server.js to any Node host';
  return '''# $name

Ejected from a appbox-designer artifact — a self-contained server-rendered
htmx app (zero custom client-side JavaScript). It runs on a real Hono runtime
on $target.

**One-way eject:** this tree is yours. appbox will never re-import it. Edit
freely — routes, templates, services, the runtime modules.

## Quick start

```sh
npm install
$runCmd          # http://localhost:${isWorkers ? '8787' : isVercel ? '3000' : '4399'}
npm run typecheck # tsc --checkJs (Phase 4)
```

## Deploy

```sh
$deployCmd
```

## Realtime (SSE)

The runtime ships an SSE bus (`runtime/realtime.js`), attached at
`GET /__events?channel=<name>`. Connect from markup with the bundled hx-sse
extension; publish from any viewmodel via `h.sse`:

```html
<div hx-ext="sse" hx-sse:connect="/__events?channel=orders">
  <div id="orders">1 open</div>
</div>
```

```js
// in a viewmodel — unnamed messages swap into the connecting element's
// hx-target/hx-swap (morph composes), so every client patches #orders:
h.sse.publishPatch('orders', '<div id="orders">2 open</div>');
// or dispatch a named DOM event instead of a swap:
h.sse.publishEvent('orders', 'order-accepted', '<li>#1042</li>');
```

Every event carries an `id:` and a short replay buffer, so reconnects (hx-sse
resends `Last-Event-ID` automatically) pick up where they left off. The bus is
in-memory: single-process only — see the Workers note below for the scale seam.

$_readmeFormsSection${isWorkers ? '''
## Cloudflare Workers notes

- Static assets (`/assets/*`, including the narrowed `/assets/vendor/*` set)
  are served from the `[assets]` binding directory (`./assets`); `worker.js`
  strips the `/assets` prefix and delegates to `env.ASSETS`. Update
  `wrangler.toml [assets]` if you add directories.
- Templates, l10n catalogs, and fixtures are pre-bundled into
  `runtime/preload.js` (Workers have no filesystem). Re-run eject to refresh it
  after artifact changes, or edit it directly.
- The SSE bus (`runtime/realtime.js`) is in-memory — events published on one
  isolate never reach clients on another. For multi-instance realtime, use a
  Durable-Object-per-channel adapter (documented in realtime.js).
''' : ''}${isVercel ? '''
## Vercel notes

- Entry shape follows Vercel's zero-config Hono convention: `server.js`
  exports the app as its default export, which becomes the Function (Fluid
  compute). There is no listening server and no vercel.json — rewrites/routes
  are unnecessary.
- Static files serve from `public/` only; the eject relocated `assets/` there
  (`serveStatic` is ignored by the platform).
- Files read from disk at runtime (l10n catalogs, fixture JSON, Lucide SVGs)
  rely on Vercel's file tracing. If a deploy 500s on a missing file, add a
  `functions` config with `includeFiles` for the directory to vercel.json.
''' : ''}## Layout

- `app.routes.js` — the URL inventory: `[method, path, handler][]` + `shellRoots`
- `ui/views/<shell>_shell/<surface>/` — view template + co-located ViewModel
- `services/repositories|facades/` — data access; **swap fixture Repositories
  for a real DB here** — ViewModels depend only on Facades, so nothing else
  changes
- `runtime/` — the Hono runtime: `router.js` (app factory), `helpers.js` (the
  `h` object), `render.js` (compiled TSX renderer), `l10n.js`, `state.js`, `timers.js`,
  `realtime.js` (SSE bus), `vendor/` (narrowed client libraries)
- `runtime/routes.js` + `routes.d.ts` — the generated typed route manifest:
  viewmodels take URLs from `routes.*` helpers, so renaming a route in
  `app.routes.js` breaks `npm run typecheck` instead of 404ing at runtime
- `${isWorkers ? 'worker.js' : 'server.js'}` — the $target entry point

## Productionize

1. **Config** — move env-sensitive values to env vars (`PORT` is supported).
2. **Data layer** — swap fixture Repositories for real ones behind Facade
   contracts. ViewModels touch only Facades → no template/route changes.
3. **Session store** — in-memory store is single-process; multi-instance needs
   a shared store (KV/Redis) behind `sessionOf/prefsOf/setPrefs`. The
   `kdh_sid` cookie is an opaque random-UUID bearer token (documented in
   `state.js`) — equivalent to a signed cookie because it carries no payload.
4. **Tests** — `appbox lens check http://localhost:${isWorkers ? '8787' : isVercel ? '3000' : '4399'}/`
   for visual + smoke; add `npm test` with your framework of choice.
5. **Security** — keep the zero-custom-JS contract; add standard headers.
''';
}

/// Forms section of the ejected README (M8) — a raw string so the TSX/JS
/// example needs no Dart escaping. Interpolated into [_ejectReadmeV2].
const _readmeFormsSection = r'''
## Forms (422 validation)

POST form actions validate with zod (`runtime/forms.js`); a failed parse
answers **422 with the form partial re-rendered** — errors and prior values
intact. htmx 4 ignores non-2xx responses by default, but the base layout
carries `hx-status:422="{}"` on `<body>`, which lets a 422 swap like any
other response (the v4-native mechanism — no extensions, no custom JS).
`autofocus` on the first invalid field makes htmx focus it after the swap
(v4 focuses the first `[autofocus]` in swapped content natively).

Field-error convention: `aria-invalid="true"` on the invalid input, an error
element right next to it (`field__error` / `field-error-<name>`), wired with
`aria-describedby` — the same shape as the artifact's FormField widget.

A contact form, end to end:

```tsx
// ui/views/main_shell/contact/contact_view.tsx — page + ContactForm fragment.
import type { FC } from 'hono/jsx';

interface ContactProps {
  action: string; // hx-post target — the viewmodel passes a routes.* helper
  errors?: Record<string, string>;
  values?: Record<string, string>;
}

export const ContactForm: FC<ContactProps> = ({ action, errors = {}, values = {} }) => {
  const firstError = Object.keys(errors)[0];
  const field = (name: string, label: string, type = 'text') => (
    <div class={errors[name] ? 'field field--invalid' : 'field'}>
      <label class="field__label" for={name}>{label}</label>
      <input
        class="field__input"
        id={name}
        name={name}
        type={type}
        value={values[name] ?? ''}
        aria-invalid={errors[name] ? 'true' : undefined}
        aria-describedby={errors[name] ? 'field-error-' + name : undefined}
        autofocus={name === firstError ? true : undefined}
      />
      {errors[name] && (
        <p class="field__error" id={'field-error-' + name}>{errors[name]}</p>
      )}
    </div>
  );
  return (
    <form hx-post={action} hx-swap="outerHTML">
      {field('name', 'Name')}
      {field('email', 'Email', 'email')}
      <button class="btn" type="submit">Send</button>
    </form>
  );
};

const ContactPage: FC<ContactProps> = (props) => (
  <main>
    <h1>Contact</h1>
    <ContactForm {...props} />
  </main>
);

export default ContactPage;
```

```js
// ui/views/main_shell/contact/contact_viewmodel.js
import { z } from 'zod';
import { parseForm } from '../../../../runtime/forms.js';
import { routes } from '../../../../runtime/routes.js';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  email: z.string().email('A valid email is required'),
});

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const page = (c, h) =>
  h.render(c, 'ui/views/main_shell/contact/contact_view.html', {
    action: routes.contact(),
  });

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const submit = async (c, h) => {
  const result = await parseForm(c, schema);
  if (!result.ok) {
    // 422 + the form fragment: htmx swaps it in place of the <form>
    // (default target), errors and typed values preserved, no full reload.
    return h.render(c, 'ui/views/main_shell/contact/contact_view.html#contactForm', {
      action: routes.contact(),
      errors: result.errors,
      values: result.values,
    }, 422);
  }
  return h.refresh(c);
};
```

```js
// app.routes.js
import * as contact from './ui/views/main_shell/contact/contact_viewmodel.js';
export default [
  // ...
  ['GET', '/contact', contact.page],
  ['POST', '/contact', contact.submit],
];
```

Invalid submit → 422 → the form swaps in place with errors + values and
focus on the first invalid field; no full reload. URLs come from the
generated route manifest (`runtime/routes.js`), so renaming `/contact` in
`app.routes.js` fails `npm run typecheck` instead of 404ing at runtime.

''';

// ══ design-system intake (Task 22.1) ═════════════════════════════════════
// Ported from skills/appbox-designer/agents/{check-design-system,record-asset,
// import-design-system}.mjs + their shared lib/asset-store.mjs. record-asset
// is a 1:1 port (the _d_meta.json asset model is pure JSON). ds-check and
// ds-import port the achievable subset: global-CSS entry + namespace
// resolution + file-sync + _d_meta.json binding. The full component/token/
// card inventory (check-design-system.mjs) and the per-load _ds_prompt.md
// (import-design-system.mjs) need ds-core.mjs's buildModel + ds-prompt.mjs's
// renderDsPrompt (~1040 lines, explicitly dropped in plan §22.1) and are NOT
// reproduced — see the divergence note on each verb.

String _toPosix(String s) => p.split(s).join('/');

// ── _d_meta.json asset model (lib/asset-store.mjs, ported 1:1) ───────────

/// status ∈ needs-review (default) | approved | changes-requested.
const List<String> statusValues = [
  'needs-review',
  'approved',
  'changes-requested',
];

/// Where a project's metadata lives. The `_d_` prefix namespaces our file at
/// the project root so it never collides with a deliverable's own meta.json.
const String metaFile = '_d_meta.json';

/// Marker a compiled design system carries at its root.
const String metaManifest = '_ds_manifest.json';

String metaPathFor(String projectDir) => p.join(projectDir, metaFile);

String _nowIso() => DateTime.now().toUtc().toIso8601String();

/// Derive a display name from a deliverable path: basename minus `.dc.html`,
/// then minus `.html`. "Welcome.html" → "Welcome", "Card.dc.html" → "Card".
String getAssetBaseName(String path) {
  final seg = path.split('/').last;
  final base = seg.isEmpty ? path : seg;
  return base
      .replaceAll(RegExp(r'\.dc\.html$'), '')
      .replaceAll(RegExp(r'\.html$'), '');
}

/// Find the asset name whose versions include [path], or null.
String? findAssetNameByPath(Map<String, dynamic> meta, String path) {
  final assets = meta['assets'];
  if (assets is! Map) return null;
  for (final entry in assets.entries) {
    final asset = entry.value;
    if (asset is! Map) continue;
    final versions = asset['versions'];
    if (versions is! List) continue;
    if (versions.any((v) => v is Map && v['path'] == path)) {
      return entry.key;
    }
  }
  return null;
}

/// Record (or update) a version under an asset. Resolves the name from
/// `action['name']`, else from `action['inheritFrom']`. If a version with the
/// same `path` exists it is updated in place; otherwise a new version is
/// appended with a fresh `createdAt`. Only supplied fields are written.
/// Mutates [meta] in place. (recordAssetVersion, asset-store.mjs.)
void recordAssetVersion(Map<String, dynamic> meta, Map<String, dynamic> action) {
  final nameField = action['name'];
  final String? name = nameField is String && nameField.isNotEmpty
      ? nameField
      : (action['inheritFrom'] is String
          ? findAssetNameByPath(meta, action['inheritFrom'] as String)
          : null);
  if (name == null) return;
  if (meta['assets'] is! Map) meta['assets'] = <String, dynamic>{};
  final assets = meta['assets'] as Map;
  final existingAsset = assets[name] is Map
      ? Map<String, dynamic>.from(assets[name] as Map)
      : <String, dynamic>{};
  final versionsField = existingAsset['versions'];
  final versions = versionsField is List
      ? versionsField
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList()
      : <Map<String, dynamic>>[];
  final statusField = action['status'];
  final status = statusField is String ? statusField : 'needs-review';
  final idx = versions.indexWhere((v) => v['path'] == action['path']);
  if (idx >= 0) {
    final version = versions[idx];
    version['status'] = status;
    if (action['subtitle'] != null) version['subtitle'] = action['subtitle'];
    if (action['viewport'] != null) {
      final vp = <String, dynamic>{
        'width': (action['viewport'] as Map)['width'],
      };
      final newHeight = (action['viewport'] as Map)['height'];
      final oldVp = version['viewport'];
      final oldHeight = oldVp is Map ? oldVp['height'] : null;
      final height = newHeight ?? oldHeight;
      if (height != null) vp['height'] = height;
      version['viewport'] = vp;
    }
    if (action['chatId'] != null) version['chatId'] = action['chatId'];
    if (action['section'] != null) version['section'] = action['section'];
  } else {
    final version = <String, dynamic>{
      'path': action['path'],
      'createdAt': _nowIso(),
    };
    if (action['chatId'] != null) version['chatId'] = action['chatId'];
    version['status'] = status;
    if (action['subtitle'] != null) version['subtitle'] = action['subtitle'];
    if (action['viewport'] != null) version['viewport'] = action['viewport'];
    if (action['section'] != null) version['section'] = action['section'];
    versions.add(version);
  }
  existingAsset['versions'] = versions;
  assets[name] = existingAsset;
}

/// Remove an asset or version. name & no path → delete the whole asset; path →
/// drop matching versions (scoped to name if given) across assets; assets that
/// end up empty are deleted, and `meta['assets']` is dropped when empty.
/// (unrecordAssetVersion, asset-store.mjs.)
void unrecordAssetVersion(Map<String, dynamic> meta, Map<String, dynamic> action) {
  final assets = meta['assets'];
  if (assets is! Map) return;
  final nameField = action['name'];
  final name = nameField is String && nameField.isNotEmpty ? nameField : null;
  final pathField = action['path'];
  final path = pathField is String && pathField.isNotEmpty ? pathField : null;
  if (name != null && path == null) {
    assets.remove(name);
  } else if (path != null) {
    for (final assetName in List.of(assets.keys)) {
      if (name != null && assetName != name) continue;
      final asset = assets[assetName];
      if (asset is! Map || asset['versions'] is! List) continue;
      final kept = (asset['versions'] as List)
          .where((v) => v is! Map || v['path'] != path)
          .toList();
      if (kept.isEmpty) {
        assets.remove(assetName);
      } else {
        asset['versions'] = kept;
      }
    }
  }
  if (assets.isEmpty) meta.remove('assets');
}

/// Read `<projectDir>/_d_meta.json`. Missing file → {} (fresh project). A file
/// that exists but is invalid JSON throws (better than silently clobbering the
/// orchestrator-written fields on the next write).
Map<String, dynamic> readMeta(String metaPath) {
  final f = File(metaPath);
  if (!f.existsSync()) return <String, dynamic>{};
  final parsed = jsonDecode(f.readAsStringSync());
  return parsed is Map
      ? Map<String, dynamic>.from(parsed)
      : <String, dynamic>{};
}

/// Seed project-level fields when absent. Never invents title/prompt (those
/// are orchestrator-owned). (bootstrapMeta, asset-store.mjs.)
Map<String, dynamic> bootstrapMeta(Map<String, dynamic> meta) {
  if (meta['type'] == null) meta['type'] = 'design';
  if (meta['designSystems'] is! List) {
    meta['designSystems'] = <Map<String, dynamic>>[];
  }
  if (!meta.containsKey('primaryDesignSystem')) meta['primaryDesignSystem'] = null;
  return meta;
}

/// Persist `_d_meta.json`: set `createdAt` once, bump `updatedAt`, pretty-print
/// with a trailing newline. (writeMeta, asset-store.mjs.)
void writeMeta(String metaPath, Map<String, dynamic> meta) {
  final iso = _nowIso();
  if (!meta.containsKey('createdAt')) meta['createdAt'] = iso;
  meta['updatedAt'] = iso;
  Directory(p.dirname(metaPath)).createSync(recursive: true);
  File(metaPath)
      .writeAsStringSync("${const JsonEncoder.withIndent('  ').convert(meta)}\n");
}

// ── record-asset (record-asset.mjs) ─────────────────────────────────────

const _recordValueFlags = {
  '--name', '--inherit-from', '--subtitle', '--status',
  '--width', '--height', '--section', '--chat-id', '--path',
};

CmdResult _recordUsage(String msg) {
  final err = <String>[];
  if (msg.isNotEmpty) err.add('record-asset: $msg');
  err.addAll([
    'Usage:',
    '  appbox design record-asset <projectDir> <htmlPath> [--name N] [--inherit-from P]',
    '       [--subtitle S] [--status needs-review|approved|changes-requested]',
    '       [--width W] [--height H] [--section S] [--chat-id ID]',
    '  appbox design record-asset <projectDir> --remove [<htmlPath>] [--name N] [--path P]',
  ]);
  return CmdResult(64, stderrLines: err);
}

/// `appbox design record-asset <projectDir> <htmlPath> [flags]` (or
/// `--remove`) — index a UI deliverable in `_d_meta.json`. Exit 64 usage /
/// 1 io|json error / 0 recorded. Ported from record-asset.mjs.
CmdResult designRecordAsset(List<String> args) {
  final opts = <String, String>{};
  final positional = <String>[];
  var remove = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--remove') {
      remove = true;
      continue;
    }
    if (_recordValueFlags.contains(a)) {
      if (i + 1 >= args.length) return _recordUsage('flag $a needs a value');
      opts[a.substring(2)] = args[++i];
      continue;
    }
    if (a.startsWith('--')) return _recordUsage('unknown flag: $a');
    positional.add(a);
  }

  if (positional.isEmpty) return _recordUsage('missing <projectDir>');
  final projectDir = p.normalize(p.absolute(positional[0]));
  final metaPath = metaPathFor(projectDir);
  final relMeta = _toPosix(p.relative(metaPath, from: Directory.current.path));
  final relMetaLabel = relMeta.isEmpty ? metaFile : relMeta;

  // Normalize a deliverable path to project-relative POSIX. Accepts an
  // absolute path, a path under <projectDir>, or an already project-relative
  // path (the documented, common case).
  String? toProjectRel(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final absFromCwd = p.normalize(p.absolute(raw));
    if (absFromCwd == projectDir) return null;
    if (absFromCwd.startsWith('$projectDir/')) {
      return _toPosix(p.relative(absFromCwd, from: projectDir));
    }
    return _toPosix(raw.replaceFirst(RegExp(r'^\./'), ''));
  }

  if (remove) {
    if (!File(metaPath).existsSync()) {
      return CmdResult(0,
          stdoutLines: ['No $relMetaLabel; nothing to remove.']);
    }
    final name = opts['name'];
    final storedPath =
        toProjectRel(positional.length > 1 ? positional[1] : opts['path']);
    if (name == null && storedPath == null) {
      return _recordUsage('--remove needs --name and/or a path');
    }
    Map<String, dynamic> meta;
    try {
      meta = readMeta(metaPath);
    } catch (e) {
      return CmdResult(1, stderrLines: ['record-asset: $e']);
    }
    final action = <String, dynamic>{};
    if (name != null) action['name'] = name;
    if (storedPath != null) action['path'] = storedPath;
    unrecordAssetVersion(meta, action);
    writeMeta(metaPath, meta);

    final assets = meta['assets'];
    final remaining = assets is Map ? assets.length : 0;
    final out = <String>[];
    if (name != null && storedPath == null) {
      out.add('Removed asset "$name".');
    } else {
      out.add('Unrecorded $storedPath${name != null ? ' from "$name"' : ''}.');
    }
    out.add(remaining != 0
        ? '$relMetaLabel: $remaining asset(s) remaining.'
        : '$relMetaLabel: no assets remaining.');
    return CmdResult(0, stdoutLines: out);
  }

  // record
  final storedPath =
      toProjectRel(positional.length > 1 ? positional[1] : opts['path']);
  if (storedPath == null) return _recordUsage('missing <htmlPath>');

  final status = opts['status'];
  if (status != null && !statusValues.contains(status)) {
    return _recordUsage(
        'invalid --status "$status" (expected: ${statusValues.join(' | ')})');
  }

  Map<String, dynamic>? viewport;
  if (opts['width'] != null) {
    final width = num.tryParse(opts['width']!);
    if (width == null) {
      return _recordUsage('--width must be a number, got "${opts['width']}"');
    }
    viewport = <String, dynamic>{'width': width};
    if (opts['height'] != null) {
      final height = num.tryParse(opts['height']!);
      if (height == null) {
        return _recordUsage('--height must be a number, got "${opts['height']}"');
      }
      viewport['height'] = height;
    }
  } else if (opts['height'] != null) {
    return _recordUsage('--height requires --width');
  }

  final action = <String, dynamic>{'path': storedPath};
  if (opts['name'] != null) action['name'] = opts['name'];
  if (opts['inherit-from'] != null) {
    action['inheritFrom'] = toProjectRel(opts['inherit-from']);
  }
  if (status != null) action['status'] = status;
  if (opts['subtitle'] != null) action['subtitle'] = opts['subtitle'];
  if (viewport != null) action['viewport'] = viewport;
  if (opts['section'] != null) action['section'] = opts['section'];
  if (opts['chat-id'] != null) action['chatId'] = opts['chat-id'];

  Map<String, dynamic> meta;
  try {
    meta = readMeta(metaPath);
  } catch (e) {
    return CmdResult(1, stderrLines: ['record-asset: $e']);
  }
  bootstrapMeta(meta);

  // Resolve the asset name the way the store will, with a CLI-only final
  // fallback to the filename so --name is rarely needed.
  String? name = action['name'] as String?;
  if (name == null && action['inheritFrom'] != null) {
    name = findAssetNameByPath(meta, action['inheritFrom'] as String);
  }
  name ??= getAssetBaseName(storedPath);
  if (name.isEmpty) return _recordUsage('could not determine an asset name; pass --name');
  action['name'] = name;

  final existingAsset = (meta['assets'] is Map) ? (meta['assets'] as Map)[name] : null;
  final wasUpdate = existingAsset is Map &&
      existingAsset['versions'] is List &&
      (existingAsset['versions'] as List)
          .any((v) => v is Map && v['path'] == storedPath);

  recordAssetVersion(meta, action);
  writeMeta(metaPath, meta);

  final versions = (((meta['assets'] as Map)[name]['versions']) as List)
      .whereType<Map>()
      .toList();
  final recorded =
      versions.firstWhere((v) => v['path'] == storedPath, orElse: () => versions.first);
  final finalStatus = recorded['status'];
  final n = versions.length;
  return CmdResult(0, stdoutLines: [
    '${wasUpdate ? 'Updated' : 'Recorded'} asset "$name" → $storedPath  '
        '(status: $finalStatus, $n version${n == 1 ? '' : 's'})',
    '$relMetaLabel: written.',
  ]);
}

// ── ds-core subset: walk + global-CSS entry + namespace ──────────────────
// The component/token/card/font parsers are NOT ported (ds-core.mjs's
// buildModel, ~750 lines, dropped per plan §22.1). These helpers cover the
// achievable subset both ds-check and ds-import hinge on.

const _dsSkipDirs = {
  'node_modules', '.git', 'dist', 'build', '.next', 'out', 'coverage',
  '.cache', '.turbo', 'vendor',
};
const _dsGenerated = {
  '_ds_bundle.js', '_ds_manifest.json', '_adherence.oxlintrc.json',
};

List<File> _walkDs(Directory root) {
  final out = <File>[];
  void rec(Directory dir) {
    for (final e in dir.listSync()) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue; // skip dotfiles + dot-dirs
      if (e is Directory) {
        if (_dsSkipDirs.contains(name)) continue;
        rec(e);
      } else if (e is File) {
        if (_dsGenerated.contains(name)) continue;
        out.add(e);
      }
    }
  }
  rec(root);
  return out;
}

const _cssEntryNames = [
  'styles.css', 'index.css', 'globals.css', 'global.css',
  'main.css', 'theme.css', 'app.css', 'tokens.css',
];

/// Prefer a known entry name at the shallowest depth, in preference order.
/// (findGlobalCssEntry, ds-core.mjs.)
String? _findGlobalCssEntry(List<String> filesRel) {
  final cssRel = filesRel.where((f) => f.endsWith('.css')).toList();
  for (final name in _cssEntryNames) {
    final matches = cssRel.where((r) => p.basename(r) == name).toList();
    if (matches.isEmpty) continue;
    matches.sort((a, b) {
      final d = a.split('/').length - b.split('/').length;
      return d != 0 ? d : a.compareTo(b);
    });
    return matches.first;
  }
  return null;
}

/// Fallback when the filename heuristic misses: trust the compiled manifest's
/// recorded closure. Its LAST entry is the importer/entry file. (manifestCssEntry.)
String? _manifestCssEntry(String root) {
  final f = File(p.join(root, metaManifest));
  if (!f.existsSync()) return null;
  try {
    final m = jsonDecode(f.readAsStringSync());
    final paths = (m is Map && m['globalCssPaths'] is List)
        ? List<String>.from(m['globalCssPaths'] as List)
        : const <String>[];
    if (paths.isEmpty) return null;
    final entry = paths.last;
    if (entry.isNotEmpty && File(p.join(root, entry)).existsSync()) return entry;
  } catch (_) {}
  return null;
}

final _cssImportRe =
    RegExp(r"""@import\s+(?:url\(\s*)?["']([^"')]+)["']\s*\)?\s*;""");

/// Post-order @import closure: each file's imports come before the file
/// itself. (resolveCssClosure, ds-core.mjs.)
List<String> _resolveCssClosure(String root, String entryRel) {
  final order = <String>[];
  final seen = <String>{};
  void visit(String relPath) {
    if (!seen.add(relPath)) return;
    final f = File(p.join(root, relPath));
    if (!f.existsSync()) return;
    final src = f.readAsStringSync();
    for (final m in _cssImportRe.allMatches(src)) {
      final spec = m.group(1)!.trim();
      if (RegExp(r'^https?:', caseSensitive: false).hasMatch(spec)) continue;
      final childRel = p.posix.normalize(
          p.posix.join(p.posix.dirname(relPath), spec));
      visit(childRel);
    }
    order.add(relPath);
  }
  visit(entryRel);
  return order;
}

String _pascalCase(String s) {
  final words = s
      .replaceAll(RegExp(r'[_\-./]+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  final out = words.map((w) => w[0].toUpperCase() + w.substring(1)).join('');
  return out.isEmpty ? 'DesignSystem' : out;
}

/// Resolve the window namespace: existing manifest → bundle header → derive
/// `PascalCase(name)_sha256(name)[:6]`. (resolveNamespace, ds-core.mjs.)
String _resolveNamespace(String root, String projectName) {
  final mFile = File(p.join(root, metaManifest));
  if (mFile.existsSync()) {
    try {
      final m = jsonDecode(mFile.readAsStringSync());
      if (m is Map &&
          m['namespace'] is String &&
          (m['namespace'] as String).isNotEmpty) {
        return m['namespace'] as String;
      }
    } catch (_) {}
  }
  final bundle = File(p.join(root, '_ds_bundle.js'));
  if (bundle.existsSync()) {
    try {
      final head = bundle.readAsStringSync().split(RegExp(r'\r?\n'))[0];
      final m = RegExp(r'@ds-bundle:\s*(\{[\s\S]*?\})\s*\*/').firstMatch(head);
      if (m != null) {
        final meta = jsonDecode(m.group(1)!);
        if (meta is Map &&
            meta['namespace'] is String &&
            (meta['namespace'] as String).isNotEmpty) {
          return meta['namespace'] as String;
        }
      }
    } catch (_) {}
  }
  final hex =
      hexEncode(sha256(Uint8List.fromList(utf8.encode(projectName))));
  return '${_pascalCase(projectName)}_${hex.substring(0, 6)}';
}

/// `appbox design ds-check <projectDir> [--verbose]` — read-only validator.
/// Ported from check-design-system.mjs. Exit 64 usage / 1 not-a-dir / 0
/// globalCssEntry found / 2 none found. The component/token/card inventory
/// needs buildModel (dropped); this port validates the structural gate the
/// exit code hinges on + the namespace.
CmdResult designDsCheck(List<String> args) {
  final verbose =
      args.any((a) => a == '--verbose' || a == '-v' || a == 'verbose');
  String? projectDir;
  for (final a in args) {
    if (a.startsWith('-') || a == 'verbose') continue;
    projectDir = a;
    break;
  }
  if (projectDir == null) {
    return CmdResult(64,
        stderrLines: const [
          'Usage: appbox design ds-check <projectDir> [--verbose]'
        ]);
  }
  final root = p.normalize(p.absolute(projectDir));
  if (!FileSystemEntity.isDirectorySync(root)) {
    return CmdResult(1,
        stderrLines: ['check-design-system: Not a directory: $projectDir']);
  }
  final filesRel = _walkDs(Directory(root))
      .map((f) => _toPosix(p.relative(f.path, from: root)))
      .toList();
  var globalCssEntry = _findGlobalCssEntry(filesRel);
  globalCssEntry ??= _manifestCssEntry(root);
  final namespace = _resolveNamespace(root, p.basename(root));

  final lines = <String>[
    'Namespace: $namespace (use `const { X } = window.$namespace` in @dsCard HTML).',
  ];
  if (globalCssEntry != null) {
    lines.add('Global CSS entry: $globalCssEntry.');
  } else {
    lines.add('Global CSS entry: (none).');
    lines.add('');
    lines.add('Issues to fix:');
    lines.add('');
    lines.add('• No global CSS entry found (expected styles.css / index.css / '
        'globals.css / main.css). Tokens cannot be extracted.');
  }
  if (verbose) {
    lines.add('');
    lines.add('[structural check only — component/token/card/font inventory '
        'requires the ds-core parser, not ported (plan §22.1)]');
  }
  return CmdResult(globalCssEntry != null ? 0 : 2, stdoutLines: lines);
}

// ── ds-import (import-design-system.mjs) ────────────────────────────────

final _cssUrlRe = RegExp(r"""url\(\s*["']?([^"')]+)["']?\s*\)""");

/// Local `url()` targets referenced by a CSS file (fonts + images), resolved
/// relative to that CSS file and returned relative to dsDir.
List<String> _cssAssetTargets(String root, String cssRel) {
  final f = File(p.join(root, cssRel));
  if (!f.existsSync()) return const [];
  final dir = p.posix.dirname(cssRel);
  final out = <String>[];
  for (final m in _cssUrlRe.allMatches(f.readAsStringSync())) {
    var u = m.group(1)!.trim();
    if (u.isEmpty) continue;
    if (RegExp(r'^(https?:|data:|#)', caseSensitive: false).hasMatch(u)) continue;
    u = u.replaceFirst(RegExp(r'[?#].*$'), '');
    if (u.isEmpty) continue;
    final relToDs = p.posix.normalize(p.posix.join(dir, u));
    if (relToDs.startsWith('..')) continue; // outside the DS folder
    out.add(relToDs);
  }
  return out;
}

/// `appbox design ds-import <dsDir> <projectDir> [--primary]` — sync a
/// compiled design system into `<project>/_ds/<slug>/` + record the binding in
/// `_d_meta.json`. Ported from import-design-system.mjs. The per-load
/// `_ds_prompt.md` needs ds-prompt.mjs's renderDsPrompt (dropped per plan
/// §22.1) and is NOT generated.
CmdResult designDsImport(List<String> args) {
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length < 2) {
    return CmdResult(64,
        stderrLines: const [
          'Usage: appbox design ds-import <dsDir> <projectDir> [--primary]'
        ]);
  }
  final makePrimary = flags.contains('--primary');
  final dsDirArg = positional[0];
  final projectDirArg = positional[1];
  final dsDir = p.normalize(p.absolute(dsDirArg));
  final projectDir = p.normalize(p.absolute(projectDirArg));

  if (!FileSystemEntity.isDirectorySync(dsDir)) {
    return CmdResult(1,
        stderrLines: ['import-design-system: not a directory: $dsDirArg']);
  }
  if (!File(p.join(dsDir, metaManifest)).existsSync()) {
    return CmdResult(1, stderrLines: [
      'import-design-system: $dsDirArg is not a compiled design system '
          '(no _ds_manifest.json at its root). Run compile-design-system there first.',
    ]);
  }

  final dsSlug = p.basename(dsDir);
  final destRoot = p.join(projectDir, '_ds', dsSlug);

  // CSS closure (buildModel's achievable subset).
  final dsFilesRel = _walkDs(Directory(dsDir))
      .map((f) => _toPosix(p.relative(f.path, from: dsDir)))
      .toList();
  var entry = _findGlobalCssEntry(dsFilesRel);
  entry ??= _manifestCssEntry(dsDir);
  final globalCssPaths =
      entry != null ? _resolveCssClosure(dsDir, entry) : <String>[];
  final namespace = _resolveNamespace(dsDir, dsSlug);

  final copied = <String>{};
  bool copyFileRel(String relPath) {
    final from = File(p.join(dsDir, relPath));
    final to = File(p.join(destRoot, relPath));
    if (!from.existsSync() || !FileSystemEntity.isFileSync(from.path)) {
      return false;
    }
    to.parent.createSync(recursive: true);
    from.copySync(to.path);
    return true;
  }
  void copyOnce(String relPath) {
    if (copied.contains(relPath)) return;
    if (copyFileRel(relPath)) copied.add(relPath);
  }
  int copyDirRel(String relDir) {
    final fromDir = Directory(p.join(dsDir, relDir));
    if (!fromDir.existsSync() ||
        !FileSystemEntity.isDirectorySync(fromDir.path)) {
      return 0;
    }
    var n = 0;
    void rec(Directory d) {
      for (final e in d.listSync()) {
        if (e is Directory) {
          rec(e);
        } else if (e is File) {
          copyOnce(_toPosix(p.relative(e.path, from: dsDir)));
          n++;
        }
      }
    }
    rec(fromDir);
    return n;
  }

  // 1. global CSS @import closure (post-order: imports before importer).
  for (final css in globalCssPaths) {
    copyOnce(css);
  }
  final cssCount = copied.length;
  // 2. url() assets referenced by those CSS files.
  for (final css in globalCssPaths) {
    for (final asset in _cssAssetTargets(dsDir, css)) {
      copyOnce(asset);
    }
  }
  final assetUrlCount = copied.length - cssCount;
  // 3. bundle + manifest + adherence + readme + skill.
  final hasBundle = copyFileRel('_ds_bundle.js');
  if (hasBundle) copied.add('_ds_bundle.js');
  for (final f in const [
    metaManifest,
    '_adherence.oxlintrc.json',
    'README.md',
    'SKILL.md',
  ]) {
    copyOnce(f);
  }
  // 4. shared runtime assets directory, if present.
  final beforeAssets = copied.length;
  copyDirRel('assets');
  final assetDirCount = copied.length - beforeAssets;

  // design-system display name.
  String? firstH1(String mdRel) {
    final f = File(p.join(dsDir, mdRel));
    if (!f.existsSync()) return null;
    final m = RegExp(r'^#\s+(.+?)\s*$', multiLine: true)
        .firstMatch(f.readAsStringSync());
    return m?.group(1)?.trim();
  }
  String? skillName(String skillRel) {
    final f = File(p.join(dsDir, skillRel));
    if (!f.existsSync()) return null;
    final m = RegExp(r'^name:\s*(.+?)\s*$', multiLine: true)
        .firstMatch(f.readAsStringSync());
    final trimmed = m?.group(1)?.trim();
    return trimmed?.replaceAll(RegExp(r"""^["']|["']$"""), '');
  }
  String titleCase(String s) => s.replaceAll(RegExp(r'[-_]+'), ' ').replaceAllMapped(
      RegExp(r'\b\w'), (m) => m[0]!.toUpperCase());
  final dsName =
      firstH1('README.md') ?? skillName('SKILL.md') ?? titleCase(dsSlug);

  // merge _d_meta.json.
  final metaPath = metaPathFor(projectDir);
  Map<String, dynamic> meta;
  try {
    meta = readMeta(metaPath);
  } catch (e) {
    return CmdResult(1, stderrLines: ['import-design-system: $e']);
  }
  bootstrapMeta(meta);
  final dsEntry = <String, dynamic>{
    'name': dsName,
    'slug': dsSlug,
    'namespace': namespace,
    'dsFolder': '_ds/$dsSlug',
    'sourcePath': _toPosix(p.relative(dsDir, from: Directory.current.path)),
  };
  final designSystems = meta['designSystems'] as List;
  final idx =
      designSystems.indexWhere((d) => d is Map && d['slug'] == dsSlug);
  if (idx >= 0) {
    designSystems[idx] = <String, dynamic>{
      ...(designSystems[idx] as Map).cast<String, dynamic>(),
      ...dsEntry,
    };
  } else {
    designSystems.add(dsEntry);
  }
  if (makePrimary || meta['primaryDesignSystem'] == null) {
    meta['primaryDesignSystem'] = dsSlug;
  }
  writeMeta(metaPath, meta);

  // report (reduced — no component sample; buildModel/renderDsPrompt dropped).
  final destRel = _toPosix(p.relative(destRoot, from: Directory.current.path));
  final out = <String>[
    'Imported "$dsName" → $destRel/  (namespace $namespace)',
    'Synced ${copied.length} files: $cssCount CSS (@import closure), '
        '$assetUrlCount url() asset(s), $assetDirCount assets/ file(s), '
        'plus bundle/manifest/adherence/readme/skill.',
    '_d_meta.json: designSystems["$dsSlug"] recorded; '
        'primaryDesignSystem = "${meta['primaryDesignSystem']}".',
    '',
  ];
  if (hasBundle) {
    out.add('Wire it up — window.React/window.ReactDOM first, then every '
        'stylesheet below in order, then the bundle as a plain <script> '
        '(no type="text/babel" / type="module"). With several systems, the '
        "PRIMARY system's <link>s load LAST so its tokens win:");
  } else {
    out.add('Wire it up — every stylesheet below in order. With several '
        "systems, the PRIMARY system's <link>s load LAST so its tokens win:");
  }
  if (globalCssPaths.isNotEmpty) {
    for (final pth in globalCssPaths) {
      out.add('  <link rel="stylesheet" href="_ds/$dsSlug/$pth">');
    }
  } else {
    out.add('  (no global CSS entry found in this DS'
        '${hasBundle ? ' — only the bundle was copied' : ''})');
  }
  if (hasBundle) out.add('  <script src="_ds/$dsSlug/_ds_bundle.js"></script>');
  out.add('');
  out.add('Note: _ds_prompt.md was NOT generated (ds-prompt.mjs is dropped per '
      'plan §22.1); read _ds/$dsSlug/README.md for the guide.');

  return CmdResult(0, stdoutLines: out);
}

// ═─ shared ─════════════════════════════════════════════════════════════

String? _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/config/appbox.config.json').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}
