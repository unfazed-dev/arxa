/// The S-gate: the style placement law, enforced against ANY design artifact
/// tree (nothing here is studio-specific). Companion to the W-gate: widgets
/// live at the narrowest scope covering their consumers; so do stylesheets.
///
/// Three tiers:
///   app tier    — `assets/css/*.css`: tokens, fonts, theme, and rules whose
///                 classes are consumed by ≥2 shells or by shell-independent
///                 code (ui/common).
///   shell tier  — `ui/views/<shell>/*.css`: rules consumed only inside that
///                 shell, linked by that shell's own view (headExtra), never
///                 by base.tsx.
///   view tier   — deeper colocation is legal; the same leak rule applies.
///
/// Four hard-fail rules; every failure names the concrete fix:
///
///   S1  demotion — a linked app-tier stylesheet whose every consumed class
///       resolves to exactly one shell must move into that shell's dir.
///   S2  leak — a shell-tier stylesheet with a class consumed outside its
///       shell (another shell, or shell-independent ui/common) must be
///       promoted back to `assets/css/`.
///   S3  link locality — a shell-tier stylesheet is linked from inside its
///       own shell dir (the shell view's headExtra), not from ui/common.
///   S4  dangling link — every `<link href="…​.css">` resolves to a file.
///
/// Consumption is measured the honest, checkable way: a class is "used by" a
/// template/viewmodel file when the class token appears inside a quoted
/// string in that file. A file's scope is the registered shell dir that
/// contains it; unregistered dirs under ui/views (v1-port mounts such as
/// main_shell/) resolve to the registered shells that transitively import
/// them; ui/common and everything outside ui/views is shell-independent.
/// Dead classes (no consumer anywhere) never decide placement — they are
/// reported on the advisory notes channel, like D9.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'design_tools.dart' show LintFinding;

class _Ctx {
  final String artifactDir;
  final String hub;
  final List<String> registered; // hub + shells
  final Map<String, String> sources = {}; // rel path -> content, tsx/js
  final Map<String, Set<String>> quoted = {}; // rel path -> quoted tokens
  final Map<String, Set<String>> importers = {}; // rel -> rel importers
  final Map<String, Set<String>> _ownerMemo = {};
  _Ctx(this.artifactDir, this.hub, this.registered);

  /// Registered-shell dir name containing [rel], or null.
  String? _rawShell(String rel) {
    final segs = p.split(rel);
    final i = segs.indexOf('views');
    if (i < 0 || i + 1 >= segs.length || segs[0] != 'ui') return null;
    return segs[i + 1];
  }

  /// Scopes a source file styles for: {shell...}, {'common'}, or {} (orphan).
  Set<String> owners(String rel, [Set<String>? seen]) {
    final memo = _ownerMemo[rel];
    if (memo != null) return memo;
    seen ??= <String>{};
    if (!seen.add(rel)) return {};
    final raw = _rawShell(rel);
    Set<String> out;
    if (raw == null) {
      out = {'common'};
    } else if (registered.contains(raw)) {
      out = {raw};
    } else {
      out = {};
      for (final q in importers[rel] ?? const <String>{}) {
        out.addAll(owners(q, seen));
      }
    }
    if (seen.length == 1) _ownerMemo[rel] = out;
    return out;
  }

  /// Union of scopes of every file whose quoted strings mention [cls].
  Set<String> classScope(String cls) {
    final out = <String>{};
    for (final e in quoted.entries) {
      if (e.value.contains(cls)) out.addAll(owners(e.key));
    }
    return out;
  }
}

final _importRe = RegExp(r"from\s+'(\.[^']+)'");
final _quotedRe = RegExp('''["'`]([^"'`\n]{0,300})["'`]''');
final _wordRe = RegExp(r'[\w-]+');
final _classRe = RegExp(r'\.([a-zA-Z][\w-]*)');
final _selectorRe = RegExp(r'([^{}]+)\{');
final _linkRe = RegExp(r'<link[^>]*href="([^"]+\.css)"');

_Ctx? _load(String artifactDir) {
  final regFile = File(p.join(artifactDir, 'ui', 'views', '.shell-structure.json'));
  if (!regFile.existsSync()) return null;
  final reg = jsonDecode(regFile.readAsStringSync()) as Map<String, dynamic>;
  final hub = reg['hub'] as String;
  final ctx = _Ctx(artifactDir, hub,
      [hub, ...(reg['shells'] as List).cast<String>()]);
  final uiDir = Directory(p.join(artifactDir, 'ui'));
  if (!uiDir.existsSync()) return null;
  for (final f in uiDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.tsx') && !f.path.endsWith('.js')) continue;
    final rel = p.relative(f.path, from: artifactDir);
    final src = f.readAsStringSync();
    ctx.sources[rel] = src;
    ctx.quoted[rel] = _quotedRe
        .allMatches(src)
        .expand((m) => _wordRe.allMatches(m.group(1)!).map((w) => w.group(0)!))
        .toSet();
  }
  for (final e in ctx.sources.entries) {
    for (final m in _importRe.allMatches(e.value)) {
      final target = p.normalize(
          p.join(p.dirname(e.key), m.group(1)!));
      ctx.importers.putIfAbsent(target, () => <String>{}).add(e.key);
    }
  }
  return ctx;
}

Set<String> _cssClasses(String css) {
  final stripped = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return _selectorRe
      .allMatches(stripped)
      .expand((m) => _classRe.allMatches(m.group(1)!).map((c) => c.group(1)!))
      .toSet();
}

/// Run S1–S4 over [artifactDir]. Hard failures return; advisory findings
/// (dormant/dead stylesheets, dead-class counts) go to [notes] and never
/// affect the exit code. An artifact without a shell registry has no shells
/// to place against, so the gate passes vacuously.
List<LintFinding> gateDesignStyles(String artifactDir,
    {List<LintFinding>? notes}) {
  final findings = <LintFinding>[];
  final ctx = _load(artifactDir);
  if (ctx == null) return findings;

  // Every stylesheet in the tree, keyed by artifact-relative path.
  final cssFiles = <String>[];
  for (final root in ['assets', 'ui']) {
    final d = Directory(p.join(artifactDir, root));
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.css')) {
        cssFiles.add(p.relative(f.path, from: artifactDir));
      }
    }
  }

  // Who links what, from where.
  final linkedBy = <String, Set<String>>{}; // css rel -> linker rels
  for (final e in ctx.sources.entries) {
    for (final m in _linkRe.allMatches(e.value)) {
      final href = m.group(1)!;
      final rel = href.startsWith('/') ? href.substring(1) : href;
      linkedBy.putIfAbsent(rel, () => <String>{}).add(e.key);
      // S4 — dangling link.
      if (!File(p.join(artifactDir, rel)).existsSync()) {
        findings.add(LintFinding(p.join(artifactDir, e.key),
            'S4 dangling link: href="$href" resolves to no file — fix the '
            'href or restore the stylesheet'));
      }
    }
  }

  for (final rel in cssFiles) {
    final abs = p.join(artifactDir, rel);
    final classes = _cssClasses(File(abs).readAsStringSync());
    final used = <String, Set<String>>{}; // class -> scopes
    var dead = 0;
    for (final c in classes) {
      final sc = ctx.classScope(c);
      if (sc.isEmpty) {
        dead++;
      } else {
        used[c] = sc;
      }
    }
    final union = used.values.expand((s) => s).toSet();
    final isAppTier = p.split(rel).first == 'assets';
    final shell = () {
      final segs = p.split(rel);
      final i = segs.indexOf('views');
      return (segs.first == 'ui' && i >= 0 && i + 1 < segs.length)
          ? segs[i + 1]
          : null;
    }();
    final linked = linkedBy.containsKey(rel);

    if (isAppTier) {
      if (!linked) {
        notes?.add(LintFinding(abs,
            'dormant stylesheet: linked by no view (v1 import awaiting its '
            'shell) — ${classes.length} classes'));
      } else if (union.length == 1 && !union.contains('common')) {
        // S1 — single-shell app-tier file must demote.
        findings.add(LintFinding(abs,
            'S1 demotion: every consumed class (${used.length}) is used only '
            'by ${union.first} — move this file to ui/views/${union.first}/ '
            'and link it from that shell view\'s headExtra'));
      } else if (linked && used.isEmpty && classes.isNotEmpty) {
        notes?.add(LintFinding(abs,
            'linked but dead: none of its ${classes.length} classes are '
            'consumed by any view — deletion candidate'));
      }
    } else if (shell != null && ctx.registered.contains(shell)) {
      // S2 — leaks out of the shell.
      final leaks = used.entries
          .where((e) => e.value.any((s) => s != shell))
          .map((e) => e.key)
          .toList()
        ..sort();
      if (leaks.isNotEmpty) {
        findings.add(LintFinding(abs,
            'S2 leak: class${leaks.length == 1 ? '' : 'es'} '
            '${leaks.join(', ')} consumed outside $shell — promote the rule'
            '${leaks.length == 1 ? '' : 's'} to assets/css/'));
      }
      // S3 — link locality.
      final linkers = linkedBy[rel] ?? const <String>{};
      final local = linkers.any((l) =>
          p.isWithin(p.join('ui', 'views', shell), l) ||
          p.dirname(l) == p.join('ui', 'views', shell));
      if (linkers.isEmpty) {
        findings.add(LintFinding(abs,
            'S3 link locality: shell stylesheet linked by no view — link it '
            'from $shell\'s shell view headExtra or delete it'));
      } else if (!local) {
        findings.add(LintFinding(abs,
            'S3 link locality: linked only from outside $shell '
            '(${linkers.join(', ')}) — the shell view owns its stylesheet '
            'links; move the <link> into $shell\'s headExtra'));
      }
    }
    if (dead > 0 && linked) {
      notes?.add(LintFinding(
          abs, 'dead classes: $dead of ${classes.length} have no consumer'));
    }
  }
  findings.sort((a, b) => a.toString().compareTo(b.toString()));
  return findings;
}
