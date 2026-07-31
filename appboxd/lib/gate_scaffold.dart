// Scaffold gate — port of gates/scaffold/scaffold.sh (818 lines, bash + embedded
// Python) to pure Dart.
//
// The SHELL STRUCTURE gate: validates the self-contained shell pattern on a host
// app's lib/ui/views/ tree. Contract: lib/ui/views/.shell-structure.json
//   { "selfContained": ["train_shell"], "notes": "..." }
//
// Shells NOT listed in selfContained are skipped (incremental migration). Absent
// manifest or empty list → WARN + pass (no shell opted in yet; the gate never
// false-fails and never rubber-stamps).
//
// Checks, cheapest first (the exact bash order):
//   §6 fresh — design tree matches the frozen hash (hash-bound approval)
//   SN  — snackbars/ placement (app-level or shell-local, nowhere else)
//   S5  — *_facade.dart / *_repository.dart live under services/facades/ /
//         services/repositories/ (placement, not existence — runs with no manifest)
//   S8  — peer-service registration (a registered Kit* service's locator<Y>()
//         peers are also registered; setupKitSnackbars() called when used)
//   S10 — overlay ownership by enum reference (a sole-consumer overlay belongs
//         in its shell; consumers reference the generated enum, never an import)
//   S0  — manifest shape (parses; every named shell dir exists)
//   S1  — ≥ 1 *_view.dart with a matching *_viewmodel.dart
//   S4  — design-system.md carries a ## Palette / ## Tokens heading + kit color
//   S2  — locality (no relocated global-overlay leaks; no cross-shell view imports)
//   S6  — shell owns its widgets (shared/widgets/, <view>/widgets/, or *_chrome.dart)
//   S7  — no ScreenTypeLayout in shared widgets (adapt internals, don't swap layouts)
//   S9  — no form-factor variant cherry-picking another variant's components
//   S3  — overlay barrel integrity (<n>/<n>_sheet.dart, <n>/<n>_dialog.dart)

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gates.dart';

GateResult scaffoldGate(GateContext ctx) {
  final app = ctx.appRoot ?? ctx.repoRoot;
  final viewsDir = Directory('$app/lib/ui/views');
  final manifestPath = '${viewsDir.path}/.shell-structure.json';
  final manifest = File(manifestPath);
  final details = <String>[];
  var fails = 0;

  void ok(String m) => details.add('  ✓ $m');
  void warn(String m) => details.add('WARN: $m');
  void fail(String m) {
    details.add('FAIL: $m');
    ctx.sarif.result('scaffold', 'error', app, m);
    fails++;
  }

  GateResult passResult() => GateResult.ok('scaffold: PASS ($app)', details);
  GateResult failResult() => GateResult.fail('scaffold: $fails failure(s)', details);

  // ---- §6: design freshness (hash-bound approval), before any assertion ----
  // Fail-open for a legacy empty hash or a missing design dir (this gate is
  // app-only and runs fine on a host with no design tree).
  final moved = assertDesignFresh(ctx);
  if (moved != null) {
    details.add(moved);
    ctx.sarif.result(
        'scaffold', 'error', app, 'design moved after freeze (designHash mismatch, §6)');
    return GateResult.fail(
        'scaffold: design moved after freeze (designHash mismatch, §6)', details);
  }

  // ---- app-only: no views tree → nothing to check ----
  if (!viewsDir.existsSync()) {
    warn('no ${viewsDir.path} — nothing to check '
        '(shell structure gate is app-only)');
    return passResult();
  }

  // ---- package name (env exit if unreadable) ----
  final pkg = _readPackageName(app);
  if (pkg == null) {
    return GateResult.env('cannot read package name from $app/pubspec.yaml');
  }

  // ---- SN: snackbars/ placement (inverted from a blanket ban) ----
  // A snackbars/ dir is legal app-level (lib/ui/snackbars/) or shell-local
  // (lib/ui/views/<shell>/snackbars/), and nowhere else.
  var snBad = 0;
  for (final d in _findDirs(Directory('$app/lib/ui'), 'snackbars')) {
    final rel = _rel(d.path, app);
    if (rel == 'lib/ui/snackbars' ||
        RegExp(r'^lib/ui/views/[^/]+/snackbars$').hasMatch(rel)) {
      // legal home
    } else {
      fail('snackbars/ in an unsanctioned location (SN): $rel — legal homes are '
          'lib/ui/snackbars/ (shared app-wide) or '
          'lib/ui/views/<shell>/snackbars/ (shell-owned)');
      snBad++;
    }
  }
  if (snBad == 0) ok('snackbars/ dirs correctly placed or absent (SN)');

  // ---- S5: services placement — placement, not existence ----
  var s5Bad = 0;
  for (final f
      in _findFiles(Directory('$app/lib'), (f) => f.path.endsWith('_facade.dart'))) {
    if (f.path.contains('/services/facades/')) continue;
    fail('misplaced facade (S5): ${_rel(f.path, app)} — '
        '*_facade.dart must live under services/facades/');
    s5Bad++;
  }
  for (final f in _findFiles(
      Directory('$app/lib'), (f) => f.path.endsWith('_repository.dart'))) {
    if (f.path.contains('/services/repositories/')) continue;
    fail('misplaced repository (S5): ${_rel(f.path, app)} — '
        '*_repository.dart must live under services/repositories/');
    s5Bad++;
  }
  if (s5Bad == 0) {
    ok('services placement: facades/repositories correctly placed or absent (S5)');
  }

  // ---- S8: peer-service registration via the locator graph ----
  _runS8(app, ok, warn, fail);

  // ---- S10: overlay ownership by enum reference ----
  _runS10(app, ok, warn, fail);

  // ---- S0: manifest shape ----
  if (!manifest.existsSync()) {
    warn('no $manifestPath — no shell has opted into the '
        'self-contained pattern yet; gate is a no-op until the first migration');
    return fails > 0
        ? failResult()
        : GateResult.ok('scaffold: no manifest (WARN)', details);
  }

  final List<String> shells;
  try {
    final decoded = jsonDecode(manifest.readAsStringSync());
    final sc = (decoded is Map) ? decoded['selfContained'] : null;
    if (sc is! List || sc.any((e) => e is! String)) {
      fail('manifest $manifestPath: selfContained must be a list of strings (S0)');
      return failResult();
    }
    shells = sc.cast<String>();
  } catch (e) {
    fail('manifest $manifestPath: does not parse as JSON: $e (S0)');
    return failResult();
  }
  ok('manifest parses');

  if (shells.isEmpty) {
    warn('selfContained is empty — no shell has opted in yet; S1–S4 skipped '
        '(populate via Phase 2 migrations)');
    return fails > 0
        ? failResult()
        : GateResult.ok('scaffold: empty selfContained (WARN)', details);
  }

  // ---- per self-contained shell: S1, S4, S2, S6, S7, S9, S3 ----
  for (final s in shells) {
    final dir = Directory('${viewsDir.path}/$s');
    if (!dir.existsSync()) {
      fail("manifest names '$s' but ${dir.path} does not exist (S0)");
      continue;
    }

    // ---- S1: ≥ 1 view with a matching viewmodel ----
    final viewFiles = _findFiles(dir, (f) => f.path.endsWith('_view.dart'));
    if (viewFiles.isEmpty) {
      fail('$s: no *_view.dart found (S1: a shell needs ≥ 1 view)');
    } else {
      var paired = false;
      for (final v in viewFiles) {
        // v.path ends with '_view.dart' (10 chars) → swap for '_viewmodel.dart'
        final vmPath = '${v.path.substring(0, v.path.length - 10)}_viewmodel.dart';
        if (File(vmPath).existsSync()) {
          paired = true;
          break;
        }
      }
      if (paired) {
        ok('$s: view + matching viewmodel present (${viewFiles.length} view(s))');
      } else {
        fail('$s: no *_view.dart has a matching *_viewmodel.dart (S1)');
      }
    }

    // ---- S1/S4: design-system.md present and non-trivial ----
    final ds = File('${dir.path}/design-system.md');
    if (!ds.existsSync()) {
      fail('$s: design-system.md missing (S1)');
    } else {
      final dst = _readOrEmpty(ds);
      final hasHeading =
          RegExp(r'^##[ \t]+(Palette|Tokens)', multiLine: true).hasMatch(dst);
      final hasColor = RegExp(r'kc[A-Z][A-Za-z0-9]*|KitColors').hasMatch(dst);
      if (hasHeading && hasColor) {
        ok('$s: design-system.md carries the palette vocabulary');
      } else {
        fail("$s: design-system.md lacks a '## Palette' / '## Tokens' heading "
            'with a kit color reference (kc*/KitColors) (S4)');
      }
    }

    // ---- S2: locality — relocated global-overlay leaks ----
    // A global-overlay import is a violation ONLY when the imported overlay no
    // longer exists at the global path (it was relocated into a shell). Shared
    // overlays that STAY global resolve at lib/<rel> and are exempt.
    final overlayImportRe = RegExp(
        r"import[ \t]+'package:" + RegExp.escape(pkg) +
        r"/ui/(bottom_sheets|dialogs|snackbars)/([^']*)'");
    var foundLeak = false;
    var exempted = 0;
    for (final f in _findFiles(dir, (f) => f.path.endsWith('.dart'))) {
      final lines = _readOrEmpty(f).split('\n');
      for (var li = 0; li < lines.length; li++) {
        final m = overlayImportRe.firstMatch(lines[li]);
        if (m == null) continue;
        final rel = 'ui/${m.group(1)}/${m.group(2)}';
        if (File('$app/lib/$rel').existsSync()) {
          exempted++;
          continue; // overlay still lives globally → shared, unmoved → exempt
        }
        foundLeak = true;
        fail('$s: stale global-overlay import (S2) — overlay relocated, no longer '
            'at global path lib/$rel: ${_rel(f.path, app)}:${li + 1}:${lines[li]}');
      }
    }
    if (!foundLeak) {
      if (exempted > 0) {
        ok('$s: $exempted shared global-overlay import(s) exempt (still global), '
            'no relocated-overlay leaks');
      } else {
        ok('$s: no global overlay imports');
      }
    }

    // ---- S2: cross-shell view-tree imports (shared services/models are fine) ----
    // Overlay subdirs (bottom_sheets|dialogs|snackbars) are exempt — overlays are
    // shared app-wide; view trees stay shell-private.
    final viewsImportRe =
        RegExp(r"import[ \t]+'package:" + RegExp.escape(pkg) + r"/ui/views/");
    final ownShellRe = RegExp(
        r'package:' + RegExp.escape(pkg) + r'/ui/views/' + RegExp.escape(s) + r'/');
    final overlayAnyRe = RegExp(r'package:' +
        RegExp.escape(pkg) +
        r'/ui/views/[^/]+/(bottom_sheets|dialogs|snackbars)/');
    final ximpLines = <String>[];
    var hasXovl = false;
    for (final f in _findFiles(dir, (f) => f.path.endsWith('.dart'))) {
      final lines = _readOrEmpty(f).split('\n');
      for (var li = 0; li < lines.length; li++) {
        final line = lines[li];
        if (!viewsImportRe.hasMatch(line)) continue;
        if (ownShellRe.hasMatch(line)) continue; // own shell
        if (overlayAnyRe.hasMatch(line)) {
          hasXovl = true; // cross-shell overlay import — exempt
        } else {
          ximpLines.add('${_rel(f.path, app)}:${li + 1}:$line');
        }
      }
    }
    if (ximpLines.isNotEmpty) {
      for (final l in ximpLines) {
        fail('$s: cross-shell import (S2): $l');
      }
    } else if (hasXovl) {
      ok('$s: cross-shell overlay import(s) exempt (overlays shared app-wide), '
          'no cross-shell view imports');
    } else {
      ok('$s: no cross-shell imports');
    }

    // ---- S6: a shell owns its widgets ----
    // Legal homes: <shell>/shared/widgets/, <shell>/<view>/widgets/, or a
    // *_chrome.dart. A bare <shell>/widgets/ is rejected by review check 1o/D,
    // so it does NOT satisfy this check.
    final widgetDirs = <String>[];
    var nw = 0;
    void addWidgetDir(String wdir) {
      if (!Directory(wdir).existsSync()) return;
      if (widgetDirs.contains(wdir)) return; // shared/widgets is matched twice
      widgetDirs.add(wdir);
      nw += _findFiles(Directory(wdir), (f) => f.path.endsWith('.dart')).length;
    }

    addWidgetDir('${dir.path}/shared/widgets');
    for (final e in _listSorted(dir)) {
      if (e is Directory) addWidgetDir('${e.path}/widgets');
    }
    final chromeFiles = <String>[
      for (final e in _listSorted(dir))
        if (e is File && _basename(e.path).endsWith('_chrome.dart')) e.path,
    ];
    final chrome = chromeFiles.isEmpty ? null : chromeFiles.first;

    if (nw > 0 || chrome != null) {
      if (nw > 0 && chrome != null) {
        ok('$s: owns its widgets (S6) — widgets/: $nw file(s), ${_basename(chrome)}');
      } else if (nw > 0) {
        ok('$s: owns its widgets (S6) — widgets/: $nw file(s)');
      } else {
        ok('$s: owns its widgets (S6) — ${_basename(chrome!)}');
      }
    } else {
      fail('$s: no widgets/*.dart and no *_chrome.dart (S6) — a shell owns its '
          'widgets; legal homes are $s/shared/widgets/, $s/<view>/widgets/ or a '
          '*_chrome.dart (a bare $s/widgets/ is rejected by review check 1o/D)');
    }

    // ---- S7: no layout-swapping in shared widgets ----
    // A shared widget may adapt internals (getValueForScreenType /
    // ResponsiveBuilder) but must never SWAP layouts via ScreenTypeLayout.
    final s7Files = <String>[
      ...widgetDirs.expand(
          (wd) => _findFiles(Directory(wd), (f) => f.path.endsWith('.dart')).map((f) => f.path)),
      ...chromeFiles,
    ];
    final screenLayoutRe =
        RegExp(r'(^|[^A-Za-z0-9_])ScreenTypeLayout[ \t]*[.(]', multiLine: true);
    var s7Bad = false;
    for (final wf in s7Files) {
      if (screenLayoutRe.hasMatch(_readOrEmpty(File(wf)))) {
        fail('$s: ScreenTypeLayout in a shared widget (S7): ${_rel(wf, app)} — '
            'widgets adapt internals via getValueForScreenType/ResponsiveBuilder; '
            'whole-layout dispatch belongs to <surface>_view.dart');
        s7Bad = true;
      }
    }
    if (!s7Bad) ok('$s: no layout-swapping in shared widgets (S7)');

    // ---- S9: no variant-to-variant component imports ----
    // A form-factor variant is ONE layout, never a component library. Wholesale
    // delegation to the imported variant's own View class is allowed; cherry-
    // picking any OTHER symbol is the defect. The dispatcher (<surface>_view.dart)
    // importing its variants is required and exempt by construction.
    final variantFiles = _findFiles(dir, (f) {
      final n = _basename(f.path);
      return n.endsWith('_view.mobile.dart') ||
          n.endsWith('_view.tablet.dart') ||
          n.endsWith('_view.desktop.dart');
    });
    final variantImportRe =
        RegExp(r"""import[ \t]+'([^']*_view\.(mobile|tablet|desktop)\.dart)'""");
    final classDeclRe = RegExp(
        r'^(abstract[ \t]+)?class[ \t]+([A-Z][A-Za-z0-9_]*)', multiLine: true);
    var s9Bad = false;
    for (final vf in variantFiles) {
      final vfText = _readOrEmpty(vf);
      final vfLines = vfText.split('\n');
      // source with import lines stripped — only real code can "squat" a symbol
      final vfNoImports = vfLines
          .where((l) => !RegExp(r'^[ \t]*import[ \t]').hasMatch(l))
          .join('\n');
      for (final line in vfLines) {
        final m = variantImportRe.firstMatch(line);
        if (m == null) continue;
        final imp = m.group(1)!; // the imported path
        final target = File('${vf.parent.path}/${imp.split('/').last}');
        var annotation = '';
        if (target.existsSync()) {
          // which of the imported variant's OWN classes does the importer use?
          final classes = classDeclRe
              .allMatches(_readOrEmpty(target))
              .map((mm) => mm.group(2)!)
              .toList();
          final squatted = <String>[];
          for (final c in classes) {
            if (c.endsWith('ViewMobile') ||
                c.endsWith('ViewTablet') ||
                c.endsWith('ViewDesktop')) {
              continue; // its top-level View class — wholesale delegation
            }
            final refRe = RegExp(
                r'(^|[^A-Za-z0-9_])' + RegExp.escape(c) + r'([^A-Za-z0-9_]|$)',
                multiLine: true);
            if (refRe.hasMatch(vfNoImports)) squatted.add(c);
          }
          if (squatted.isEmpty) continue; // wholesale delegation — allowed
          annotation = ' (uses: ${squatted.join(' ')})';
        }
        fail('$s: form-factor variant imports another variant (S9): '
            '${_rel(vf.path, app)} -> ${m.group(0)}$annotation; move the shared '
            'component into widgets/ or *_chrome.dart — a '
            '*_view.{mobile,tablet,desktop}.dart is one layout, not a component '
            'library');
        s9Bad = true;
      }
    }
    if (!s9Bad) ok('$s: no variant-to-variant component imports (S9)');

    // ---- S3: overlay barrel integrity ----
    for (final kind in [('bottom_sheets', 'sheet'), ('dialogs', 'dialog')]) {
      final sub = kind.$1, suffix = kind.$2;
      final subDir = Directory('${dir.path}/$sub');
      if (!subDir.existsSync()) continue;
      for (final entry in _listSorted(subDir)) {
        if (entry is! Directory) continue;
        final n = _basename(entry.path);
        if (File('${entry.path}/${n}_$suffix.dart').existsSync()) {
          ok('$s: $sub/$n barrel present');
        } else {
          fail('$s: $sub/$n/ exists but ${n}_$suffix.dart is missing (S3 barrel)');
        }
      }
    }
  }

  if (fails > 0) return failResult();
  return passResult();
}

// ── S8: peer-service registration (port of the embedded Python) ──────────────

void _runS8(String app, void Function(String) ok, void Function(String) warn,
    void Function(String) fail) {
  final appDart = File('$app/lib/app/app.dart');
  if (!appDart.existsSync()) {
    ok('peer-service check N/A (no lib/app/app.dart)');
    return;
  }
  final appSrc = _readOrEmpty(appDart);
  final have = <String>{
    ..._captures(appSrc, RegExp(r'classType:\s*([A-Za-z0-9_]+)')),
    ..._captures(appSrc, RegExp(r'asType:\s*([A-Za-z0-9_]+)')),
  };

  final pcFile = File('$app/.dart_tool/package_config.json');
  if (!pcFile.existsSync()) {
    warn('no .dart_tool/package_config.json — run flutter pub get; S8 not verified');
    return;
  }
  List? pkgs;
  try {
    final decoded = jsonDecode(pcFile.readAsStringSync());
    pkgs = decoded is Map ? decoded['packages'] as List? : null;
  } catch (_) {
    pkgs = null;
  }
  if (pkgs == null) {
    warn('package_config unreadable — S8 not verified');
    return;
  }

  // class -> (file, text) index across kit packages (single pass).
  final index = <String, _Src>{};
  for (final p in pkgs.cast<Map<String, dynamic>>()) {
    final name = (p['name'] ?? '') as String;
    if (!name.startsWith('kit') && name != 'ui_library') continue;
    final kitRoot = _resolveRootUri((p['rootUri'] ?? '') as String, app);
    for (final f in _findFiles(
        Directory('$kitRoot/lib'), (f) => f.path.endsWith('.dart'))) {
      final t = _readOrEmpty(f);
      for (final cls in _captures(
          t, RegExp(r'^\s*class\s+([A-Z][A-Za-z0-9_]*)', multiLine: true))) {
        index.putIfAbsent(cls, () => _Src(f.path, t));
      }
    }
  }

  var bad = 0;
  for (final kt in have.where((t) => t.startsWith('Kit')).toList()..sort()) {
    final hit = index[kt];
    if (hit == null) continue;
    // read comment-free source: a locator<> inside a doc comment is not a peer edge
    final peers = _captures(_stripComments(hit.text),
            RegExp(r'locator<([A-Z][A-Za-z0-9_]*)>'))
        .toSet()
        .toList()
      ..sort();
    for (final peer in peers) {
      if (have.contains(peer) || peer == kt) continue;
      fail('$kt is registered but its peer $peer is not (S8) — $kt calls '
          'locator<$peer>(); add LazySingleton(classType: $peer) to @StackedApp '
          '[${_basename(hit.file)}]');
      bad++;
    }
  }

  // setupKitSnackbars(): the kit registers a SnackbarConfig per KitSnackbarType.
  // Asserting the CALL, not a main.dart template.
  if (have.contains('KitNotificationService')) {
    var called = false;
    for (final x in _findFiles(
        Directory('$app/lib'), (f) => f.path.endsWith('.dart'))) {
      if (_readOrEmpty(x).contains('setupKitSnackbars')) {
        called = true;
        break;
      }
    }
    if (!called) {
      fail('KitNotificationService is registered but setupKitSnackbars() is never '
          'called in lib/ (S8) — the KitSnackbarType SnackbarConfig variants stay '
          'unregistered, so severity/position render as bare defaults '
          '(showcase_app/lib/main.dart:26 is the reference call site)');
      bad++;
    }
  }

  if (bad == 0) ok('peer services registered for every Kit* service (S8)');
}

// ── S10: overlay ownership by enum reference (port of the embedded Python) ────

void _runS10(String app, void Function(String) ok, void Function(String) warn,
    void Function(String) fail) {
  const kinds = [
    ('bottomsheets', 'BottomSheetType', 'bottom_sheets'),
    ('dialogs', 'DialogType', 'dialogs'),
  ];
  final genExists =
      kinds.any((k) => File('$app/lib/app/app.${k.$1}.dart').existsSync());
  if (!genExists) {
    ok('overlay-ownership check N/A (no generated app.bottomsheets.dart / '
        'app.dialogs.dart — no overlays registered)');
    return;
  }

  // class -> file index over the app's lib/, read once.
  final libFiles =
      _findFiles(Directory('$app/lib'), (f) => f.path.endsWith('.dart'));
  final libTexts = <String, String>{};
  for (final f in libFiles) {
    libTexts[f.path] = _readOrEmpty(f);
  }
  final decl = <String, String>{};
  for (final f in libFiles) {
    for (final cls in _captures(
        libTexts[f.path]!, RegExp(r'^\s*class\s+([A-Z][A-Za-z0-9_]*)', multiLine: true))) {
      decl.putIfAbsent(cls, () => f.path);
    }
  }
  final shellRe = RegExp(r'/lib/ui/views/([^/]+)/');

  var bad = 0;
  var warned = false;
  for (final kind in kinds) {
    final key = kind.$1, enumName = kind.$2, dirname = kind.$3;
    final gfile = File('$app/lib/app/app.$key.dart');
    if (!gfile.existsSync()) continue;
    final gtext = _readOrEmpty(gfile);
    // Generated builder map: EnumType.member: (...) => ClassName(
    // The builder parameter list spans lines, so anchor on the member then look
    // ahead a bounded window for the `=> ClassName(`.
    final memberRe = RegExp(RegExp.escape(enumName) + r'\.([A-Za-z0-9_]+)\s*:');
    final arrowRe = RegExp(r'=>\s*([A-Z][A-Za-z0-9_]*)\s*\(');
    final pairs = <(String, String)>[];
    for (final m in memberRe.allMatches(gtext)) {
      // Python slice gtext[m.end():m.end()+300] silently clamps; Dart does not.
      final winEnd = m.end + 300;
      final win = gtext.substring(m.end, winEnd > gtext.length ? gtext.length : winEnd);
      final cm = arrowRe.firstMatch(win);
      if (cm != null) pairs.add((m.group(1)!, cm.group(1)!));
    }
    for (final (member, cls) in pairs) {
      final fpath = decl[cls];
      if (fpath == null) continue;
      final consumers = <String>{};
      for (final c in libFiles) {
        if (c.path == fpath) continue; // the overlay itself
        if (c.path.contains('/lib/app/')) continue; // the generated registry
        if (libTexts[c.path]!.contains('$enumName.$member')) {
          final m2 = shellRe.firstMatch(c.path);
          consumers.add(m2 != null ? m2.group(1)! : '<app-level>');
        }
      }
      final rel = _rel(fpath, app);
      final shells = consumers.where((c) => c != '<app-level>').toSet();
      if (consumers.isEmpty) {
        warn('$enumName.$member ($cls) is registered but no file references the '
            'variant — unconsumed overlay');
        warned = true;
      } else if (shells.length == 1 && !consumers.contains('<app-level>')) {
        final owner = shells.first;
        final want = 'lib/ui/views/$owner/$dirname/';
        if (!rel.startsWith(want)) {
          fail('$owner is the sole consumer of $enumName.$member but $cls lives '
              'at $rel (S10) — a sole-consumer overlay belongs in its shell: '
              'move it under $want');
          bad++;
        }
      } else if (shells.length >= 2) {
        final want = 'lib/ui/$dirname/';
        if (!rel.startsWith(want)) {
          final names = shells.toList()..sort();
          fail('$enumName.$member ($cls) is consumed by ${shells.length} shells '
              '(${names.join(', ')}) but lives at $rel (S10) — a genuinely shared '
              'overlay belongs app-level under $want');
          bad++;
        }
      }
    }
  }

  if (bad == 0 && !warned) ok('overlay ownership matches consumer scope (S10)');
}

// ── helpers ──────────────────────────────────────────────────────────────────

class _Src {
  final String file;
  final String text;
  _Src(this.file, this.text);
}

/// `${path#"$base/"}` — strip a base/ prefix, returning '.' for the base itself.
String _rel(String path, String base) {
  final prefix = base.endsWith('/') ? base : '$base/';
  if (path == base) return '.';
  if (path.startsWith(prefix)) return path.substring(prefix.length);
  return path;
}

String _basename(String path) => path.split('/').last;

/// Read a file as text, tolerating non-UTF-8 bytes (mirrors Python errors='ignore').
String _readOrEmpty(File f) {
  try {
    return utf8.decode(f.readAsBytesSync(), allowMalformed: true);
  } catch (_) {
    return '';
  }
}

/// All capture-group-1 matches of [re] in [s], nulls filtered out.
List<String> _captures(String s, RegExp re) =>
    re.allMatches(s).map((m) => m.group(1)).whereType<String>().toList();

/// First `name:` value in a pubspec.yaml, or null.
String? _readPackageName(String appDir) {
  final pubspec = File('$appDir/pubspec.yaml');
  if (!pubspec.existsSync()) return null;
  List<String> lines;
  try {
    lines = pubspec.readAsLinesSync();
  } catch (_) {
    return null;
  }
  final re = RegExp(r'^name:[ \t]*(.*)$');
  for (final line in lines) {
    final m = re.firstMatch(line);
    if (m != null) return m.group(1)!.trim();
  }
  return null;
}

/// Recursive .dart-file walk skipping dot-directories, sorted for determinism.
List<File> _findFiles(Directory dir, bool Function(File) where) {
  final out = <File>[];
  void walk(Directory d) {
    if (!d.existsSync()) return;
    for (final entry in d.listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (entry is Directory) {
        if (_basename(entry.path).startsWith('.')) continue;
        walk(entry);
      } else if (entry is File && where(entry)) {
        out.add(entry);
      }
    }
  }

  walk(dir);
  return out;
}

/// Recursive walk for directories named [name], skipping dot-directories.
List<Directory> _findDirs(Directory dir, String name) {
  final out = <Directory>[];
  void walk(Directory d) {
    if (!d.existsSync()) return;
    for (final entry in d.listSync()..sort((a, b) => a.path.compareTo(b.path))) {
      if (entry is Directory) {
        final n = _basename(entry.path);
        if (n.startsWith('.')) continue;
        if (n == name) out.add(entry);
        walk(entry);
      }
    }
  }

  walk(dir);
  return out;
}

/// Sorted direct children of a directory (empty if missing).
List<FileSystemEntity> _listSorted(Directory d) {
  if (!d.existsSync()) return const [];
  return d.listSync()..sort((a, b) => a.path.compareTo(b.path));
}

/// `os.path.normpath`-ish: collapse '.' and '..' segments.
String _normalize(String path) {
  final isAbs = path.startsWith('/');
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else if (!isAbs) {
        out.add('..');
      }
    } else {
      out.add(part);
    }
  }
  final result = out.join('/');
  return isAbs ? '/$result' : (result.isEmpty ? '.' : result);
}

/// Resolve a package_config rootUri to a filesystem root, mirroring the Python:
///   raw = urlparse(rootUri).path
///   root = raw if isabs(raw) else normpath(join(app, '.dart_tool', raw))
String _resolveRootUri(String rootUri, String appDir) {
  String path;
  try {
    final uri = Uri.parse(rootUri);
    path = uri.path.isEmpty ? rootUri : uri.path;
  } catch (_) {
    path = rootUri;
  }
  if (path.startsWith('/')) return path; // absolute
  return _normalize('$appDir/.dart_tool/$path'); // relative to .dart_tool
}

/// Blank Dart comment CONTENT, preserve newlines and code. S8 is a pure selector
/// (does this class resolve `locator<X>()`?) so it must read comment-free source — a
/// kit doc-comment showing example usage must not read as a real peer edge. Port
/// of the embedded Python strip_comments() (handles strings, //, and nested /* */).
String _stripComments(String src) {
  const q3d = '"""';
  const q3s = "'''";
  final out = StringBuffer();
  var i = 0;
  final n = src.length;
  while (i < n) {
    final c = src[i];
    if (c == '"' || c == "'") {
      final triple = i + 3 <= n ? src.substring(i, i + 3) : '';
      final q = (triple == q3d || triple == q3s) ? triple : c;
      out.write(src.substring(i, i + q.length));
      i += q.length;
      while (i < n) {
        if (src[i] == '\\' && q.length == 1) {
          out.write(src.substring(i, i + 2 > n ? n : i + 2));
          i += 2;
          continue;
        }
        if (src.startsWith(q, i)) {
          out.write(q);
          i += q.length;
          break;
        }
        out.write(src[i]);
        i += 1;
      }
      continue;
    }
    if (src.startsWith('//', i)) {
      while (i < n && src[i] != '\n') {
        i += 1;
      }
      continue;
    }
    if (src.startsWith('/*', i)) {
      var depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (src.startsWith('/*', i)) {
          depth += 1;
          i += 2;
        } else if (src.startsWith('*/', i)) {
          depth -= 1;
          i += 2;
        } else {
          if (src[i] == '\n') out.write('\n'); // preserve line numbers
          i += 1;
        }
      }
      continue;
    }
    out.write(c);
    i += 1;
  }
  return out.toString();
}
