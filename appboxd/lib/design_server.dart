// The appbox design server (ports skills/appbox-designer/runtime/serve.mjs +
// lib/*.mjs). Dart owns the process contract — target resolution, ports,
// supervisor/hot-reload, pidfile registry, session/pref/timer state, exit
// codes 64/66/69/70/77. Artifact JS (app.routes.js viewmodels, Nunjucks views)
// executes in a headless-Chrome worker over CDP (see worker.dart): the designs
// stay ES modules, the toolchain stays Dart.
//
// Divergence from serve.mjs: serve.mjs is a node supervisor spawning a node
// worker process. Here the Dart server is one process and the "worker" is the
// Chrome tab — viewmodel exceptions are caught (→ 500), never crash the server,
// so no Dart subprocess is needed. Hot reload re-imports the artifact modules
// cache-busted in the same Chrome tab (worker.reload). Timers/sessions live in
// Dart state, so they ride out a reload (behavior 13) trivially.
//
// Divergence from serve.mjs's sha1: Dart has no sha1 in-tree (crypto_aead is
// sha256); the state-file id would use a 12-char sha256 prefix — same
// uniqueness, different digest. (State currently lives in-memory; the snapshot
// file is the documented persistence seam.)

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/design_server/worker.dart';
import 'package:appboxd/project.dart';
import 'package:path/path.dart' as p;

const _exitUsage = 64;
const _exitNothing = 66;
const _exitAddrInUse = 69;
const _exitOther = 70;
const _exitAcces = 77;

final _ignoreRe = RegExp(
    r'(^|[/\\])(node_modules|\.git|build|\.dart_tool)([/\\]|$)|\.DS_Store$');

/// The current process pid (dart:io's top-level `pid`). Wrapped so the
/// `DesignServer.pid` instance getter can read it without shadowing itself.
int get _osPid => pid;

/// The artifact the user asked to serve, plus the candidates searched.
class ResolvedTarget {
  final String dir;
  final List<String> tried;
  ResolvedTarget(this.dir, this.tried);
}

/// Resolve a bare design name or path to an artifact dir containing
/// `app.routes.js`. Port of serve.mjs's candidate walk.
ResolvedTarget? resolveArtifact(String target, {String? cwd}) {
  final base = cwd ?? Directory.current.path;
  final candidates = <String>[
    p.absolute(target),
    p.absolute(p.join(base, 'designs', target)),
  ];
  for (var dir = base;;) {
    candidates.add(p.join(dir, 'designs', target));
    if (p.dirname(dir) == dir) break;
    dir = p.dirname(dir);
  }
  for (final c in candidates) {
    if (File(p.join(c, 'app.routes.js')).existsSync()) {
      return ResolvedTarget(c, candidates);
    }
  }
  return null;
}

class _ServeArgs {
  String? target;
  int port = Platform.environment['PORT'] != null
      ? int.tryParse(Platform.environment['PORT']!) ?? -1
      : 4319;
  String host = Platform.environment['HOST'] ?? '127.0.0.1';
  bool asJson = false;
  bool noWatch = false;
  bool worker = false;
  String? project;
  String? error;
}

_ServeArgs _parseArgs(List<String> args) {
  final a = _ServeArgs();
  for (var i = 0; i < args.length; i++) {
    final s = args[i];
    if (s == '--port') {
      if (i + 1 >= args.length) {
        a.error = '--port requires a value';
        return a;
      }
      a.port = int.tryParse(args[++i]) ?? -1;
    } else if (s.startsWith('--port=')) {
      a.port = int.tryParse(s.substring(7)) ?? -1;
    } else if (s == '--host') {
      a.host = args[++i];
    } else if (s.startsWith('--host=')) {
      a.host = s.substring(7);
    } else if (s == '--json') {
      a.asJson = true;
    } else if (s == '--no-watch') {
      a.noWatch = true;
    } else if (s == '--worker') {
      a.worker = true; // accepted for compat; no-op (Chrome is the worker)
    } else if (s == '--project') {
      if (i + 1 >= args.length) {
        a.error = '--project requires a value';
        return a;
      }
      a.project = args[++i];
    } else if (s.startsWith('--project=')) {
      a.project = s.substring(10);
    } else if (s.startsWith('--')) {
      a.error = 'unknown flag: $s';
      return a;
    } else {
      a.target = s;
    }
  }
  return a;
}

/// A running design server. Boot via [start]; stop via [stop]. Tested
/// in-process (HttpServer on loopback port 0).
class DesignServer {
  DesignServer._();
  late final HttpServer _http;
  late final JsWorker _worker;
  // Default empty so boot-time static requests (the worker loading its own page
  // + app.routes.js) are served before the route table is populated.
  List<List<String>> _routeTable = const [];
  StreamSubscription<FileSystemEvent>? _watcherSub;
  StreamSubscription<FileSystemEvent>? _projectWatcherSub;
  Timer? _debounce;
  bool _stopped = false;

  final _sessions = <String, Map<String, dynamic>>{};
  final _timers = <String, Map<String, dynamic>>{};
  late final Set<String> locales;

  String artifactDir = '';
  String? projectRoot;
  String host = '127.0.0.1';
  int get port => _http.port;
  int _pidValue = 0;
  int get pid => _pidValue;
  int workerPid = -1;
  bool noWatch = false;
  String _vendorDir = '';
  String _workerAssetsDir = '';

  String get url {
    final shown = (host == '0.0.0.0' || host == '::') ? 'localhost' : host;
    return 'http://$shown:$port/';
  }

  /// Boot the server. [port] 0 asks the OS for a free port. [projectDir]
  /// overlays the live-read project (.appbox/projects/name) — see
  /// _scanArtifact in worker.dart.
  static Future<DesignServer> start({
    required String artifactDir,
    int port = 0,
    String host = '127.0.0.1',
    bool noWatch = false,
    String? runtimeVendorDir,
    String? iconsDir,
    String? workerAssetsDir,
    String? projectDir,
  }) async {
    final srv = DesignServer._()
      ..artifactDir = artifactDir
      ..projectRoot = projectDir
      .._pidValue = _osPid
      ..host = host
      ..noWatch = noWatch
      ..locales = _scanLocales(artifactDir, projectDir: projectDir);
    // Let SocketException propagate (EADDRINUSE/EACCES) — designServe maps it
    // via bindExitCode; tests assert the bind path directly.
    srv._http = await HttpServer.bind(_bindAddress(host), port);
    // Start serving BEFORE booting the worker: the worker loads its page from
    // this very origin, so the socket must be listening first.
    srv._http.listen(srv._handle);
    final assets = workerAssetsDir ?? findWorkerAssetsDir();
    if (assets == null) {
      await srv._http.close(force: true);
      throw StateError(
          'worker assets not found (lib/design_server/worker_assets)');
    }
    srv._vendorDir = runtimeVendorDir ?? _findRuntimeVendorDir() ?? '';
    srv._workerAssetsDir = assets;
    final bindHost = (host == '0.0.0.0' || host == '::') ? '127.0.0.1' : host;
    final origin = 'http://$bindHost:${srv.port}';
    srv._worker = await JsWorker.boot(
      workerPageUrl: '$origin/__worker_page',
      origin: origin,
      artifactDir: artifactDir,
      iconsDir: iconsDir ?? _findIconsDir(),
      projectDir: projectDir,
    );
    srv.workerPid = srv._worker.workerPid;
    srv._routeTable = await srv._worker.routes();
    if (!noWatch) {
      srv._startWatcher(artifactDir);
      if (projectDir != null) srv._startProjectWatcher(projectDir);
    }
    return srv;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      final method = req.method;

      if (path == '/__worker_page') {
        return _serveFile(req, p.join(_workerAssetsDir, 'worker_page.html'),
            'text/html; charset=utf-8');
      }
      if (path.startsWith('/__worker_assets/')) {
        final rel = Uri.decodeComponent(path.substring('/__worker_assets/'.length));
        return _serveFile(req, p.join(_workerAssetsDir, rel), _contentType(rel),
            root: _workerAssetsDir);
      }
      if ((method == 'GET' || method == 'POST') && path == '/prefs/lang') {
        return _handlePrefsLang(req);
      }
      // Project write channel (the studio edits the current project): the JS
      // worker POSTs {path, body}; the write is confined to the project dir.
      if (method == 'POST' && path == '/__project_write') {
        return _handleProjectWrite(req);
      }
      // The dashboard's live project grid: every project in ~/.appbox with
      // its derived stage + honest output counts.
      if (method == 'GET' && path == '/__projects') {
        req.response.headers.contentType =
            ContentType.parse('application/json; charset=utf-8');
        req.response.write(jsonEncode({
          'current': currentProject(),
          'projects': projectCards(),
        }));
        await req.response.close();
        return;
      }
      // Point `current` at another project (the overlay itself rebinds on the
      // next serve — the marker + grid update immediately).
      if (method == 'POST' && path == '/__project_use') {
        final payload =
            jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        final name = (payload['name'] ?? '').toString();
        try {
          useProject(name);
        } on ArgumentError catch (e) {
          req.response.statusCode = 404;
          req.response.write(e.message);
          await req.response.close();
          return;
        }
        req.response.headers.contentType =
            ContentType.parse('application/json; charset=utf-8');
        req.response.write(jsonEncode({'ok': true, 'current': name}));
        await req.response.close();
        return;
      }
      if (_matchRoute(method, path) != null) {
        return _dispatch(req, method, path);
      }
      if (path.startsWith('/assets/vendor/')) {
        final rel = Uri.decodeComponent(path.substring('/assets/vendor/'.length));
        return _serveFile(req, p.join(_vendorDir, rel), _contentType(rel),
            root: _vendorDir);
      }
      if (method == 'GET' && _tryServeArtifactFile(req, path)) return;

      req.response.statusCode = 404;
      req.response.headers.contentType =
          ContentType.parse('text/plain; charset=utf-8');
      req.response.headers.add('Vary', 'HX-Request');
      req.response.write('404 — no route for $method $path');
      await req.response.close();
    } catch (e, st) {
      stderr.writeln('[design-server] $e\n$st');
      try {
        req.response.statusCode = 500;
        req.response.headers.contentType =
            ContentType.parse('text/plain; charset=utf-8');
        req.response.write('500 — $e');
        await req.response.close();
      } catch (_) {}
    }
  }

  List<String>? _matchRoute(String method, String path) {
    final pOnly = path.split('?')[0];
    for (final r in _routeTable) {
      if (r[0] == method && _matchPattern(r[1], pOnly)) return r;
    }
    return null;
  }

  static bool _matchPattern(String pattern, String path) {
    final pp = pattern.split('/');
    final ap = path.split('/');
    if (pp.length != ap.length) return false;
    for (var i = 0; i < pp.length; i++) {
      if (pp[i].startsWith(':')) continue;
      if (pp[i] != ap[i]) return false;
    }
    return true;
  }

  Future<void> _dispatch(HttpRequest req, String method, String path) async {
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k] = v.join(','));
    String? body;
    if (method == 'POST' || method == 'PUT' || method == 'PATCH') {
      body = await utf8.decoder.bind(req).join();
    }
    final cookies = _parseCookies(headers);
    var sid = cookies['kdh_sid'];
    var minted = false;
    if (sid == null || !_sessions.containsKey(sid)) {
      sid = _uuid();
      _sessions[sid] = {};
      minted = true;
    }
    final sessionData = Map<String, dynamic>.from(_sessions[sid] ?? {});    final prefs = _parsePrefs(cookies['kdh_prefs']);
    final locale = _resolveLocale(
        locales, req.uri.queryParameters, prefs, headers['accept-language']);
    final state = <String, dynamic>{
      'locale': locale,
      'session': {'id': sid, 'data': sessionData},
      'timers': Map<String, dynamic>.from(_timers),
    };
    final resp = await _worker.dispatch(method, req.uri.toString(),
        headers: headers, body: body, state: state);
    if (resp.session != null) {
      _sessions[sid] =
          Map<String, dynamic>.from(resp.session!['data'] as Map? ?? {});
    }
    _timers
      ..clear()
      ..addAll(resp.timers.cast());

    req.response.statusCode = resp.status;
    resp.headers.forEach((k, v) => req.response.headers.add(k, v));
    if (minted) {
      req.response.headers.add(
          'Set-Cookie', 'kdh_sid=$sid; Path=/; HttpOnly; SameSite=Lax');
    }
    for (final c in resp.setCookies) {
      req.response.headers.add('Set-Cookie', c);
    }
    req.response.headers.add('Vary', 'HX-Request');
    if ((resp.headers['content-type'] ?? '').contains('text/html')) {
      req.response.headers.add('Vary', 'Accept-Language');
    }
    if (resp.body != null) req.response.add(utf8.encode(resp.body!));
    await req.response.close();
  }

  /// POST /__project_write {path, body} — write one file INSIDE the live-read
  /// project. The studio edits the project through this one confined channel
  /// (flow confirms, tile reorders); path traversal outside the project is
  /// rejected. The project watcher hot-reloads the worker on its own.
  Future<void> _handleProjectWrite(HttpRequest req) async {
    Future<void> deny(int code, String msg) async {
      req.response.statusCode = code;
      req.response.headers.contentType =
          ContentType.parse('application/json; charset=utf-8');
      req.response.write(jsonEncode({'ok': false, 'error': msg}));
      await req.response.close();
    }

    final root = projectRoot;
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    } catch (_) {
      return deny(400, 'bad JSON body');
    }
    // payload.project targets ANOTHER (or new) project — the wizard's create
    // path. Name-validated, still confined to the projects dir; ensureProject
    // lays out the four shell dirs first (idempotent).
    final targetProject = payload['project']?.toString();
    if (targetProject != null && !validProjectName(targetProject)) {
      return deny(400, 'bad project name');
    }
    if (targetProject != null) ensureProject(targetProject);
    final base = targetProject != null ? projectDir(targetProject) : root;
    if (base == null) {
      return deny(409, 'no project overlaid');
    }
    final rel = (payload['path'] ?? '').toString();
    final body = payload['body'];
    if (rel.isEmpty || body is! String) {
      return deny(400, 'path and body (string) are required');
    }
    final abs = p.normalize(p.join(base, rel));
    if (!p.isWithin(base, abs) && abs != base) {
      return deny(403, 'path escapes the project');
    }
    final f = File(abs);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(body);
    req.response.headers.contentType =
        ContentType.parse('application/json; charset=utf-8');
    req.response.write(jsonEncode({'ok': true, 'path': rel}));
    await req.response.close();
  }

  Future<void> _handlePrefsLang(HttpRequest req) async {
    String? lang;
    if (req.method == 'POST') {
      final body = await utf8.decoder.bind(req).join();
      lang = Uri.splitQueryString(body)['lang'];
    } else {
      lang = req.uri.queryParameters['lang'];
    }
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k] = v.join(','));
    final cookies = _parseCookies(headers);
    if (locales.contains(lang)) {
      final prefs = _parsePrefs(cookies['kdh_prefs']);
      prefs['lang'] = lang!;
      req.response.headers.add('Set-Cookie',
          'kdh_prefs=${Uri.encodeComponent(jsonEncode(prefs))}; Path=/; Max-Age=31536000; SameSite=Lax');
    }
    req.response.headers.add('Vary', 'HX-Request');
    req.response.headers.add('Vary', 'Accept-Language');
    if (req.headers.value('HX-Request') != null) {
      req.response.headers.add('HX-Refresh', 'true');
    } else {
      var back = '/';
      final ref = req.headers.value('Referer');
      if (ref != null) {
        try {
          final u = Uri.parse(ref);
          back = u.path + (u.query.isEmpty ? '' : '?${u.query}');
        } catch (_) {}
      }
      req.response.statusCode = 302;
      req.response.headers.add('Location', back);
    }
    await req.response.close();
  }

  bool _tryServeArtifactFile(HttpRequest req, String path) {
    final rel = Uri.decodeComponent(path.split('?')[0]);
    if (rel.contains('..')) return false;
    final segs = rel.split('/').where((s) => s.isNotEmpty).join(p.separator);
    if (segs.isEmpty) return false;
    final f = File(p.join(artifactDir, segs));
    if (!f.existsSync() || !_isInside(artifactDir, f.path)) return false;
    _serveFile(req, f.path, _contentType(p.basename(f.path)));
    return true;
  }

  Future<void> _serveFile(HttpRequest req, String absPath, String contentType,
      {String? root}) async {
    final f = File(absPath);
    if (root != null && !_isInside(root, absPath)) {
      req.response.statusCode = 403;
      await req.response.close();
      return;
    }
    if (!f.existsSync()) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType.parse(contentType);
    await req.response.addStream(f.openRead());
    await req.response.close();
  }

  void _startWatcher(String dir) {
    try {
      _watcherSub = Directory(dir).watch(recursive: true).listen((e) {
        if (_ignoreRe.hasMatch(e.path)) return;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 200), () {
          if (!_stopped) _worker.reload();
        });
      });
    } catch (_) {
      // watch unsupported — hot reload simply disabled.
    }
  }

  // The live-read project gets the same hot reload: editing a partial or a
  // fixture under ~/.appbox/projects/<name> re-scans and re-boots the worker.
  void _startProjectWatcher(String dir) {
    try {
      _projectWatcherSub = Directory(dir).watch(recursive: true).listen((e) {
        if (_ignoreRe.hasMatch(e.path)) return;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 200), () {
          if (!_stopped) _worker.reload();
        });
      });
    } catch (_) {
      // watch unsupported — hot reload simply disabled.
    }
  }

  /// Reload the worker now (used by tests; production uses the file watcher).
  Future<void> reload() => _worker.reload();

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _debounce?.cancel();
    await _watcherSub?.cancel();
    await _projectWatcherSub?.cancel();
    await _http.close(force: true);
    await _worker.dispose();
  }
}

// ── the CLI entry ────────────────────────────────────────────────────────
Future<int> designServe(List<String> args) async {
  final a = _parseArgs(args);
  if (a.error != null) {
    stderr.writeln(a.error);
    return _exitUsage;
  }
  if (a.target == null) {
    stderr.writeln('Usage: appbox design serve <artifact-dir|design-name> '
        '[--port N] [--host H] [--json] [--no-watch]');
    return _exitUsage;
  }
  if (a.port < 0 || a.port > 65535) {
    stderr.writeln('not a port: ${a.port}');
    return _exitUsage;
  }
  final resolved = resolveArtifact(a.target!);
  if (resolved == null) {
    stderr.writeln('no artifact at "${a.target}" — every candidate lacked '
        'app.routes.js:');
    for (final c in _triedList(a.target!)) {
      stderr.writeln('  $c');
    }
    return _exitNothing;
  }
  final DesignServer srv;
  // The live-read project: --project wins, then APPBOX_PROJECT, then the
  // ~/.appbox current project when it exists; none → artifact-only serving.
  final projectName = a.project ??
      Platform.environment['APPBOX_PROJECT'] ??
      (Directory(projectDir(currentProject())).existsSync()
          ? currentProject()
          : null);
  final resolvedProject =
      projectName != null && Directory(projectDir(projectName)).existsSync()
          ? projectDir(projectName)
          : null;
  try {
    srv = await DesignServer.start(
      artifactDir: resolved.dir,
      port: a.port,
      host: a.host,
      noWatch: a.noWatch || a.worker,
      projectDir: resolvedProject,
    );
  } on SocketException catch (e) {
    final code = bindExitCode(e);
    if (code == _exitAddrInUse) {
      stderr.writeln('port ${a.port} is already in use on ${a.host} — '
          'pass --port 0 for any free port');
      return _exitAddrInUse;
    }
    if (code == _exitAcces) {
      stderr.writeln('not allowed to bind ${a.host}:${a.port}');
      return _exitAcces;
    }
    stderr.writeln(e.message);
    return _exitOther;
  } catch (e) {
    stderr.writeln('$e');
    return _exitOther;
  }

  if (!a.noWatch) {
    registerServeInstance(srv.pid, srv.artifactDir);
  }

  if (a.asJson) {
    stdout.writeln(jsonEncode({
      'url': srv.url,
      'port': srv.port,
      'host': srv.host,
      'pid': srv.pid,
      'artifact': srv.artifactDir,
      'workerPid': srv.workerPid,
    }));
  } else {
    for (final line in humanReadyLines(
        url: srv.url, host: srv.host, artifactDir: srv.artifactDir)) {
      stdout.writeln(line);
    }
  }

  final completer = Completer<int>();
  Future<void> shutdown(int code) async {
    if (completer.isCompleted) return;
    if (!a.noWatch) deregisterServeInstance(srv.pid);
    await srv.stop();
    if (!completer.isCompleted) completer.complete(code);
  }

  StreamSubscription? termSub;
  StreamSubscription? intSub;
  if (!a.noWatch) {
    intSub = ProcessSignal.sigint.watch().listen((_) {
      sweepSiblingInstances(srv.pid, srv.artifactDir);
      shutdown(0);
    });
  }
  termSub = ProcessSignal.sigterm.watch().listen((_) => shutdown(0));

  final code = await completer.future;
  await termSub.cancel();
  await intSub?.cancel();
  return code;
}

// ── ready output (extracted for testing the --host 0.0.0.0 warning) ────────
List<String> humanReadyLines(
    {required String url, required String host, required String artifactDir}) {
  final out = <String>[
    'appbox-designer serving $artifactDir',
    '→ $url',
  ];
  if (host == '0.0.0.0' || host == '::') {
    out.add('  (bound to every interface — reachable from your network)');
  }
  out.add(
      '  watching for changes — Ctrl+C stops every instance of this design');
  return out;
}

// ── helpers ──────────────────────────────────────────────────────────────
List<String> _triedList(String target) {
  final base = Directory.current.path;
  final candidates = <String>[
    p.absolute(target),
    p.absolute(p.join(base, 'designs', target)),
  ];
  for (var dir = base;;) {
    candidates.add(p.join(dir, 'designs', target));
    if (p.dirname(dir) == dir) break;
    dir = p.dirname(dir);
  }
  return candidates;
}

InternetAddress _bindAddress(String host) {
  if (host == '0.0.0.0') return InternetAddress.anyIPv4;
  if (host == '::') return InternetAddress.anyIPv6;
  return InternetAddress(host);
}

Set<String> _scanLocales(String artifactDir, {String? projectDir}) {
  final out = <String>{};
  void scan(Directory dir) {
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      final m = RegExp(r'app_(.+)\.arb$').firstMatch(p.basename(f.path));
      if (m != null) out.add(m.group(1)!);
    }
  }

  scan(Directory(p.join(artifactDir, 'l10n')));
  if (projectDir != null) {
    scan(Directory(p.join(projectDir, 'design', 'l10n')));
  }
  return out;
}

/// Locale resolution: ?lang= → prefs.lang → Accept-Language → 'en'. Port of
/// lib/l10n.mjs's resolveLocale.
String _resolveLocale(Set<String> locales, Map<String, String> query,
    Map<String, dynamic> prefs, String? acceptLanguage) {
  if (locales.isEmpty) return 'en';
  final q = query['lang'];
  if (q != null && locales.contains(q)) return q;
  final pLang = prefs['lang'];
  if (pLang is String && locales.contains(pLang)) return pLang;
  if (acceptLanguage != null) {
    for (final tag in _parseAcceptLanguage(acceptLanguage)) {
      final base = tag.split('-')[0];
      for (final l in locales) {
        if (l == tag || l.split('-')[0] == base) return l;
      }
    }
  }
  return 'en';
}

List<String> _parseAcceptLanguage(String header) {
  final entries = <(String, double)>[];
  for (final part in header.split(',')) {
    final segs = part.trim().split(';');
    if (segs.isEmpty || segs.first.trim().isEmpty) continue;
    final tag = segs.first.trim().toLowerCase();
    var qv = 1.0;
    for (final s in segs.skip(1)) {
      final t = s.trim();
      if (t.startsWith('q=')) qv = double.tryParse(t.substring(2)) ?? 0;
    }
    if (qv > 0) entries.add((tag, qv));
  }
  entries.sort((a, b) => b.$2.compareTo(a.$2));
  return entries.map((e) => e.$1).toList();
}

Map<String, String> _parseCookies(Map<String, String> headers) {
  final raw = headers['cookie'] ?? headers['Cookie'] ?? '';
  final out = <String, String>{};
  for (final part in raw.split(';')) {
    final i = part.indexOf('=');
    if (i > 0) {
      out[part.substring(0, i).trim()] =
          Uri.decodeComponent(part.substring(i + 1).trim());
    }
  }
  return out;
}

Map<String, dynamic> _parsePrefs(String? cookie) {
  if (cookie == null || cookie.isEmpty) return {};
  try {
    return (jsonDecode(Uri.decodeComponent(cookie)) as Map)
        .cast<String, dynamic>();
  } catch (_) {
    return {};
  }
}

int _uuidCounter = 0;
String _uuid() =>
    '${DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36)}-'
    '${pid.toRadixString(36)}-${(_uuidCounter++).toRadixString(36)}';

bool _isInside(String root, String path) {
  final r = p.absolute(root);
  final f = p.absolute(path);
  return f == r || f.startsWith('$r${p.separator}');
}

String _contentType(String name) {
  if (name.endsWith('.js')) return 'text/javascript; charset=utf-8';
  if (name.endsWith('.html')) return 'text/html; charset=utf-8';
  if (name.endsWith('.css')) return 'text/css; charset=utf-8';
  if (name.endsWith('.json')) return 'application/json; charset=utf-8';
  if (name.endsWith('.svg')) return 'image/svg+xml';
  return 'application/octet-stream';
}

// ── pidfile registry ─────────────────────────────────────────────────────
Directory get serveRegistryDir =>
    Directory(p.join(Directory.systemTemp.path, 'appbox-designer-serve'));

void registerServeInstance(int pid, String artifactDir) {
  serveRegistryDir.createSync(recursive: true);
  File(p.join(serveRegistryDir.path, '$pid.json'))
      .writeAsStringSync(jsonEncode({'artifactDir': artifactDir}));
}

void deregisterServeInstance(int pid) {
  try {
    File(p.join(serveRegistryDir.path, '$pid.json')).deleteSync();
  } catch (_) {}
}

/// SIGINT stops EVERY instance serving the same artifact. For each sibling
/// pidfile whose artifactDir matches, verify via `ps` that the pid is still a
/// design-server process (pids get reused) before signalling; sweep stale ones.
/// Returns the sibling pids that were signalled (for tests).
List<int> sweepSiblingInstances(int selfPid, String artifactDir,
    {void Function(int pid)? kill}) {
  final killed = <int>[];
  final files = serveRegistryDir.existsSync()
      ? serveRegistryDir.listSync().whereType<File>().toList()
      : const <File>[];
  for (final f in files) {
    final m = RegExp(r'^(\d+)\.json$').firstMatch(p.basename(f.path));
    final other = m == null ? null : int.tryParse(m.group(1)!);
    if (other == null || other == selfPid) continue;
    Map<String, dynamic>? entry;
    try {
      entry = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    if (entry['artifactDir'] != artifactDir) continue;
    try {
      final r = Process.runSync('ps', ['-p', '$other', '-o', 'command=']);
      if (r.exitCode != 0) {
        try {
          f.deleteSync();
        } catch (_) {}
        continue;
      }
      final cmd = (r.stdout as String).trim();
      if (cmd.contains('appbox') ||
          cmd.contains('design_server') ||
          cmd.contains('design serve')) {
        if (kill != null) {
          kill(other);
        } else {
          Process.killPid(other, ProcessSignal.sigterm);
        }
        killed.add(other);
      } else {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
  return killed;
}

int serveRegistryFileCount() =>
    serveRegistryDir.existsSync() ? serveRegistryDir.listSync().length : 0;

String? _findRuntimeVendorDir() {
  var dir = Directory.current;
  for (var i = 0; i < 12; i++) {
    final c =
        p.join(dir.path, 'skills', 'appbox-designer', 'runtime', 'vendor');
    if (Directory(c).existsSync()) return c;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}

String? _findIconsDir() {
  final v = _findRuntimeVendorDir();
  if (v == null) return null;
  final c = p.join(v, 'lucide', 'icons');
  return Directory(c).existsSync() ? c : null;
}

/// Map a bind-time SocketException to a serve exit code (69/77/70). Exposed so
/// the port-collision path is testable in-process without spawning the CLI.
int bindExitCode(SocketException e) {
  final code = e.osError?.errorCode;
  final msg = e.message;
  if (code == 48 || code == 98 || msg.contains('in use')) return _exitAddrInUse;
  if (code == 13 || msg.contains('Permission denied')) return _exitAcces;
  return _exitOther;
}
