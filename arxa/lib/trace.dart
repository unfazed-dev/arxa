// trace.dart — the design↔view↔viewmodel↔route traceability manifest + guard.
//
// Dart port of trace.py. Cross-references the design decomposition (breakdown.json:
// pages→components→primitives) against the EMITTED Flutter code (target's
// `*_view.dart`, `*_viewmodel.dart`, `app.router.dart`) and emits one manifest.
//
// THE GUARD (why it exists): a template-STRING unit test passed falsely on the
// router (it asserted the TEMPLATE contained `initial: true`, which it did — but
// the MATERIALIZED `app.router.dart` had drifted to `homeShellView = '/'`). A trace
// row reads the REAL emitted files, so a screen whose route is absent from the
// generated router, or whose view has no VM, is flagged here — not on a string
// that can lie.
//
// Trace proves the generated layer matches DESIGN; the gen_freshness gate proves
// the generated layer matches source.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// ── data classes (the manifest shape) ─────────────────────────────────────────

/// One screen's traceability row — pins a design screen to its emitted view,
/// viewmodel, route, guard, design-origin, and the primitives it renders.
class TraceScreen {
  final String id;
  final String viewClass; // the emitted View class: <Pascal(id)>View
  final String? designName; // the (possibly inconsistent) breakdown `name`
  final String? route; // route path from the generated router (null if absent)
  final String routeConst; // the router const name (camelCase View)
  final String routedVia; // 'route' or 'shellTab' (primary-nav tab via shell)
  final bool initial; // is this route the router's initial ('/')?
  final Map<String, dynamic>? guard; // from breakdown (runtime guard)
  final String? designSourceRef; // the breakdown's DOM pin
  final String? viewFile; // lib/presentation/<id>_view.dart (null if not emitted)
  final String? viewmodelFile; // lib/presentation/<id>_viewmodel.dart (null if none)
  final String? viewmodelClass;
  final List<String> primitives; // from breakdown components→primitives
  final List<String> dataDeps; // locator<...> deps captured from the VM

  TraceScreen({
    required this.id,
    required this.viewClass,
    required this.designName,
    required this.route,
    required this.routeConst,
    required this.routedVia,
    required this.initial,
    required this.guard,
    required this.designSourceRef,
    required this.viewFile,
    required this.viewmodelFile,
    required this.viewmodelClass,
    required this.primitives,
    required this.dataDeps,
  });

  /// JSON shape matches the Python `row` dict (snake_case keys).
  Map<String, dynamic> toJson() => {
        'id': id,
        'view_class': viewClass,
        'design_name': designName,
        'route': route,
        'route_const': routeConst,
        'routed_via': routedVia,
        'initial': initial,
        'guard': guard,
        'design_source_ref': designSourceRef,
        'view_file': viewFile,
        'viewmodel_file': viewmodelFile,
        'viewmodel_class': viewmodelClass,
        'primitives': primitives,
        'data_deps': dataDeps,
      };
}

/// The full manifest: screens keyed by id, plus primary-nav and meta.
class TraceManifest {
  final Map<String, TraceScreen> screens;
  final Map<String, dynamic> primaryNav;
  final Map<String, dynamic> meta;

  TraceManifest({
    required this.screens,
    required this.primaryNav,
    required this.meta,
  });

  Map<String, dynamic> toJson() => {
        'screens': {for (final e in screens.entries) e.key: e.value.toJson()},
        'primary_nav': primaryNav,
        'meta': meta,
      };
}

/// Result of the guard: every design screen must be fully traced.
class TraceCheckResult {
  final bool passed;
  final List<String> issues;
  final List<String> initials; // screen ids whose route is the initial ('/')

  TraceCheckResult({
    required this.passed,
    required this.issues,
    required this.initials,
  });
}

// ── emitted-code parsing (the MATERIALIZED layer — what the string-test missed) ─

// `class SigninView extends StackedView<SigninViewModel>` → view name + its VM.
final _viewVmRe = RegExp(r'class\s+(\w+)\s+extends\s+StackedView<(\w+)>');

// `class SigninViewModel extends BaseViewModel` (or *ViewModel) — the VM's own decl.
final _vmClassRe = RegExp(r'class\s+(\w+)\s+extends\s+\w*ViewModel');

// `locator<SessionRepository>()` / `locator<SupabaseAuthService>()` — data deps.
final _locatorRe = RegExp(r'locator<(\w+)>');

// `static const signinView = '/signin-view';` and `static const splashView = '/';`.
final _routeConstRe = RegExp(r"static const (\w+)\s*=\s*'(/[^']*)'");

// The route-name → View mapping in the generated router: `_i3.SigninView: (data)`.
// Ported for parity with trace.py; not referenced by the current derive logic.
// ignore: unused_element
final _routeFactoryRe =
    RegExp(r'_(?:i\d+\.)?(\w+View|HomeShellView):\s*\(data\)');

String _read(File f) {
  try {
    return f.readAsStringSync();
  } catch (_) {
    return '';
  }
}

class _ViewScan {
  final String file;
  final String viewmodelClass;
  _ViewScan({required this.file, required this.viewmodelClass});
}

class _VmScan {
  final String file;
  final List<String> dataDeps;
  _VmScan({required this.file, required this.dataDeps});
}

class _PageAgg {
  final Map<String, dynamic> page;
  final Set<String> prims;
  _PageAgg({required this.page, required this.prims});
}

/// `{ViewName: {file, viewmodel_class}}` from the emitted `*_view.dart` files.
/// Reads the MATERIALIZED view, so a missing VM is a real gap, not a template
/// assumption.
Map<String, _ViewScan> _scanViews(Directory presDir) {
  final out = <String, _ViewScan>{};
  if (!presDir.existsSync()) return out;
  final names = presDir.listSync().whereType<File>().map((f) => p.basename(f.path)).toList()
    ..sort();
  for (final name in names) {
    if (!name.endsWith('_view.dart')) continue;
    final src = _read(File(p.join(presDir.path, name)));
    final m = _viewVmRe.firstMatch(src);
    if (m == null) continue; // a view not bound via StackedView (e.g. HomeShellView)
    out[m.group(1)!] = _ViewScan(
      file: 'lib/presentation/$name',
      viewmodelClass: m.group(2)!,
    );
  }
  return out;
}

/// `{ViewModelName: {file, data_deps}}` — the `locator<...>` deps the VM pulls
/// (repositories + services), parsed from the materialized VM.
Map<String, _VmScan> _scanViewmodels(Directory presDir) {
  final out = <String, _VmScan>{};
  if (!presDir.existsSync()) return out;
  final names = presDir.listSync().whereType<File>().map((f) => p.basename(f.path)).toList()
    ..sort();
  for (final name in names) {
    final isVm = name.endsWith('_viewmodel.dart');
    final isGen = name.endsWith('_viewmodel.gen.dart');
    if (!isVm && !isGen) continue;
    // prefer the hand-editable *_viewmodel.dart (where locator deps live) over a
    // generated *_viewmodel.gen.dart sibling — skip the .gen if a hand-editable exists.
    if (isGen) {
      final hand = name.substring(0, name.length - '.gen.dart'.length);
      if (File(p.join(presDir.path, hand)).existsSync()) continue;
    }
    final src = _read(File(p.join(presDir.path, name)));
    final m = _vmClassRe.firstMatch(src);
    if (m == null) continue;
    final deps = _locatorRe.allMatches(src).map((mm) => mm.group(1)!).toSet().toList()..sort();
    out[m.group(1)!] = _VmScan(file: 'lib/presentation/$name', dataDeps: deps);
  }
  return out;
}

/// `{routeConstName: routePath}` + the initial-route const name (the one whose
/// path is '/'). Reads the GENERATED `app.router.dart` — so a route ABSENT here
/// (the drift) is detected, and the initial route is identified from the
/// materialized artifact, not the `@StackedApp` source.
(Map<String, String>, String?) _scanRouter(File appRouterPath) {
  final src = _read(appRouterPath);
  final consts = <String, String>{};
  for (final m in _routeConstRe.allMatches(src)) {
    consts[m.group(1)!] = m.group(2)!;
  }
  String? initial;
  for (final entry in consts.entries) {
    if (entry.value == '/') initial = entry.key;
  }
  return (consts, initial);
}

/// The breakdown decomposition: `pages[]` + `primaryNav` + `meta`. The DESIGN
/// side the trace row pins each screen to.
({List<Map<String, dynamic>> pages, Map<String, dynamic> primaryNav, Map<String, dynamic> meta})
_breakdown(String breakdownPath) {
  try {
    final data = jsonDecode(File(breakdownPath).readAsStringSync());
    if (data is! Map<String, dynamic>) {
      return (pages: const [], primaryNav: const {}, meta: const {});
    }
    final pages = (data['pages'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final pn = (data['primaryNav'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final meta = (data['meta'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return (pages: pages, primaryNav: pn, meta: meta);
  } catch (_) {
    return (pages: const [], primaryNav: const {}, meta: const {});
  }
}

/// Flatten a breakdown page's components→primitives into a sorted id list.
List<String> _pagePrimitives(Map<String, dynamic> page) {
  final prims = <String>{};
  for (final c in (page['components'] as List? ?? const [])) {
    if (c is! Map<String, dynamic>) continue;
    for (final prim in (c['primitives'] as List? ?? const [])) {
      if (prim is Map<String, dynamic>) {
        final pid = prim['id'];
        if (pid is String && pid.isNotEmpty) prims.add(pid);
      }
    }
  }
  return prims.toList()..sort();
}

/// The deterministic emitted View class for a screen id: PascalCase + 'View'.
/// home→HomeView, signin→SigninView. The breakdown `name` is INCONSISTENT, so the
/// screen ID — not the name — is the stable key. We resolve against the EMITTED
/// files, so a mismatch (design name ≠ emitted class) is a real signal.
String _viewClassFor(String sid) {
  if (sid.isEmpty) return 'View';
  return '${sid[0].toUpperCase()}${sid.substring(1)}View';
}

/// Stacked's generated route-const name: PascalCase View → camelCase.
/// SignInView → signinView, HomeShellView → homeShellView, HomeView → homeView.
String _routeConstFor(String viewClass) {
  if (viewClass.isEmpty) return viewClass;
  return '${viewClass[0].toLowerCase()}${viewClass.substring(1)}';
}

// ── derive: build the manifest by cross-referencing design vs emitted code ─────

/// Build the trace manifest. [breakdownPath] defaults to `<targetDir>/../breakdown.json`
/// (the `.blueprint` layout).
TraceManifest derive(String targetDir, {String? breakdownPath}) {
  final presDir = Directory(p.join(targetDir, 'lib', 'presentation'));
  breakdownPath ??= p.normalize(p.join(targetDir, '..', 'breakdown.json'));
  final bd = _breakdown(breakdownPath);

  final views = _scanViews(presDir);
  final vms = _scanViewmodels(presDir);
  final (routerConsts, initialConst) =
      _scanRouter(File(p.join(targetDir, 'lib', 'app', 'app.router.dart')));

  // collapse duplicate-id pages (e.g. detail has 3 component variants — one screen):
  // the FIRST page per id wins; primitives merge across the variants.
  final byId = <String, _PageAgg>{};
  for (final page in bd.pages) {
    final sid = page['id'];
    if (sid is! String || sid.isEmpty) continue;
    final agg = byId.putIfAbsent(sid, () => _PageAgg(page: page, prims: <String>{}));
    for (final prim in _pagePrimitives(page)) {
      agg.prims.add(prim);
    }
  }

  // primary-nav tab ids are reached via the shell (HomeShellView's tab children),
  // NOT as top-level MaterialRoutes — so "no route const" is CORRECT for them.
  final tabs = (bd.primaryNav['tabs'] as List? ?? const []);
  final tabIds = <String>{
    for (final t in tabs)
      if (t is Map<String, dynamic> && t['id'] is String) t['id'] as String,
  };

  final screens = <String, TraceScreen>{};
  for (final entry in byId.entries) {
    final sid = entry.key;
    final agg = entry.value;
    final page = agg.page;
    final viewClass = _viewClassFor(sid);
    var routeConst = _routeConstFor(viewClass);
    String? routePath = routerConsts[routeConst];
    // fall back to a case-insensitive const match if the exact name missed.
    if (routePath == null) {
      for (final rc in routerConsts.entries) {
        if (rc.key.toLowerCase() == routeConst.toLowerCase()) {
          routePath = rc.value;
          routeConst = rc.key;
          break;
        }
      }
    }
    final view = views[viewClass];
    final vmName = view?.viewmodelClass;
    final vm = (vmName == null) ? null : vms[vmName];
    final isTab = tabIds.contains(sid);
    screens[sid] = TraceScreen(
      id: sid,
      viewClass: viewClass,
      designName: page['name'] as String?,
      route: routePath,
      routeConst: routeConst,
      routedVia: (isTab && routePath == null) ? 'shellTab' : 'route',
      initial: initialConst != null && routeConst == initialConst,
      guard: page['guard'] as Map<String, dynamic>?,
      designSourceRef: page['sourceRef'] as String?,
      viewFile: view?.file,
      viewmodelFile: vm?.file,
      viewmodelClass: vmName,
      primitives: agg.prims.toList()..sort(),
      dataDeps: vm?.dataDeps ?? const [],
    );
  }

  return TraceManifest(
    screens: screens,
    primaryNav: bd.primaryNav,
    meta: {'app': bd.meta['appName'], 'screens_n': screens.length},
  );
}

// ── the guard: every design screen must be FULLY traced (no gap) ──────────────

/// A screen is COMPLETE iff it has a view_file, a viewmodel_file, and a route.
/// This is the gate that replaces the false template-string router test: it reads
/// the MATERIALIZED files.
TraceCheckResult check(TraceManifest manifest) {
  final issues = <String>[];
  final sorted = manifest.screens.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final e in sorted) {
    final sid = e.key;
    final row = e.value;
    if (row.viewFile == null) {
      issues.add("'$sid': no emitted view file (design screen not generated)");
    }
    if (row.viewmodelFile == null) {
      issues.add("'$sid': view ${row.viewClass} has no viewmodel");
    }
    // a route is required UNLESS the screen is a primary-nav tab (reached via the
    // shell's tab children, not a top-level MaterialRoute).
    if (row.route == null && row.routedVia != 'shellTab') {
      issues.add("'$sid': route absent from generated app.router.dart "
          '(stale router? run dart run build_runner build)');
    }
  }
  final initials = manifest.screens.entries
      .where((e) => e.value.initial)
      .map((e) => e.key)
      .toList();
  if (initials.isEmpty) {
    issues.add("no initial route ('/') in the generated router — app boots to "
        "Flutter's default, skipping startup");
  } else if (initials.length > 1) {
    issues.add('multiple initial routes: $initials — Stacked allows only one');
  }
  return TraceCheckResult(passed: issues.isEmpty, issues: issues, initials: initials);
}
