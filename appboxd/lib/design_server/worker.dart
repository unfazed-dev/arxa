// The CDP worker bridge for the Dart design server.
//
// Design artifacts (app.routes.js, *_viewmodel.js, Nunjucks views) are authored
// ES modules — porting them to Dart is out of scope. So the Dart server
// executes that JS in a headless-Chrome tab driven over CDP. Dart owns HTTP,
// routing, sessions, prefs, timers, hot reload; the worker tab owns viewmodel
// dispatch + Nunjucks rendering + l10n.
//
// The one Node builtin the artifact graph touches is `node:fs` (in the
// fixture_reader seam). The worker page's import map remaps it to fs_shim.js,
// which reads from a Dart-prefetched fixture map (sync — no async I/O on the
// render path). Templates + l10n + icons are likewise prefetched into in-memory
// maps before boot. Spike-verified (tool/_worker_spike.dart).
//
// kimitail: node:fs shim covers the documented fixture seam only. If an
// artifact ever imports another Node builtin (node:path, node:crypto, …), add
// the shim to fs_shim.js + the import map; the ceiling is "artifacts use only
// node:fs", which the appbox-designer architecture fixes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/design_server/l10n.dart' show parseArb;
import 'package:path/path.dart' as p;

/// One dispatched request's outcome, plus the per-request state the worker
/// hands back so Dart can persist sessions/timers/locale across reloads.
class WorkerResponse {
  final int status;
  final Map<String, String> headers;
  final String? body;
  final List<String> setCookies;
  final Map<String, dynamic>? session;
  final Map<String, dynamic> timers;
  final String locale;
  WorkerResponse({
    required this.status,
    required this.headers,
    required this.body,
    required this.setCookies,
    required this.session,
    required this.timers,
    required this.locale,
  });

  factory WorkerResponse.fromJson(Map<String, dynamic> m) => WorkerResponse(
        status: m['status'] as int? ?? 200,
        headers: (m['headers'] as Map?)?.cast<String, String>() ?? {},
        body: m['body'] as String?,
        setCookies: ((m['setCookies'] as List?) ?? []).cast<String>(),
        session: m['session'] as Map<String, dynamic>?,
        timers: (m['timers'] as Map?)?.cast<String, dynamic>() ?? {},
        locale: m['locale'] as String? ?? 'en',
      );
}

/// The in-memory prefetch the worker renders from. Built by scanning the
/// artifact dir; refreshed on hot reload. Sync lookups only on the render path.
class _Prefetch {
  final Map<String, String> templates;
  final Map<String, String> fixtures; // keyed by absolute served URL
  final Map<String, Map<String, dynamic>> arb;
  final Map<String, String> icons;
  _Prefetch(this.templates, this.fixtures, this.arb, this.icons);
}

_Prefetch _scanArtifact(String artifactDir, String origin, String? iconsDir,
    {String? projectDir}) {
  final templates = <String, String>{};
  final fixtures = <String, String>{};
  final arb = <String, Map<String, dynamic>>{};
  final iconNames = <String>{};

  String posixRel(String f) =>
      p.relative(f, from: artifactDir).split(p.separator).join('/');

  void iconScan(String src) {
    for (final m
        in RegExp(r"""icon['"]?\s*[:\(]\s*['"]([a-z0-9-]+)['"]""").allMatches(src)) {
      iconNames.add(m.group(1)!);
    }
  }

  for (final f in _walk(Directory(artifactDir))) {
    final rel = posixRel(f.path);
    if (rel.endsWith('.html') || rel.endsWith('.js')) {
      final src = f.readAsStringSync();
      if (rel.endsWith('.html')) templates[rel] = src;
      iconScan(src);
    }
    if (RegExp(r'^models/.*\.json$').hasMatch(rel)) {
      fixtures['$origin/$rel'] = f.readAsStringSync();
    }
  }
  void scanArbDir(Directory l10nDir) {
    if (!l10nDir.existsSync()) return;
    for (final f in l10nDir.listSync().whereType<File>()) {
      final m = RegExp(r'app_(.+)\.arb$').firstMatch(p.basename(f.path));
      if (m == null) continue;
      final entries = parseArb(f.path);
      // Project keys merge OVER the artifact's (a project can restyle copy).
      arb[m.group(1)!] = {
        ...?arb[m.group(1)!],
        ...Map.fromEntries(
            entries.entries.where((e) => !e.key.startsWith('@'))),
      };
    }
  }

  scanArbDir(Directory(p.join(artifactDir, 'l10n')));

  // ---- the live-read project overlay (~/.appbox/projects/<name>/) ---------
  // The studio serves the CURRENT PROJECT's data alongside its own chrome:
  //   design/surfaces/**.html -> templates ui/project/<sub>  (screen partials)
  //   design/l10n/app_*.arb   -> merged over the artifact's arb (project wins)
  //   **.json anywhere        -> fixtures at /project/<rel>  (design seeds,
  //                              intake registry+flows, build evidence)
  if (projectDir != null) {
    for (final f in _walk(Directory(projectDir))) {
      final rel = p.relative(f.path, from: projectDir).split(p.separator).join('/');
      if (rel.endsWith('.html') || rel.endsWith('.js')) iconScan(f.readAsStringSync());
      if (rel.startsWith('design/surfaces/') && rel.endsWith('.html')) {
        templates['ui/project/${rel.substring('design/surfaces/'.length)}'] =
            f.readAsStringSync();
      }
      if (rel.endsWith('.json')) {
        fixtures['$origin/project/$rel'] = f.readAsStringSync();
      }
    }
    scanArbDir(Directory(p.join(projectDir, 'design', 'l10n')));
  }
  final icons = <String, String>{};
  if (iconsDir != null) {
    for (final name in iconNames) {
      final f = File(p.join(iconsDir, '$name.svg'));
      if (f.existsSync()) icons[name] = f.readAsStringSync();
    }
  }
  return _Prefetch(templates, fixtures, arb, icons);
}

List<File> _walk(Directory d) => d
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => !f.path.contains(RegExp(r'[/\\](node_modules|\.git)([/\\]|$)')))
    .toList();

/// A live headless-Chrome worker tab. Boot it once per server; reload on
/// artifact change; dispose on shutdown.
class JsWorker {
  JsWorker._(this._tab, this._workerPageUrl, this._origin, this._artifactDir,
      this._iconsDir, this._projectDir);
  final CdpSession _tab;
  final String _workerPageUrl;
  final String _origin;
  final String _artifactDir;
  final String? _iconsDir;
  final String? _projectDir;
  _ChromeHandle? _chrome;

  /// Boot a worker against the artifact served at [origin] (the Dart server's
  /// own origin). [workerPageUrl] is the server's internal worker page.
  ///
  /// Launches Chrome directly (rather than via CdpClient.launch) so we own the
  /// Chrome [Process] and can report a real [workerPid] (behavior 4: the worker
  /// is a distinct process from the Dart server pid). cdp.dart is not modified.
  static Future<JsWorker> boot({
    required String workerPageUrl,
    required String origin,
    required String artifactDir,
    String? iconsDir,
    String? projectDir,
  }) async {
    final handle = await _ChromeHandle.launch();
    try {
      final tab = await handle.client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(workerPageUrl, settleMs: 600);
      final w = JsWorker._(
          tab, workerPageUrl, origin, artifactDir, iconsDir, projectDir)
        .._chrome = handle;
      await w._inject(
          _scanArtifact(artifactDir, origin, iconsDir, projectDir: projectDir));
      final ok = await tab.evaluateFunction(
          '(b) => globalThis.__boot(b).then(() => true).catch(e => "FAIL:"+(e&&e.message||e))',
          origin);
      if (ok != true) {
        await handle.close();
        throw StateError('worker boot failed: $ok');
      }
      return w;
    } catch (e) {
      await handle.close();
      rethrow;
    }
  }

  Future<void> _inject(_Prefetch pf) async {
    await _tab.evaluate('globalThis.__templates=${jsonEncode(pf.templates)};');
    await _tab.evaluate('globalThis.__fixtures=${jsonEncode(pf.fixtures)};');
    await _tab.evaluate('globalThis.__arb=${jsonEncode(pf.arb)};');
    await _tab.evaluate('globalThis.__icons=${jsonEncode(pf.icons)};');
  }

  /// The Chrome process pid (the "worker" pid — distinct from the Dart pid).
  int get workerPid => _chrome?.pid ?? -1;

  /// The route table: `[[method, path], ...]`.
  Future<List<List<String>>> routes() async {
    final raw =
        await _tab.evaluate('JSON.stringify(globalThis.__routes())') as String;
    return [
      for (final r in jsonDecode(raw) as List)
        [(r[0] as String).toUpperCase(), r[1] as String]
    ];
  }

  /// Dispatch one request through the artifact's viewmodel layer. [state]
  /// carries sessions/timers/locale so the JS side stays stateless across
  /// reloads.
  Future<WorkerResponse> dispatch(
    String method,
    String fullPath, {
    Map<String, String> headers = const {},
    String? body,
    Map<String, dynamic> state = const {},
  }) async {
    final raw = await _tab.evaluateFunction(
      '(req) => globalThis.__dispatch(req.method, req.path, req.headers, req.body, req.state)',
      {
        'method': method.toUpperCase(),
        'path': fullPath,
        'headers': headers,
        'body': body,
        'state': state,
      },
    );
    return WorkerResponse.fromJson(
        jsonDecode(raw as String) as Map<String, dynamic>);
  }

  /// Hot reload: re-navigate the worker page, then re-scan disk and re-boot.
  ///
  /// The renavigation is what makes nested modules pick up edits. A dynamic
  /// `import()` is evaluated once per realm: every module the graph pulls in
  /// (services/facades, viewmodels, repositories) is keyed in the realm's
  /// module map by resolved URL and never fetched again. A cache-busting query
  /// on the entry specifier cannot fix that — relative specifiers resolve
  /// against the base URL's path, so `./services/x.js` drops the query.
  /// Only a fresh realm empties the map, so we reboot the page the same way
  /// [boot] does, in the same order: navigate, then inject (the globals
  /// _inject writes do not survive a navigation), then __boot.
  ///
  /// Cost is per reload (watcher-triggered), not per request — one navigation
  /// plus a re-parse of the worker page's scripts, ~850ms measured, most of it
  /// the navigateAndSettle wait. Dispatch is untouched.
  Future<void> reload() async {
    await _tab.navigateAndSettle(_workerPageUrl, settleMs: 600);
    await _inject(_scanArtifact(_artifactDir, _origin, _iconsDir,
        projectDir: _projectDir));
    final ok = await _tab.evaluateFunction(
        '(b) => globalThis.__boot(b).then(()=>true).catch(e=>"FAIL:"+(e&&e.message||e))',
        _origin);
    // A failed reboot used to be discarded here — which is how a reload that
    // re-imported nothing stayed invisible. Keep serving, but say so.
    if (ok != true) stderr.writeln('worker reload failed: $ok');
  }

  Future<void> dispose() async {
    await _chrome?.close();
  }
}

/// Owns the spawned headless-Chrome process + its CDP client. Mirrors
/// cdp.dart's CdpClient.launch args (keep in sync); launched here so the worker
/// bridge can report a real Chrome pid without modifying cdp.dart.
class _ChromeHandle {
  _ChromeHandle(this.client, this.process, this.tmpDir);
  final CdpClient client;
  final Process process;
  final Directory tmpDir;
  int get pid => process.pid;

  static Future<_ChromeHandle> launch() async {
    final chromePath = CdpClient.defaultChromePath();
    if (!await File(chromePath).exists()) {
      throw StateError('Chrome not found at: $chromePath');
    }
    final tmpDir = await Directory.systemTemp.createTemp('appbox-design-worker-');
    final args = [
      '--headless=new',
      '--remote-debugging-port=0',
      '--user-data-dir=${tmpDir.path}',
      '--no-first-run',
      '--no-default-browser-check',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
      '--ignore-gpu-blocklist',
      '--hide-scrollbars',
      'about:blank',
    ];
    final proc = await Process.start(chromePath, args);
    final wsUrl = await _readWsUrl(proc);
    final client = await CdpClient.connect(wsUrl);
    return _ChromeHandle(client, proc, tmpDir);
  }

  static Future<String> _readWsUrl(Process proc) async {
    final completer = Completer<String>();
    late StreamSubscription sub;
    sub = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        final m = RegExp(r'ws://\S+').firstMatch(line);
        if (m != null && !completer.isCompleted) completer.complete(m.group(0)!);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('Chrome exited before DevTools URL'));
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      await sub.cancel();
    }
  }

  Future<void> close() async {
    // Graceful shutdown via CDP: Browser.close makes Chrome tear down ALL its
    // child processes (renderer/gpu/zygote). A bare kill(sigkill) on the parent
    // orphans the children — they pile up across test runs.
    try {
      await client.send('Browser.close').timeout(
          const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {
      // already gone / command rejected — fall through to the hard kill.
    }
    await client.close();
    if (!process.kill(ProcessSignal.sigkill)) {
      // already exited — nothing more to do.
    }
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Locate the vendored worker assets (worker_page.html + shim + nunjucks),
/// bundled inside the appboxd package. Walks up from [from] to find
/// `appboxd/pubspec.yaml`.
String? findWorkerAssetsDir([String? from]) {
  var dir = Directory(from ?? Directory.current.path);
  for (var i = 0; i < 12; i++) {
    final candidate = File(p.join(dir.path, 'appboxd', 'pubspec.yaml'));
    if (candidate.existsSync()) {
      final assets = p.join(dir.path, 'appboxd', 'lib', 'design_server',
          'worker_assets', 'worker_page.html');
      if (File(assets).existsSync()) {
        return p.dirname(assets);
      }
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}
