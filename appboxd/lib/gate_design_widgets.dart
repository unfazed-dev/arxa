/// The W-gate: the widget placement law and the panel contract, enforced
/// against ANY design artifact tree (nothing here is studio-specific).
///
/// Six hard-fail rules, per docs/plans/widget-panel-vocabulary-reconciliation.md
/// D5. Every failure message begins with its rule id and names the concrete fix,
/// because the reader of a gate failure is someone who has to move a file:
///
///   W1  placement — a widget lives at the narrowest scope covering all its
///       consumers, enforced in BOTH directions (too broad and too narrow).
///   W2  dead widgets — zero includers is a deletion, not a widget.
///   W3  panels are instantiated, never re-implemented — the `.panel-*`
///       structural skeleton appears in markup only inside `_panel.html`.
///   W4  shell composition — `<shell>_view.html` mounts role panels from
///       {header, main, activity, composer, footer}, each at most once.
///   W5  chip singularity — pill radius (999px/9999px) only in the widgets CSS.
///   W6  state namespacing — a shell's viewmodels write session keys under
///       `<shell>.` or `app.` only.
///
/// The include/import graph is the only authority for W1/W2. No such parser
/// existed in appboxd before this file — the pre-existing "orphan sweeps"
/// (emit_htmx, emit_structure, gate_intake) are surface- and viewmodel-scoped
/// and never look at Jinja includes — so [buildIncludeGraph] is new machinery.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_tools.dart' show LintFinding, stripComments;

// ══ vocabulary ══════════════════════════════════════════════════════════

/// The five panel roles. A shell mounts each at most once (W4); a widget named
/// `<role>_panel.html` is that role's instantiation.
const panelRoles = <String>['header', 'main', 'activity', 'composer', 'footer'];

/// The `.panel-*` structural skeleton — the classes that BUILD a panel: the
/// 3×3 section grid, the frame, the size steps, the resize grip. Extracted from
/// `assets/css/panels.css`.
///
/// Deliberately excludes two neighbouring families that are NOT re-implementation
/// and so must stay legal everywhere:
///   - role markers (`panel-header`, `panel-main`, `panel-activity`,
///     `panel-composer`, `panel-footer`) — an instantiation applies these; that
///     is the whole point of instantiating.
///   - innocuous descendants (`panel-label`, `panel-bar`, `panel-bar-item`,
///     `panel-views`, `panel-views-icon`) — chrome that lives inside a panel
///     rather than constructing one.
const panelStructuralClasses = <String>[
  'panel-frame',
  'panel-top',
  'panel-body',
  'panel-bottom',
  'panel-side-start',
  'panel-side-end',
  'panel-size-s',
  'panel-size-m',
  'panel-size-l',
  'panel-resize',
  'panel-resize-width',
];

/// The base widget that owns the panel skeleton. If a tree has no `_panel.html`
/// it has not reached D4 yet, and W3 reports skipped-with-note rather than a
/// vacuous pass.
const panelBaseWidget = 'ui/common/widgets/_panel.html';

/// Where the pill radius is allowed to live (W5). The chip widget's rules are
/// consolidated here; no per-widget CSS files.
const widgetsCssPath = 'assets/css/widgets.css';

// ══ the include graph ═══════════════════════════════════════════════════

/// A parsed template reference: `{% include %}`, `{% import %}`,
/// `{% from … import … %}`, `{% extends %}`.
///
/// Paths in this dialect are ARTIFACT-ROOT-RELATIVE (`ui/common/mini_panel.html`),
/// never relative to the referring file — matching how the design server resolves
/// them. `alias` is the `as X` binding when present, which W4 needs to count
/// macro calls.
class TemplateRef {
  final String path;
  final String? alias;
  const TemplateRef(this.path, this.alias);
}

final _refRe = RegExp(
  r'''\{%-?\s*(?:from\s+(?<from>"[^"]*"|'[^']*')\s+import\b[^%]*|(?<kind>include|import|extends)\s+(?<path>"[^"]*"|'[^']*')(?:\s+as\s+(?<alias>[A-Za-z_][A-Za-z_0-9]*))?[^%]*)%\}''',
);

String _unquote(String s) => s.substring(1, s.length - 1);

/// Every template reference in [src], comments already stripped by the caller.
///
/// A malformed or dynamic directive (the bare `{% include %}` that exists in the
/// studio today, or `{% include some_var %}`) simply does not match and is
/// skipped — a lint must not crash on the tree it is auditing.
List<TemplateRef> parseTemplateRefs(String src) {
  final out = <TemplateRef>[];
  for (final m in _refRe.allMatches(src)) {
    final raw = m.namedGroup('from') ?? m.namedGroup('path');
    if (raw == null) continue;
    out.add(TemplateRef(_unquote(raw), m.namedGroup('alias')));
  }
  return out;
}

/// Artifact-root-relative POSIX paths of every `.html` file under [artifactDir].
List<String> _htmlFiles(String artifactDir) {
  final dir = Directory(artifactDir);
  if (!dir.existsSync()) return const [];
  final out = <String>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.html')) continue;
    out.add(p.split(p.relative(e.path, from: artifactDir)).join('/'));
  }
  out.sort();
  return out;
}

/// includee → the files that reference it, for every `.html` in the tree.
///
/// Keys and values are artifact-root-relative POSIX paths. Self-references are
/// dropped (a macro file importing itself is not a consumer of itself).
Map<String, Set<String>> buildIncludeGraph(String artifactDir) {
  final graph = <String, Set<String>>{};
  for (final rel in _htmlFiles(artifactDir)) {
    final src = stripComments(File(p.join(artifactDir, rel)).readAsStringSync());
    for (final ref in parseTemplateRefs(src)) {
      if (ref.path == rel) continue;
      (graph[ref.path] ??= <String>{}).add(rel);
    }
  }
  return graph;
}

// ══ scopes ══════════════════════════════════════════════════════════════

/// A widget file: any `.html` under a directory literally named `widgets`.
bool isWidget(String rel) => rel.split('/').contains('widgets');

/// The three legal widget homes, widest first. [dir] is the widget's parent
/// directory (the `widgets/` dir itself), root-relative POSIX.
enum WidgetHome { common, shell, surface }

/// Where a widget at [rel] currently lives, plus the scope key that home claims.
///
/// - `ui/common/widgets/**`            → common, key `''`
/// - `ui/views/<shell>/shared/widgets/**` → shell, key `ui/views/<shell>`
/// - `<dir>/widgets/**`                → surface, key `<dir>`
///
/// Returns null when the path is under a `widgets/` dir that fits no home —
/// `ui/views/<shell>/widgets/` is the illegal bare case W1 reports by name.
({WidgetHome home, String key})? widgetHomeOf(String rel) {
  final segs = rel.split('/');
  final wi = segs.indexOf('widgets');
  if (wi < 0) return null;
  final dir = segs.sublist(0, wi).join('/');
  if (dir == 'ui/common') return (home: WidgetHome.common, key: '');
  final d = dir.split('/');
  // ui/views/<shell>/shared → shell home. ui/views/<shell> alone → illegal.
  if (d.length >= 3 && d[0] == 'ui' && d[1] == 'views') {
    if (d.length == 3) return null; // bare <shell>/widgets/
    if (d.length == 4 && d[3] == 'shared') {
      return (home: WidgetHome.shell, key: 'ui/views/${d[2]}');
    }
  }
  return (home: WidgetHome.surface, key: dir);
}

/// The shell a path belongs to, or null for `ui/common/**` and anything outside
/// `ui/views/`. Shell = the first segment under `ui/views/`.
String? shellOf(String rel) {
  final segs = rel.split('/');
  if (segs.length >= 3 && segs[0] == 'ui' && segs[1] == 'views') return segs[2];
  return null;
}

/// The directory that contains [rel], root-relative POSIX ('' at the root).
String _dirOf(String rel) {
  final i = rel.lastIndexOf('/');
  return i < 0 ? '' : rel.substring(0, i);
}

// ══ W1 · W2 — placement and dead widgets ════════════════════════════════

/// W1 + W2 over the include graph.
///
/// ponytail: consumer scope is read from DIRECT includers, not the transitive
/// closure. A misplaced widget therefore drags its children's required scope
/// with it (a common widget consumed only by main_shell makes everything it
/// includes look common too). That resolves by fixpoint — fix the parent, rerun,
/// the children settle — and it keeps each message pointing at one file the
/// reader can actually move. A transitive closure would name the same violation
/// from every leaf that reaches it.
List<LintFinding> _placementFindings(
    String artifactDir, Map<String, Set<String>> graph) {
  final findings = <LintFinding>[];
  final all = _htmlFiles(artifactDir);
  final surfaceDirs = _surfaceDirs(all);
  for (final rel in all) {
    if (!isWidget(rel)) continue;
    final consumers = graph[rel] ?? const <String>{};

    // ── W2: a widget nobody includes is a deletion, not a widget.
    if (consumers.isEmpty) {
      findings.add(LintFinding(rel,
          'W2: widget has zero includers (dead) — delete it, or include it '
          'from the surface that needs it'));
      continue;
    }

    final home = widgetHomeOf(rel);
    if (home == null) {
      final shell = shellOf(rel) ?? '<shell>';
      findings.add(LintFinding(rel,
          'W1: `ui/views/$shell/widgets/` is not a legal widget home — move to '
          '`ui/views/$shell/shared/widgets/` (2+ surfaces of $shell) or to '
          '`<surface>/widgets/` (one surface)'));
      continue;
    }

    // ── the narrowest scope covering every consumer.
    //
    // Each consumer contributes the directory its OWN scope covers, which is not
    // always the directory it sits in: a consumer that is itself a widget covers
    // its home's scope. A shell-scoped widget included only by another
    // shell-scoped widget in the same folder is correctly placed — reading the
    // literal parent directory instead would demand it move into a `widgets/`
    // inside `widgets/`.
    final scopeDirs = consumers.map(_consumerScopeDir).toSet();
    final required = _requiredHome(_commonAncestor(scopeDirs), surfaceDirs);

    if (required.home == home.home && required.key == home.key) continue;

    final dest = _destination(required, p.basename(rel));
    findings.add(LintFinding(rel, 'W1: ${_why(required, scopeDirs)} — move to `$dest`'));
  }
  return findings;
}

/// The directory a consumer's scope covers (see [_placementFindings]).
String _consumerScopeDir(String consumer) {
  final home = widgetHomeOf(consumer);
  if (home == null) return _dirOf(consumer);
  return switch (home.home) {
    WidgetHome.common => '',
    WidgetHome.shell => home.key,
    WidgetHome.surface => home.key,
  };
}

/// Deepest directory containing all of [dirs] (path-segment prefix, POSIX).
String _commonAncestor(Iterable<String> dirs) {
  final lists = dirs.map((d) => d.isEmpty ? <String>[] : d.split('/')).toList();
  if (lists.isEmpty) return '';
  var prefix = lists.first;
  for (final l in lists.skip(1)) {
    var i = 0;
    while (i < prefix.length && i < l.length && prefix[i] == l[i]) {
      i++;
    }
    prefix = prefix.sublist(0, i);
  }
  return prefix.join('/');
}

/// The home that covers [ancestor]: the placement law, read off the graph.
///
/// The law names exactly THREE homes, so an ancestor that is not a surface must
/// round UP to the shell rather than inventing a fourth tier. `ui/views/
/// main_shell/intake/` — a section holding eight surfaces — is the case that
/// matters: two consumers in different intake surfaces ancestor up to `intake/`,
/// and `intake/widgets/` is not a home the placement law or the scaffolder
/// recognises. Walking up to the nearest real surface keeps "narrowest scope"
/// meaning "narrowest LEGAL scope".
({WidgetHome home, String key}) _requiredHome(
    String ancestor, Set<String> surfaceDirs) {
  final segs = ancestor.isEmpty ? <String>[] : ancestor.split('/');
  if (segs.length >= 3 && segs[0] == 'ui' && segs[1] == 'views') {
    final shellKey = 'ui/views/${segs[2]}';
    var d = ancestor;
    while (d.split('/').length > 3) {
      if (surfaceDirs.contains(d)) return (home: WidgetHome.surface, key: d);
      d = _dirOf(d);
    }
    return (home: WidgetHome.shell, key: shellKey);
  }
  // '', 'ui', 'ui/views', 'ui/common/**' and anything outside the shell tree
  // are all covered only by the cross-shell home.
  return (home: WidgetHome.common, key: '');
}

/// Surfaces, identified structurally: a directory holding a `*_view.html`.
///
/// This is what separates a surface from a section. `ui/views/main_shell/intake/`
/// holds `_shared.html` and `routes.intake.js` but no `*_view.html`; each of its
/// children (`brief/`, `flows/`, …) holds one. A shell's own
/// `<shell>_view.html` makes the shell root look like a surface, so it is
/// excluded — the shell root is the shell home, never a surface.
Set<String> _surfaceDirs(List<String> htmlFiles) {
  final out = <String>{};
  for (final rel in htmlFiles) {
    final name = p.basename(rel);
    if (!name.endsWith('_view.html')) continue;
    if (isWidget(rel)) continue;
    final dir = _dirOf(rel);
    final shell = shellOf(rel);
    if (shell != null && dir == 'ui/views/$shell') continue; // shell root
    out.add(dir);
  }
  return out;
}

String _destination(({WidgetHome home, String key}) required, String name) =>
    switch (required.home) {
      WidgetHome.common => 'ui/common/widgets/$name',
      WidgetHome.shell => '${required.key}/shared/widgets/$name',
      WidgetHome.surface => '${required.key}/widgets/$name',
    };

String _why(({WidgetHome home, String key}) required, Set<String> scopeDirs) {
  // Name the consumers, capped — a placement failure is fixed by looking at who
  // includes the widget, so the message should save the reader that grep.
  final dirs = scopeDirs.map((d) => d.isEmpty ? 'ui/common' : d).toList()..sort();
  final shown =
      dirs.length <= 3 ? dirs.join(', ') : '${dirs.take(3).join(', ')}, +${dirs.length - 3} more';
  return switch (required.home) {
    WidgetHome.common =>
      'consumers ($shown) reach beyond any one shell, so only the cross-shell home covers them',
    WidgetHome.shell =>
      'the narrowest scope covering every consumer ($shown) is the '
          '${required.key.split('/').last} shell',
    WidgetHome.surface => 'every consumer ($shown) is confined to ${required.key}',
  };
}

// ══ W3 — the panel skeleton lives in one file ═══════════════════════════

final _classAttrRe = RegExp(r'''class\s*=\s*(?:"([^"]*)"|'([^']*)')''');

List<LintFinding> _panelReimplementationFindings(
    String artifactDir, List<LintFinding>? notes) {
  final base = File(p.join(artifactDir, panelBaseWidget));
  if (!base.existsSync()) {
    // Transition tolerance: a tree that has not reached D4 has nowhere legal to
    // put the skeleton, so flagging every use would be noise. Skipped, not passed.
    //
    // The note is worth printing only for a tree that HAS a UI (a design artifact
    // mid-migration). A fixture of two loose .html files is not mid-migration —
    // the rule simply does not address it, and a note there is noise in the
    // channel the ADR-0002 lint uses for its own advisories.
    if (Directory(p.join(artifactDir, 'ui')).existsSync()) {
      notes?.add(LintFinding(panelBaseWidget,
          'W3 skipped: no panel base widget in this artifact — the rule cannot '
          'distinguish instantiation from re-implementation until one exists'));
    }
    return const [];
  }
  final findings = <LintFinding>[];
  final structural = panelStructuralClasses.toSet();
  for (final rel in _htmlFiles(artifactDir)) {
    if (rel == panelBaseWidget) continue;
    final src = stripComments(File(p.join(artifactDir, rel)).readAsStringSync());
    final hits = <String>{};
    for (final m in _classAttrRe.allMatches(src)) {
      final value = m.group(1) ?? m.group(2) ?? '';
      for (final cls in value.split(RegExp(r'\s+'))) {
        if (structural.contains(cls)) hits.add(cls);
      }
    }
    if (hits.isEmpty) continue;
    final named = (hits.toList()..sort()).join(', ');
    findings.add(LintFinding(rel,
        'W3: panel skeleton classes ($named) outside `$panelBaseWidget` — '
        'instantiate the panel base instead of re-implementing it'));
  }
  return findings;
}

// ══ W4 — shell composition ══════════════════════════════════════════════

/// Role panels a shell view mounts, counted by macro-call site.
///
/// ponytail: a mount inside `{% if %}`/`{% else %}` branches counts once per
/// branch, so a shell that renders the same role two ways reads as a duplicate.
/// Counting distinct branches would need a template parser, not a regex; the
/// D4 rule ("declares which role panels it mounts") reads the declaration as
/// unconditional, so branch-aware counting would be measuring the wrong thing.
List<LintFinding> _shellCompositionFindings(
    String artifactDir, List<LintFinding>? notes) {
  final findings = <LintFinding>[];
  final roles = panelRoles.toSet();
  final all = _htmlFiles(artifactDir);
  // Same honesty as W3: with no role-panel widgets there is nothing to compose,
  // so a silent pass would read as "composition checked" when it was not.
  final hasRolePanels = all.any((rel) =>
      isWidget(rel) &&
      roles.any((r) => p.basename(rel) == '${r}_panel.html'));
  if (!hasRolePanels) {
    if (Directory(p.join(artifactDir, 'ui', 'views')).existsSync()) {
      notes?.add(LintFinding('ui/views',
          'W4 skipped: no role-panel widgets (<role>_panel.html under a '
          '`widgets/` dir) — nothing to compose yet'));
    }
    return const [];
  }
  for (final rel in all) {
    final name = p.basename(rel);
    if (!name.endsWith('_shell_view.html') && !name.endsWith('_view.html')) {
      continue;
    }
    final shell = shellOf(rel);
    // Only a shell's own view composes panels: ui/views/<shell>/<shell>_view.html.
    if (shell == null || name != '${shell}_view.html') continue;

    final src = stripComments(File(p.join(artifactDir, rel)).readAsStringSync());
    final mounts = <String, int>{};
    for (final ref in parseTemplateRefs(src)) {
      final refName = p.basename(ref.path);
      if (!refName.endsWith('_panel.html')) continue;
      if (!isWidget(ref.path)) continue;
      final role = refName.substring(0, refName.length - '_panel.html'.length);
      if (!roles.contains(role)) {
        findings.add(LintFinding(rel,
            'W4: mounts `$refName`, which is not one of the five panel roles '
            '(${panelRoles.join(', ')}) — rename it to a role or stop mounting '
            'it from the shell view'));
        continue;
      }
      // An `import … as X` mounts once per macro call; a bare include mounts once.
      final count = ref.alias == null
          ? 1
          : RegExp('(?<![A-Za-z_0-9])${RegExp.escape(ref.alias!)}\\s*\\.')
              .allMatches(src)
              .length;
      mounts[role] = (mounts[role] ?? 0) + count;
    }
    for (final role in panelRoles) {
      final n = mounts[role] ?? 0;
      if (n > 1) {
        findings.add(LintFinding(rel,
            'W4: mounts the $role panel $n times — a shell mounts each role at '
            'most once; keep one mount and move the variation inside the panel'));
      }
    }
  }
  return findings;
}

// ══ W5 — chip singularity ═══════════════════════════════════════════════

/// `border-radius: 999px` / `9999px`. `50%` circles are exempt and never match.
final _pillRadiusRe =
    RegExp(r'border-radius\s*:\s*[^;{}]*?9{3,4}px', caseSensitive: false);

List<LintFinding> _pillRadiusFindings(String artifactDir) {
  final findings = <LintFinding>[];
  final dir = Directory(artifactDir);
  if (!dir.existsSync()) return findings;
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = p.split(p.relative(e.path, from: artifactDir)).join('/');
    // Vendored stylesheets are not ours to edit, so failing on their pill radii
    // would leave the gate permanently red on a file nobody can fix. The
    // ADR-0002 rules allowlist `/assets/vendor/` for the same reason.
    if (rel.startsWith('assets/vendor/')) continue;
    if (rel.endsWith('.css')) {
      if (rel == widgetsCssPath) continue;
      if (_pillRadiusRe.hasMatch(e.readAsStringSync())) {
        findings.add(LintFinding(rel,
            'W5: pill radius (999px/9999px) outside `$widgetsCssPath` — the '
            'chip widget owns the pill; move the rule there and use the chip '
            '(`50%` circles are exempt)'));
      }
      continue;
    }
    if (!rel.endsWith('.html')) continue;
    final src = stripComments(e.readAsStringSync());
    for (final m in RegExp(r'''style\s*=\s*(?:"([^"]*)"|'([^']*)')''')
        .allMatches(src)) {
      final value = m.group(1) ?? m.group(2) ?? '';
      if (_pillRadiusRe.hasMatch(value)) {
        findings.add(LintFinding(rel,
            'W5: pill radius (999px/9999px) in an inline `style=` — use the '
            'chip widget instead of restating its radius'));
        break;
      }
    }
  }
  return findings;
}

// ══ W6 — session-key namespacing ════════════════════════════════════════

/// Direct session writes: `h.session(c).data.foo = …`, `session.data['foo'] = …`,
/// `sd.foo ??= …`. The captured group is the ROOT key.
final _sessionWriteRes = <RegExp>[
  RegExp(r'''session\s*\([^)]*\)\s*\.\s*data\s*\.\s*([A-Za-z_$][\w$]*)\s*(?:\?\?)?=(?!=)'''),
  RegExp(r'''session\s*\([^)]*\)\s*\.\s*data\s*\[\s*['"]([^'"]+)['"]\s*\]\s*(?:\?\?)?=(?!=)'''),
  RegExp(r'''\bsession\s*\.\s*data\s*\.\s*([A-Za-z_$][\w$]*)\s*(?:\?\?)?=(?!=)'''),
  RegExp(r'''\bsession\s*\.\s*data\s*\[\s*['"]([^'"]+)['"]\s*\]\s*(?:\?\?)?=(?!=)'''),
];

/// Drop `//` line comments and `/* … */` blocks. Deliberately naive: it does
/// not track strings or regex literals, so a `//` inside a string literal eats
/// the rest of that line. That direction is safe for a hard-fail gate — it can
/// only hide a violation, never invent one.
String _stripJsComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Directories under a shell that are structure, not namespace: the shell-widget
/// overlay and any `widgets/` dir. Never groups, never surfaces.
const _overlayDirNames = <String>{'shared', 'widgets'};

/// The session-key roots the viewmodel at [rel] may write.
///
/// Ownership, not recognition: `app` (cross-shell), the viewmodel's OWN shell,
/// and every hosted-shell GROUP on its own path — an ancestor between the shell
/// and the file that is neither a surface nor a structural overlay.
///
/// Groups are namespaces because a shell can HOST other shells: the studio's
/// `main_shell/intake`, `main_shell/design` and `main_shell/build` are hosted
/// shells whose facades legitimately own `intake.*`, `design.*`, `build.*`. A
/// literal `<path-shell>.` rule would call all three illegal and be wrong about
/// the product model, not about the code. Ancestors count because panel-level
/// state can live at the host tier: a viewmodel under `main_shell/intake/brief`
/// may write both `intake.*` and `main_shell.*`.
///
/// A root that is a real namespace ELSEWHERE in the tree still fails here —
/// existing somewhere is not owning it here.
Set<String> _legalRootsForPath(String rel, Set<String> surfaceDirs) {
  final roots = <String>{'app'};
  final segs = rel.split('/');
  if (segs.length < 4 || segs[0] != 'ui' || segs[1] != 'views') return roots;
  roots.add(segs[2]); // the owning shell
  var dir = 'ui/views/${segs[2]}';
  // Ancestor dirs strictly between the shell and the file itself.
  for (var i = 3; i < segs.length - 1; i++) {
    final name = segs[i];
    dir = '$dir/$name';
    if (_overlayDirNames.contains(name)) continue; // structure, not namespace
    if (surfaceDirs.contains(dir)) continue; // a surface is not a hosted shell
    roots.add(name);
  }
  return roots;
}

/// W6 over viewmodels only.
///
/// ponytail: this covers DIRECT session writes from a `*_viewmodel.js` whose
/// path names its shell. It cannot cover facade-mediated writes — a facade in
/// `services/facades/` owns the root key (`sd.intake ??= {…}`) but its path
/// names no shell, so there is no static owner to check the key against. Those
/// writes are invisible to this rule, by construction, not by omission. Making
/// them checkable needs the facade to declare its namespace (or to move under
/// the shell it serves); until then W6 is a floor, not a ceiling.
List<LintFinding> _stateNamespaceFindings(
    String artifactDir, List<LintFinding>? notes) {
  final findings = <LintFinding>[];
  final dir = Directory(artifactDir);
  if (!dir.existsSync()) return findings;
  final surfaceDirs = _surfaceDirs(_htmlFiles(artifactDir));
  var scanned = 0;
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = p.split(p.relative(e.path, from: artifactDir)).join('/');
    if (!rel.endsWith('_viewmodel.js')) continue;
    final shell = shellOf(rel);
    if (shell == null) continue; // ui/common viewmodels: app-scoped, see below.
    scanned++;
    // Commented-out code is not a violation — the same precedent `stripComments`
    // sets for the ADR-0002 lint, applied to JS instead of markup.
    final src = _stripJsComments(e.readAsStringSync());
    final legal = _legalRootsForPath(rel, surfaceDirs);
    final bad = <String>{};
    for (final re in _sessionWriteRes) {
      for (final m in re.allMatches(src)) {
        final key = m.group(1)!;
        if (legal.contains(key)) continue;
        bad.add(key);
      }
    }
    final legalList = (legal.toList()..sort()).join(', ');
    for (final key in bad.toList()..sort()) {
      findings.add(LintFinding(rel,
          'W6: writes session key `$key`, a namespace this viewmodel does not '
          'own — it may write $legalList (its shell, the hosted shells above it, '
          'or cross-shell `app`); rename it to `$shell.$key`, or to '
          '`$shell.<panel>.$key` for panel state'));
    }
  }
  // As with W3: only a tree that has shells at all can be "missing" viewmodels.
  if (scanned == 0 && Directory(p.join(artifactDir, 'ui', 'views')).existsSync()) {
    notes?.add(LintFinding('ui/views',
        'W6 skipped: no shell-scoped `*_viewmodel.js` in this artifact'));
  }
  return findings;
}

// ══ entry point ═════════════════════════════════════════════════════════

/// Run W1–W6 over the design artifact at [artifactDir].
///
/// Returns the hard-fail findings in rule order. [notes] collects the advisory
/// skipped-with-note channel (a rule that cannot apply to this tree yet), which
/// rides stdout and never moves the exit code — the same vehicle the ADR-0002
/// lint uses for its inferred-fn notes.
///
/// Kept OUT of `lintArtifact` deliberately: `design_cli`'s self-check and
/// `design_selftest` both assert `lintArtifact(...)` is empty on synthetic
/// ADR-0002 fixtures, which carry no widget tree and would trip W2/W6 noise.
List<LintFinding> gateDesignWidgets(String artifactDir,
    {List<LintFinding>? notes}) {
  final graph = buildIncludeGraph(artifactDir);
  return <LintFinding>[
    ..._placementFindings(artifactDir, graph),
    ..._panelReimplementationFindings(artifactDir, notes),
    ..._shellCompositionFindings(artifactDir, notes),
    ..._pillRadiusFindings(artifactDir),
    ..._stateNamespaceFindings(artifactDir, notes),
  ];
}
