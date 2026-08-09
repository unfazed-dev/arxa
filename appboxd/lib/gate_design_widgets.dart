/// The W-gate: the widget placement law and the panel contract, enforced
/// against ANY design artifact tree (nothing here is studio-specific).
///
/// Seven hard-fail rules, per docs/plans/widget-panel-vocabulary-reconciliation.md
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
///   W7  widget identity — in surface/view templates (outside widget-library
///       dirs), a rendered HTML element that bears literal text or is
///       interactive (button|a|input|select|textarea) must carry widget
///       identity: a `data-el` attribute, an `inspectAttrs(...)` spread, or
///       be a Capitalized library-widget invocation.
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

/// The retired widget tiers — the old three-tier law's homes plus the flat
/// dialogs/bottomsheets family. None exist in the exemplar
/// (`kit/showcase_app/lib`), whose only widget root is `ui/widgets/`
/// (showcase-anatomy.md §2). Prefix-matched members live here;
/// `ui/views/**/widgets/` (bare shell, `shared/widgets/`, surface `widgets/`)
/// is detected structurally in [isRetiredWidgetPath] because the shell name
/// varies.
///
/// `ui/dialogs/` and `ui/bottomsheets/` hold no `widgets/` segment, so they are
/// invisible to [isWidget]; they are named here so the placement pass can see
/// the whole retired family rather than only the part that happens to be
/// spelled `widgets`.
const retiredWidgetTierPrefixes = <String>[
  'ui/common/widgets/',
  'ui/dialogs/',
  'ui/bottomsheets/',
];

bool isRetiredWidgetPath(String rel) {
  if (retiredWidgetTierPrefixes.any(rel.startsWith)) return true;
  // Any widgets/ dir inside the shell tree: bare `ui/views/<shell>/widgets/`,
  // `ui/views/<shell>/shared/widgets/`, `<surface>/widgets/`.
  final segs = rel.split('/');
  return segs.length >= 3 &&
      segs[0] == 'ui' &&
      segs[1] == 'views' &&
      segs.contains('widgets');
}

/// The two legal widget homes (showcase-anatomy.md §2), read off the exemplar:
/// cross-shell widgets in `ui/widgets/common/<group>/`, everything else in
/// `ui/widgets/<app>_<feature>_widgets/`.
enum WidgetHome { common, feature }

/// Where a widget at [rel] currently lives, plus the scope key that home claims.
///
/// - `ui/widgets/common/<group>/**`      → common,  key `ui/widgets/common/<group>`
/// - `ui/widgets/<feature>_widgets/**`   → feature, key `ui/widgets/<feature>_widgets`
///
/// Returns null when the path is under `ui/widgets/` but fits no home, and W1
/// reports each such case BY NAME rather than as a scope problem: a flat
/// `ui/widgets/x.tsx`, a flat `ui/widgets/common/x.tsx` (common is grouped,
/// never flat), and an unnamed group `ui/widgets/<name>/` whose name neither is
/// `common` nor ends `_widgets`. The last is legal in the exemplar only for
/// genuinely app-agnostic behavior wrappers (`ui/widgets/mouse_transforms/`,
/// showcase-anatomy.md §2) — a deliberate documented exception, not a home this
/// gate can verify, so the design tree takes the `_widgets` suffix.
({WidgetHome home, String key})? widgetHomeOf(String rel) {
  final segs = rel.split('/');
  if (segs.length < 4 || segs[0] != 'ui' || segs[1] != 'widgets') return null;
  final child = segs[2];
  if (child == 'common') {
    if (segs.length < 5) return null; // flat common/x.tsx
    return (home: WidgetHome.common, key: 'ui/widgets/common/${segs[3]}');
  }
  if (child.endsWith('_widgets')) {
    return (home: WidgetHome.feature, key: 'ui/widgets/$child');
  }
  return null; // unnamed group
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
  final shells = _shellDirs(artifactDir);
  for (final rel in all) {
    if (!isWidget(rel) && !isRetiredWidgetPath(rel)) continue;
    final consumers = graph[rel] ?? const <String>{};

    // ── W2: a widget nobody imports is a deletion, not a widget.
    if (consumers.isEmpty) {
      findings.add(LintFinding(rel,
          'W2: widget has zero importers (dead) — delete it, or import it '
          'from the surface that needs it'));
      continue;
    }

    // ── W1: a retired tier, named as such. Its problem is the tier, not the
    // scope, so say so — a scope message here sends the reader to measure
    // consumers when the fix is a migration.
    if (isRetiredWidgetPath(rel)) {
      final tier = retiredWidgetTierPrefixes
              .where(rel.startsWith)
              .firstOrNull ??
          rel.substring(0, rel.indexOf('/widgets/') + '/widgets/'.length);
      findings.add(LintFinding(rel,
          'W1: `$tier` is a retired widget tier (three-tier law, superseded) — '
          'the only widget root is `ui/widgets/`: move to '
          '`ui/widgets/common/<group>/` (consumers in 2+ shells) or '
          '`ui/widgets/<app>_<feature>_widgets/` (one feature, any of its '
          'surfaces)'));
      continue;
    }

    final home = widgetHomeOf(rel);
    if (home == null) {
      findings.add(LintFinding(rel, _illegalHomeMessage(rel)));
      continue;
    }

    // ── the shell reach of the consumers.
    //
    // Each consumer contributes the shells its OWN scope covers, which is not
    // always the shell it sits in: a consumer that is itself a widget covers
    // its home's reach, and a consumer under `ui/common/` (the base/document
    // layer every shell renders through) is cross-shell by construction.
    // Promotion to `common/<group>/` is earned by a second shell consumer,
    // proven by this graph, never by intent (showcase-anatomy.md §2).
    final reach = _consumerShellReach(consumers, shells);
    final required = _requiredHome(reach);

    // Which group/feature folder is a naming decision; the gate only forces
    // tier transitions the graph proves (promotion earned / demotion due).
    if (required.home == home.home) continue;

    final dest = _destination(required, p.basename(rel));
    findings.add(LintFinding(rel, 'W1: ${_why(required, reach)} — move to `$dest`'));
  }
  return findings;
}

/// W1 message for a path under `ui/widgets/` that fits neither home.
String _illegalHomeMessage(String rel) {
  final segs = rel.split('/');
  if (segs.length == 3) {
    return 'W1: flat file directly in `ui/widgets/` — widgets live in a group: '
        '`ui/widgets/common/<group>/` (2+ shells) or '
        '`ui/widgets/<app>_<feature>_widgets/` (one feature)';
  }
  if (segs[2] == 'common') {
    return 'W1: `ui/widgets/common/` is grouped, never flat — move into a '
        '`ui/widgets/common/<group>/` that names what the group shares';
  }
  return 'W1: `ui/widgets/${segs[2]}/` names no legal home — feature folders '
      'take the `<app>_<feature>_widgets` suffix; a bare group name is '
      'reserved for genuinely app-agnostic behavior wrappers '
      '(showcase-anatomy.md §2 names `mouse_transforms` as the deliberate '
      'exception)';
}

/// The shell reach of a consumer set (see [_placementFindings]).
///
/// A consumer under `ui/views/<shell>/` reaches that shell. A consumer that is
/// itself a widget covers its home's reach: `ui/widgets/common/**` is
/// cross-shell by placement, a feature widget adds no shell of its own (its
/// reach is whatever ITS consumers prove, which resolves by fixpoint — see the
/// ponytail note above). Anything under `ui/common/` or `runtime/` is the
/// base/document layer every shell renders through: cross-shell by
/// construction.
({bool crossShell, Set<String> shells, Set<String> dirs}) _consumerShellReach(
    Set<String> consumers, Set<String> shells) {
  var cross = false;
  final touched = <String>{};
  final dirs = <String>{};
  for (final c in consumers) {
    dirs.add(_dirOf(c));
    final home = widgetHomeOf(c);
    if (home != null) {
      if (home.home == WidgetHome.common) cross = true;
      continue; // feature widget: no shell of its own
    }
    final segs = c.split('/');
    if (segs.length >= 3 && segs[0] == 'ui' && segs[1] == 'views') {
      final shell = 'ui/views/${segs[2]}';
      if (shells.contains(shell)) touched.add(shell);
      continue;
    }
    // ui/common/**, runtime/**, and anything outside the view tree.
    cross = true;
  }
  return (crossShell: cross, shells: touched, dirs: dirs);
}

/// The home that covers [reach]: the two-tier placement law, read off the
/// graph (showcase-anatomy.md §2).
///
/// Promotion to `ui/widgets/common/<group>/` is EARNED — a second shell in the
/// import graph, or a cross-shell consumer — never declared by intent. One
/// shell (or none yet proven) keeps the widget in its feature folder; which
/// feature folder is a naming decision the gate does not second-guess, so a
/// feature-tier widget only moves when the graph proves promotion.
({WidgetHome home, String key}) _requiredHome(
    ({bool crossShell, Set<String> shells, Set<String> dirs}) reach) {
  if (reach.crossShell || reach.shells.length >= 2) {
    return (home: WidgetHome.common, key: 'ui/widgets/common/<group>');
  }
  return (home: WidgetHome.feature, key: 'ui/widgets/<app>_<feature>_widgets');
}

/// Shell roots, structurally: the directories directly under `ui/views/`.
Set<String> _shellDirs(String artifactDir) {
  final viewsDir = Directory(p.join(artifactDir, 'ui', 'views'));
  if (!viewsDir.existsSync()) return const {};
  return viewsDir
      .listSync()
      .whereType<Directory>()
      .map((d) => 'ui/views/${p.basename(d.path)}')
      .toSet();
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
    '${required.key}/$name';

String _why(({WidgetHome home, String key}) required,
    ({bool crossShell, Set<String> shells, Set<String> dirs}) reach) {
  // Name the consumers, capped — a placement failure is fixed by looking at who
  // imports the widget, so the message should save the reader that grep.
  final dirs = reach.dirs.toList()..sort();
  final shown =
      dirs.length <= 3 ? dirs.join(', ') : '${dirs.take(3).join(', ')}, +${dirs.length - 3} more';
  return switch (required.home) {
    WidgetHome.common =>
      'consumers ($shown) span ${reach.crossShell ? 'the cross-shell base layer' : '${reach.shells.length} shells'}, which earns promotion to the common tier',
    WidgetHome.feature =>
      'every consumer ($shown) sits in one feature — a common/ placement is unearned; demote to that feature\'s widget folder',
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

// ══ W7 — anonymous text/interactive elements in surface templates ══════

/// Interactive HTML elements that always require widget identity, even with no
/// text content: a bare `<button />` or `<a />` is an interaction the widget
/// library must own.
const _interactiveTags = <String>{'button', 'a', 'input', 'select', 'textarea'};

/// Roles that may bear direct text content. Text inside any other role (or with
/// no `data-el` carrier at all) must flow through a Label/Heading/Txt widget so
/// every visible string resolves to its own identity on inspect.
const _textBearingRoles = <String>{
  'label', 'heading', 'text', 'button', 'link', 'chip', 'badge',
  'input', 'option',
};

/// The first direct text snippet after the opening tag at [tagEnd] in [src],
/// or null when the tag has only element children / whitespace. Handles the
/// `<tag><Icon/> text</tag>` blind spot (self-closing child then text).
///
/// JSX expressions (`{expr}`) are NOT literal text: a snippet that starts with
/// `{` is a JSX child expression (e.g. `{cond ? (<A/> : <B/)}), and the next
/// `<` it finds belongs to a component inside that expression, not a sibling
/// element. Without this guard, every conditional-child wrapper in the studio
/// would be a false positive.
String? _directTextSnippet(String src, int tagEnd) {
  final nextLt = src.indexOf('<', tagEnd);
  final between = src.substring(tagEnd, nextLt < 0 ? src.length : nextLt);
  final trimmed = between.trim();
  if (trimmed.isNotEmpty && !trimmed.startsWith('{')) return trimmed;
  if (nextLt >= tagEnd && nextLt < src.length) {
    final childEnd = src.indexOf('>', nextLt);
    if (childEnd >= 0 && src.substring(nextLt, childEnd + 1).endsWith('/>')) {
      final afterSc = childEnd + 1;
      final nextLtSc = src.indexOf('<', afterSc);
      final textSc = src.substring(afterSc, nextLtSc < 0 ? src.length : nextLtSc);
      final trimmedSc = textSc.trim();
      if (trimmedSc.isNotEmpty && !trimmedSc.startsWith('{')) return trimmedSc;
    }
  }
  return null;
}

/// Truncates [text] for inclusion in a failure message.
String _snippet(String? text) {
  if (text == null) return '';
  return text.length <= 40 ? text : '${text.substring(0, 37)}…';
}

/// Known HTML element names. Restricting the scan to these eliminates false
/// positives from TypeScript generics (`Record<string, …>`, `Array<T>`) that
/// happen to look like `<lowercase>` after comment stripping.
const _htmlElements = <String>{
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

// kimitail: line-regex scan like the sibling rules, not a JSX parser — upgrade
// only if false positives appear in practice. The _htmlElements allowlist is
// the one upgrade applied: TS generics (Record<string, …>) produce <lowercase>
// matches that a bare regex cannot distinguish from HTML tags.
final _openingTagRe = RegExp(r'<([a-z][\w-]*)([^>]*?)(/?)>');

/// W7: in surface/view templates (NOT in widget-library dirs), a rendered HTML
/// element that bears literal text or is interactive must carry widget identity
/// — a `data-el` attribute, an `inspectAttrs(...)` spread, or be a library-widget
/// invocation. Capitalized tags (`<Label>`, `<Heading>`) are component
/// invocations, not raw HTML, so they are exempt by construction (the regex only
/// matches lowercase-opening tags).
///
/// Additionally, an element that DOES carry identity but whose `data-inspect-role`
/// is not a text-bearing role (card/panel/nav/section…) must not bear direct
/// text content either — that text must flow through a Label/Heading/Txt widget
/// so it resolves to its own `data-el` on inspect.
///
/// The failure output doubles as the migration worklist: each finding names the
/// file, line, and tag that needs wrapping.
List<LintFinding> _anonymousElementFindings(String artifactDir) {
  final findings = <LintFinding>[];
  for (final rel in _templateFiles(artifactDir)) {
    // Widget-library dirs DEFINE the widgets — raw HTML with text is legal there.
    if (isWidget(rel)) continue;
    final src = stripComments(File(p.join(artifactDir, rel)).readAsStringSync());
    for (final m in _openingTagRe.allMatches(src)) {
      final tag = m.group(1)!;
      if (!_htmlElements.contains(tag)) continue; // TS generic, not HTML
      final attrs = m.group(2)!;
      final selfClosing = m.group(3) == '/';
      final hasIdentity =
          attrs.contains('data-el') || attrs.contains('inspectAttrs');
      final snippet = selfClosing ? null : _directTextSnippet(src, m.end);
      final line = _lineNumberAt(src, m.start);

      if (hasIdentity) {
        // Identity-carrying element with direct text in a non-text-bearing
        // role: the text is unreachable on inspect (resolves to the container,
        // never its own widget).
        if (snippet != null) {
          final roleMatch = RegExp(r'data-inspect-role\s*=\s*"([^"]*)"')
              .firstMatch(attrs);
          final role = roleMatch?.group(1);
          if (role != null && !_textBearingRoles.contains(role)) {
            findings.add(LintFinding(rel,
                'W7: raw text "${_snippet(snippet)}" in <$tag> at line $line — '
                'author via Label/Heading/Txt (or a text-bearing widget)'));
          }
        }
        continue;
      }

      // No identity at all.
      final interactive = _interactiveTags.contains(tag);
      if (!interactive && snippet == null) continue;

      if (interactive && snippet == null) {
        // Bare interactive element with no text.
        findings.add(LintFinding(rel,
            'W7: <$tag> bearing interaction at line $line — wrap this <$tag> in '
            'a library widget (Label/Heading/Txt/…) or spread inspectAttrs(...), '
            'or add a `data-el` attribute'));
      } else {
        // Text (with or without interaction) outside any text-bearing widget.
        findings.add(LintFinding(rel,
            'W7: raw text "${_snippet(snippet)}" in <$tag> at line $line — '
            'author via Label/Heading/Txt (or a text-bearing widget)'));
      }
    }
  }
  return findings;
}

// ══ entry point ═════════════════════════════════════════════════════════

/// Run W1–W7 over the design artifact at [artifactDir].
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
    ..._anonymousElementFindings(artifactDir),
  ];
}
