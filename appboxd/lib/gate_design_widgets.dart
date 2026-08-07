/// The W-gate: the widget placement law and the panel contract, enforced
/// against ANY design artifact tree (nothing here is studio-specific).
///
/// Six hard-fail rules, per docs/plans/widget-panel-vocabulary-reconciliation.md
/// D5. Every failure message begins with its rule id and names the concrete fix,
/// because the reader of a gate failure is someone who has to move a file:
///
///   W1  placement — a widget lives at the narrowest scope covering all its
///       consumers, enforced in BOTH directions (too broad and too narrow).
///   W2  dead widgets — zero importers is a deletion, not a widget.
///   W3  panels are instantiated, never re-implemented — the `.panel-*`
///       structural skeleton appears in markup only inside `_panel.tsx`.
///   W4  shell composition — `<shell>_view.tsx` mounts role panels from
///       {header, main, activity, composer, footer} by rendering the panel's
///       imported `Open` component, each at most once.
///   W5  chip singularity — pill radius (999px/9999px) only in the widgets CSS.
///   W6  state namespacing — a shell's viewmodels write session keys under
///       `<shell>.` or `app.` only.
///
/// The import graph is the only authority for W1/W2. No such parser existed in
/// appboxd before this file — the pre-existing "orphan sweeps" (emit_htmx,
/// emit_structure, gate_intake) are surface- and viewmodel-scoped and never
/// look at template imports — so [buildIncludeGraph] is new machinery.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_tools.dart' show LintFinding, stripComments;

// ══ vocabulary ══════════════════════════════════════════════════════════

/// The five panel roles. A shell mounts each at most once (W4); a widget named
/// `<role>_panel.tsx` is that role's instantiation.
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

/// The base widget that owns the panel skeleton, identified by NAME rather than
/// by a fixed path: `_panel.tsx` in any legal widget home.
///
/// A fixed `ui/common/widgets/_panel.tsx` would put W3 in direct conflict with
/// W1. W1 judges placement by real consumers, so a base whose only consumers are
/// one shell's role panels belongs in that shell's `shared/widgets/` — and a W3
/// that only ever looked in `ui/common/widgets/` would then report "no base" for
/// a tree that has one, correctly placed. The rule is "the skeleton lives in the
/// base", not "the base lives at this path".
const panelBaseName = '_panel.tsx';

/// Every legal widget home holding a `_panel.tsx`.
List<String> panelBaseWidgets(String artifactDir) => _templateFiles(artifactDir)
    .where((rel) =>
        p.basename(rel) == panelBaseName &&
        isWidget(rel) &&
        widgetHomeOf(rel) != null)
    .toList();

/// Where the pill radius is allowed to live (W5). The chip widget's rules are
/// consolidated here; no per-widget CSS files.
const widgetsCssPath = 'assets/css/widgets.css';

// ══ the import graph ════════════════════════════════════════════════════

/// A TSX import statement. `clause` is the binding list (`X`, `{ A, B as C }`,
/// `X, { A }`, `* as X`) — absent for a side-effect import (`import './x.css'`).
/// An optional `type` qualifier is allowed (`import type { FC } from …`).
final _importRe = RegExp(
    r'''import\s+(?:type\s+)?(?:(?<clause>[\w$]+|\{[^}]*\}|[\w$]+\s*,\s*\{[^}]*\}|\*\s+as\s+[\w$]+)\s+from\s+)?['"](?<path>[^'"]+)['"]''');

/// The bindings an import [clause] creates, as (imported, local) name pairs —
/// `Open as MainOpen` is `(imported: 'Open', local: 'MainOpen')`. The default
/// import reads as `(imported: 'default', …)`: its source name is unknowable
/// from the import alone, and every role panel re-exports its `Open` frame as
/// default, so W4 treats a default binding as a mount binding.
List<({String imported, String local})> _importBindings(String? clause) {
  if (clause == null) return const [];
  final out = <({String imported, String local})>[];
  if (!clause.startsWith('{') && !clause.startsWith('*')) {
    out.add((
      imported: 'default',
      local: RegExp(r'[\w$]+').firstMatch(clause)![0]!,
    ));
  }
  final named = RegExp(r'\{([^}]*)\}').firstMatch(clause);
  if (named != null) {
    for (final part in named.group(1)!.split(',')) {
      final bits = part.trim().split(RegExp(r'\s+as\s+'));
      final imported = bits.first.trim();
      if (imported.isEmpty) continue;
      out.add((imported: imported, local: bits.last.trim()));
    }
  }
  return out;
}

/// Artifact-root-relative POSIX paths of every `.tsx` template under
/// [artifactDir].
List<String> _templateFiles(String artifactDir) {
  final dir = Directory(artifactDir);
  if (!dir.existsSync()) return const [];
  final out = <String>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File) continue;
    if (!e.path.endsWith('.tsx')) continue;
    out.add(p.split(p.relative(e.path, from: artifactDir)).join('/'));
  }
  out.sort();
  return out;
}

/// importee → the files that import it, for every template in the tree.
///
/// Keys and values are artifact-root-relative POSIX paths. Self-references are
/// dropped (a file importing itself is not a consumer of itself). Only RELATIVE
/// imports resolve into the tree — bare specifiers ('hono/jsx') are packages,
/// not files.
Map<String, Set<String>> buildIncludeGraph(String artifactDir) {
  final graph = <String, Set<String>>{};
  for (final rel in _templateFiles(artifactDir)) {
    final src = stripComments(File(p.join(artifactDir, rel)).readAsStringSync());
    final importerDir = p.dirname(rel);
    for (final m in _importRe.allMatches(src)) {
      final importPath = m.namedGroup('path')!;
      if (!importPath.startsWith('.')) continue;
      // Resolve relative to the importing file, normalize to
      // artifact-root-relative.
      final resolved =
          p.normalize(p.join(importerDir, importPath)).replaceAll('\\', '/');
      if (resolved == rel) continue;
      (graph[resolved] ??= <String>{}).add(rel);
    }
  }
  return graph;
}

// ══ scopes ══════════════════════════════════════════════════════════════

/// A widget file: any `.tsx` under a directory literally named `widgets`.
bool isWidget(String rel) => rel.split('/').contains('widgets');

/// The retired flat tier — `ui/widgets/`, `ui/dialogs/`, `ui/bottomsheets/` at
/// the artifact root, historically with a `components/` subfolder inside.
///
/// `ui/dialogs/` and `ui/bottomsheets/` hold no `widgets/` segment, so they are
/// invisible to [isWidget]; they are named here so the placement pass can see
/// the whole retired family rather than only the third of it that happens to be
/// spelled `widgets`.
const retiredFlatWidgetDirs = <String>[
  'ui/widgets/',
  'ui/dialogs/',
  'ui/bottomsheets/',
];

bool isRetiredFlatWidget(String rel) =>
    retiredFlatWidgetDirs.any(rel.startsWith);

/// The three legal widget homes, widest first. [dir] is the widget's parent
/// directory (the `widgets/` dir itself), root-relative POSIX.
enum WidgetHome { common, shell, surface }

/// Where a widget at [rel] currently lives, plus the scope key that home claims.
///
/// - `ui/common/widgets/**`            → common, key `''`
/// - `ui/views/<shell>/shared/widgets/**` → shell, key `ui/views/<shell>`
/// - `<dir>/widgets/**`                → surface, key `<dir>`
///
/// Returns null when the path is under a `widgets/` dir that fits no home. Two
/// such cases exist and W1 reports each BY NAME rather than as a scope problem:
/// the bare `ui/views/<shell>/widgets/`, and the retired flat `ui/widgets/`.
///
/// A surface home must live under `ui/views/`. Returning one for any unmatched
/// directory is what used to map the flat `ui/widgets/x.tsx` onto a surface
/// home keyed `ui`, so a legacy tree drew "every consumer is confined to
/// ui/views/main_shell — move to …" (a scope complaint about a file whose real
/// problem is that it sits in a retired tier) instead of being told to migrate.
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
    return (home: WidgetHome.surface, key: dir);
  }
  return null;
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

/// W1 + W2 over the import graph.
///
/// ponytail: consumer scope is read from DIRECT importers, not the transitive
/// closure. A misplaced widget therefore drags its children's required scope
/// with it (a common widget consumed only by main_shell makes everything it
/// imports look common too). That resolves by fixpoint — fix the parent, rerun,
/// the children settle — and it keeps each message pointing at one file the
/// reader can actually move. A transitive closure would name the same violation
/// from every leaf that reaches it.
List<LintFinding> _placementFindings(
    String artifactDir, Map<String, Set<String>> graph) {
  final findings = <LintFinding>[];
  final all = _templateFiles(artifactDir);
  final surfaceDirs = _surfaceDirs(all);
  for (final rel in all) {
    if (!isWidget(rel) && !isRetiredFlatWidget(rel)) continue;
    final consumers = graph[rel] ?? const <String>{};

    // ── W2: a widget nobody imports is a deletion, not a widget.
    if (consumers.isEmpty) {
      findings.add(LintFinding(rel,
          'W2: widget has zero importers (dead) — delete it, or import it '
          'from the surface that needs it'));
      continue;
    }

    // ── W1: the retired flat tier, named as such. Its problem is the tier, not
    // the scope, so say so — a scope message here sends the reader to measure
    // consumers when the fix is a migration.
    if (isRetiredFlatWidget(rel)) {
      final tier = retiredFlatWidgetDirs.firstWhere(rel.startsWith);
      findings.add(LintFinding(rel,
          'W1: `$tier` is the retired flat widget tier, not a legal home — move '
          'to `ui/common/widgets/` (consumers in 2+ shells), '
          '`ui/views/<shell>/shared/widgets/` (2+ surfaces of one shell), or '
          '`<surface>/widgets/` (one surface)'));
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
    // its home's scope. A shell-scoped widget imported only by another
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

/// Surfaces, identified structurally: a directory holding a `*_view.tsx`.
///
/// This is what separates a surface from a section. `ui/views/main_shell/intake/`
/// holds `_shared.tsx` and `routes.intake.js` but no `*_view.tsx`; each of its
/// children (`brief/`, `flows/`, …) holds one. A shell's own
/// `<shell>_view.tsx` makes the shell root look like a surface, so it is
/// excluded — the shell root is the shell home, never a surface.
Set<String> _surfaceDirs(List<String> templateFiles) {
  final out = <String>{};
  for (final rel in templateFiles) {
    final name = p.basename(rel);
    if (!name.endsWith('_view.tsx')) continue;
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
  // imports the widget, so the message should save the reader that grep.
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

/// hono/jsx keeps the HTML attribute name: `class="…"` / `class='…'`, or a
/// computed class string as a backtick template (`class={`…`}`).
final _classAttrRe =
    RegExp(r'''class\s*=\s*(?:"([^"]*)"|'([^']*)'|\{`([^`]*)`\})''');

List<LintFinding> _panelReimplementationFindings(
    String artifactDir, List<LintFinding>? notes) {
  final bases = panelBaseWidgets(artifactDir).toSet();
  if (bases.isEmpty) {
    // Transition tolerance: a tree that has not reached D4 has nowhere legal to
    // put the skeleton, so flagging every use would be noise. Skipped, not passed.
    //
    // The note is worth printing only for a tree that HAS a UI (a design artifact
    // mid-migration). A fixture of two loose .tsx files is not mid-migration —
    // the rule simply does not address it, and a note there is noise in the
    // channel the ADR-0002 lint uses for its own advisories.
    if (Directory(p.join(artifactDir, 'ui')).existsSync()) {
      notes?.add(LintFinding('ui',
          'W3 skipped: no `$panelBaseName` in any widget home — the rule cannot '
          'distinguish instantiation from re-implementation until a base exists'));
    }
    return const [];
  }
  final findings = <LintFinding>[];
  final structural = panelStructuralClasses.toSet();
  for (final rel in _templateFiles(artifactDir)) {
    if (bases.contains(rel)) continue;
    final src = stripComments(File(p.join(artifactDir, rel)).readAsStringSync());
    final hits = <String>{};
    for (final m in _classAttrRe.allMatches(src)) {
      final value = m.group(1) ?? m.group(2) ?? m.group(3) ?? '';
      for (final cls in value.split(RegExp(r'\s+'))) {
        if (structural.contains(cls)) hits.add(cls);
      }
    }
    if (hits.isEmpty) continue;
    final named = (hits.toList()..sort()).join(', ');
    findings.add(LintFinding(rel,
        'W3: panel skeleton classes ($named) outside the panel base '
        '(${bases.join(', ')}) — instantiate the base instead of '
        're-implementing it'));
  }
  return findings;
}

// ══ W4 — shell composition ══════════════════════════════════════════════

/// True when [rel] sits under a hosted-shell GROUP dir — an immediate child of
/// a shell that is neither a surface nor a structural overlay.
///
/// The same tier W6 treats as a namespace owner (`main_shell/intake`,
/// `main_shell/design`, `main_shell/build`): a shell hosting other shells. One
/// definition of "hosted shell" across both rules, so a dir cannot be a shell
/// for state and not a shell for composition.
bool _underHostedGroup(String rel, Set<String> surfaceDirs) {
  final segs = rel.split('/');
  if (segs.length < 5 || segs[0] != 'ui' || segs[1] != 'views') return false;
  if (_overlayDirNames.contains(segs[3])) return false;
  return !surfaceDirs.contains('ui/views/${segs[2]}/${segs[3]}');
}

// The nunjucks gate carried an open/close BALANCE rule here (a `{% macro %}`
// pair can go unbalanced). JSX components are balanced by construction — the
// TSX compiler owns that check now, so there is nothing to count.

/// Role panels a shell view mounts, counted by JSX use of the panel's `Open`
/// component.
///
/// The mount convention, read off the studio tree: a role panel
/// `<role>_panel.tsx` exports `Open` — the frame — plus section/body helpers
/// (`Top`, `Bottom`, `PanelBar`, `Empty`, `View`, …) for OOB refreshes, and
/// re-exports `Open` as default. So a shell MOUNTS a role by rendering the
/// imported `Open` binding (`import { Open as MainOpen } …` → `<MainOpen>…`)
/// or the default import (`import HeaderPanel from '…/header_panel.tsx'` →
/// `<HeaderPanel>…`). Using a helper export is composing INSIDE a panel
/// someone else mounted, never a mount: counting every imported identifier
/// would read `design/_shared.tsx` — four names imported from main_panel.tsx,
/// one of them the frame — as a triple mount, the macro-library false
/// positive the nunjucks gate carried a whole apparatus to avoid.
///
/// ponytail: counting is regex-deep (`<Ident` open tags), like every other
/// rule in this file; a mount inside a conditional branch counts once per
/// branch, so a shell that renders the same role two ways reads as a
/// duplicate. Branch-aware counting would need an AST, and the D4 rule
/// ("declares which role panels it mounts") reads the declaration as
/// unconditional anyway.
List<LintFinding> _shellCompositionFindings(
    String artifactDir, List<LintFinding>? notes) {
  final findings = <LintFinding>[];
  final roles = panelRoles.toSet();
  final all = _templateFiles(artifactDir);
  // Same honesty as W3: with no role-panel widgets there is nothing to compose,
  // so a silent pass would read as "composition checked" when it was not.
  final hasRolePanels = all.any((rel) =>
      isWidget(rel) &&
      roles.any((r) => p.basename(rel) == '${r}_panel.tsx'));
  if (!hasRolePanels) {
    if (Directory(p.join(artifactDir, 'ui', 'views')).existsSync()) {
      notes?.add(LintFinding('ui/views',
          'W4 skipped: no role-panel widgets (<role>_panel.tsx under a '
          '`widgets/` dir) — nothing to compose yet'));
    }
    return const [];
  }
  final surfaceDirs = _surfaceDirs(all);
  for (final rel in all) {
    final name = p.basename(rel);
    final shell = shellOf(rel);
    final isShellView = shell != null && name == '${shell}_view.tsx';

    final src = stripComments(File(p.join(artifactDir, rel)).readAsStringSync());
    final importerDir = p.dirname(rel);
    // This file's panel imports. `role` is null for a `*_panel.tsx` widget
    // whose name is not one of the five roles.
    final panelImports =
        <({String? role, String refName, List<String> mountIdents})>[];
    for (final m in _importRe.allMatches(src)) {
      final importPath = m.namedGroup('path')!;
      if (!importPath.startsWith('.')) continue;
      final resolved =
          p.normalize(p.join(importerDir, importPath)).replaceAll('\\', '/');
      final refName = p.basename(resolved);
      if (!refName.endsWith('_panel.tsx') || !isWidget(resolved)) continue;
      final role = refName.substring(0, refName.length - '_panel.tsx'.length);
      final mountIdents = [
        for (final b in _importBindings(m.namedGroup('clause')))
          if (b.imported == 'default' || b.imported == 'Open') b.local,
      ];
      panelImports.add((
        role: roles.contains(role) ? role : null,
        refName: refName,
        mountIdents: mountIdents,
      ));
    }

    // A top-level shell declares its panel set in `<shell>_view.tsx`; a HOSTED
    // shell declares its own in whatever view composes it. Both are shell
    // views in the sense that matters, so both are checked.
    //
    // Detection is structural, not by filename: build's composition lives in a
    // surface view (`build/loop/loop_view.tsx`), so a `_shared.tsx` naming
    // rule would miss it. The scope is bounded to hosted-shell GROUP dirs so a
    // content widget that happens to compose a non-role panel — design_viewer
    // mounting mini_panel from `shared/widgets/` — is not read as a shell
    // declaring its panel set.
    if (!isShellView &&
        !(panelImports.isNotEmpty && _underHostedGroup(rel, surfaceDirs))) {
      continue;
    }

    // Counted PER FILE: two sibling composition files each mounting the
    // activity panel once are two shells with one activity panel, not a double
    // mount. Alternative layouts of one hosted shell are the same story.
    final mounts = <String, int>{};
    for (final imp in panelImports) {
      final role = imp.role;
      if (role == null) {
        findings.add(LintFinding(rel,
            'W4: mounts `${imp.refName}`, which is not one of the five panel '
            'roles (${panelRoles.join(', ')}) — rename it to a role or stop '
            'mounting it from the shell view'));
        continue;
      }
      // A mount is a JSX use of the panel's frame: the default import, or a
      // binding of the `Open` export. An unused mount binding is a dead
      // import, not a mount; helper bindings (Top/Bottom/PanelBar/…) are
      // never mounts.
      for (final ident in imp.mountIdents) {
        mounts[role] = (mounts[role] ?? 0) +
            RegExp('<$ident(?=[\\s>/])').allMatches(src).length;
      }
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

/// The one deliberate escape from W5: a radius that is a SHAPE, not a chip —
/// a progress track, a swatch, device chrome, a form input. Annotate the rule's
/// own line and it is skipped.
///
/// Deliberate-and-trail-leaving by construction: the escape is greppable, sits
/// on the line it excuses, and shows up in review as an addition. What it
/// replaces is worse — a blanket allowance, or the rule quietly not applying to
/// whole files.
///
/// CSS only. An inline `style=` has no escape hatch, on purpose: the structural
/// radii this exists for all live in stylesheets, and inline is where a chip
/// gets re-implemented by hand.
const w5Exemption = 'w5:not-a-chip';

/// The whole line(s) of [src] spanned by [start]..[end], so a trailing
/// annotation after the semicolon is seen.
String _lineSpan(String src, int start, int end) {
  var a = src.lastIndexOf('\n', start);
  a = a < 0 ? 0 : a + 1;
  var b = src.indexOf('\n', end);
  if (b < 0) b = src.length;
  return src.substring(a, b);
}

int _lineNumberAt(String src, int offset) =>
    '\n'.allMatches(src.substring(0, offset)).length + 1;

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
      final src = e.readAsStringSync();
      final unexempt = _pillRadiusRe
          .allMatches(src)
          .where((m) => !_lineSpan(src, m.start, m.end).contains(w5Exemption))
          .toList();
      if (unexempt.isNotEmpty) {
        final lines =
            unexempt.map((m) => _lineNumberAt(src, m.start)).join(', ');
        findings.add(LintFinding(rel,
            'W5: pill radius (999px/9999px) outside `$widgetsCssPath` at line '
            '$lines — the chip widget owns the pill; move the rule there and '
            'use the chip. If it is a shape and not a chip (progress track, '
            'swatch, device chrome, form input), annotate that line '
            '`/* $w5Exemption */` (`50%` circles are exempt and never match)'));
      }
      continue;
    }
    if (!rel.endsWith('.tsx')) continue;
    final src = stripComments(e.readAsStringSync());
    for (final m in RegExp(r'''style\s*=\s*(?:"([^"]*)"|'([^']*)'|\{`([^`]*)`\})''')
        .allMatches(src)) {
      final value = m.group(1) ?? m.group(2) ?? m.group(3) ?? '';
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
  final surfaceDirs = _surfaceDirs(_templateFiles(artifactDir));
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
