// The appbox design server (ports skills/appbox-designer/runtime/serve.mjs +
// lib/*.mjs). Dart owns the process contract — target resolution, ports,
// supervisor/hot-reload, pidfile registry, session/pref/timer state, exit
// codes 64/66/69/70/77. Artifact JS (app.routes.js viewmodels, TSX views)
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

import 'package:appboxd/design_dial.dart';
import 'package:appboxd/design_media.dart';
import 'package:appboxd/design_draft.dart';
import 'package:appboxd/design_server/browser_trust.dart';
import 'package:appboxd/design_server/l10n.dart';
import 'package:appboxd/design_server/worker.dart';
import 'package:appboxd/design_tools.dart' show scriptRepoRoot;
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

// ── the error surface ────────────────────────────────────────────────────
// What the user is told when a request fails. The raw exception never gets
// here: it goes to stderr in the catch block.
//
// These constants are no longer the strings the user sees — they are the
// FALLBACKS behind the ARB lookup (task #46). [ErrorCatalog] reads
// `l10n/app_<locale>.arb` off disk and only lands on one of these when the key
// is missing from every catalog or a catalog is unreadable. Translation here
// deliberately does NOT go through the worker's `t()`: this surface exists for
// the case where a request could not be served, and the worker may be exactly
// what failed, so the error page must not depend on it.

/// Fallback for t('errorSurface.serverError')
const _msgServerError =
    'Something went wrong on the appbox server. The serve log has the detail.';

/// Fallback for t('errorSurface.pageHint')
const _msgErrorHint = 'Nothing you had open was lost — this request alone failed.';

/// Fallback for t('errorSurface.backHome')
const _msgBackHome = 'Back to the dashboard';

/// Fallback for t('errorSurface.dismiss')
const _msgDismiss = 'Dismiss';

/// Fallback for t('errorSurface.notFound')
const _msgNotFound = 'no route for {method} {path}';

/// Fallback for t('errorSurface.reloading')
///
/// Its own message, not `serverError`: this is a transient state with a known
/// cause and a useful instruction ("try again"), and telling the user something
/// went wrong on the server would be both wrong and unactionable.
const _msgReloading =
    'The design server is reloading after a file change. Try again in a moment.';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// The htmx fragment. htmx retargets it into `#toasts` (the hx-status 404/5xx
/// rules in base.tsx) — so it lands in the always-rendered tray without
/// touching whatever panel the request came from, and only one shows at a
/// time. The checkbox is the dismiss control: pure CSS, no client JS.
String _errorToast(String message, String dismiss) =>
    '<div class="toast toast-error">'
    '<input type="checkbox" id="toast-error-cb" class="toast-error-cb" '
    'aria-label="${_esc(dismiss)}">'
    '<span class="toast-error-msg">${_esc(message)}</span>'
    '<label for="toast-error-cb" class="toast-error-x" aria-hidden="true">'
    '&times;</label>'
    '</div>';

/// The full-page (non-htmx) failure: a real page, not a bare string.
///
/// `<html lang>` carries the resolved locale, not a hard-coded "en" — a page
/// whose text is Polish while its lang attribute claims English mis-announces
/// every word to a screen reader.
String _errorPage(int status, String message, String locale, String hint,
        String backHome) =>
    '<!doctype html>\n'
    '<html lang="${_esc(locale)}"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    '<title>$status — appbox</title>'
    '<link rel="stylesheet" href="/ui/styles/common/app.css">'
    '<link rel="stylesheet" href="/ui/styles/studio_unknown_shell/error_surface.css">'
    '</head><body><div id="app" data-theme="light">'
    '<main class="error-page">'
    '<p class="error-page-code">$status</p>'
    '<h1 class="error-page-msg">${_esc(message)}</h1>'
    '<p class="error-page-hint">${_esc(hint)}</p>'
    '<a class="error-page-home" href="/">${_esc(backHome)}</a>'
    '</main></div></body></html>';

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
  bool dial = true;
  String? project;
  // Repeatable. Env fallbacks so a long-lived studio server can be configured
  // once instead of on every relaunch.
  List<String> trustedHosts = [
    ..._splitList(Platform.environment['APPBOX_TRUSTED_HOSTS']),
  ];
  List<String> trustedOrigins = [
    ..._splitList(Platform.environment['APPBOX_TRUSTED_ORIGINS']),
  ];
  String? error;
}

Iterable<String> _splitList(String? raw) =>
    (raw ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);

/// The name of the machine-wide trusted-origins file under [appboxHome].
const kTrustedOriginsFile = 'trusted-origins';

/// The Design Dial's central-store credentials: `url=` + `service_key=`
/// lines in `~/.appbox/supabase`, `#` starts a comment. Read at boot only;
/// the env vars (APPBOX_SUPABASE_URL / APPBOX_SUPABASE_SERVICE_KEY) win when
/// set. Same machine-scoped argument as trusted origins: the operator's
/// Supabase project is a fact about this laptop, not about any client repo.
/// Missing file = no Supabase = the dial runs its honest memory store.
String? readSupabaseCredentialsFile() {
  final f = File(p.join(appboxHome(), 'supabase'));
  if (!f.existsSync()) return null;
  try {
    return f.readAsStringSync();
  } catch (_) {
    return null; // unreadable credentials must not break the server boot
  }
}

/// Origins this machine trusts to call `/__*` cross-origin: one per line in
/// `~/.appbox/trusted-origins`, `#` starts a comment.
///
/// MACHINE-scoped, not repo-scoped, and that is the whole point. "The arxa
/// studio at :7891 may subscribe to my design servers" is a fact about this
/// laptop; a design server runs from whichever client repo the design lives
/// in, and `config/appbox.config.json` is the pipeline's SSOT — an operator
/// preference has no business in it. ~/.appbox is where appbox already keeps
/// operator state (projects, the current marker), so it goes there.
///
/// A line that is not a parseable `scheme://host` is DROPPED and named on
/// stderr. Left in, it would fall through normalizeOrigin's raw-string
/// fallback, match nothing, and look exactly like "the flag didn't work" —
/// the worst failure shape an allowlist can have.
List<String> readTrustedOriginsFile() {
  final f = File(p.join(appboxHome(), kTrustedOriginsFile));
  if (!f.existsSync()) return const [];
  final out = <String>[];
  for (final raw in f.readAsLinesSync()) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;
    final u = Uri.tryParse(line);
    if (u == null || u.scheme.isEmpty || u.host.isEmpty) {
      stderr.writeln('[design-server] ${f.path}: ignoring "$line" — '
          'not a scheme://host origin');
      continue;
    }
    out.add(line);
  }
  return out;
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
    } else if (s == '--no-dial') {
      a.dial = false;
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
    } else if (s == '--trusted-host' || s == '--trusted-origin') {
      if (i + 1 >= args.length) {
        a.error = '$s requires a value';
        return a;
      }
      (s == '--trusted-host' ? a.trustedHosts : a.trustedOrigins)
          .add(args[++i]);
    } else if (s.startsWith('--trusted-host=')) {
      a.trustedHosts.addAll(_splitList(s.substring(15)));
    } else if (s.startsWith('--trusted-origin=')) {
      a.trustedOrigins.addAll(_splitList(s.substring(17)));
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

  /// How long a request waits for an in-flight hot reload before giving up.
  ///
  /// From measurement rather than taste: while root-causing task #19 the
  /// slowest observed reload was 948ms (re-navigate + 600ms settle + re-scan +
  /// `__boot`), and a reload that hits the worker's boot retry (task #51) adds
  /// ~850ms on top of that. 3800ms is 4x the slowest observed, which covers the
  /// retry path with room to spare. Past that point the reload is not coming
  /// back, and a loud 503 is more use to the caller than a longer stall.
  static const Duration _kReloadGrace = Duration(milliseconds: 3800);

  late final Duration _reloadGrace;

  final _sessions = <String, Map<String, dynamic>>{};

  /// Timers, KEYED BY SESSION ID — the same shape as [_sessions] (task #53).
  ///
  /// This used to be a flat `timerId -> record` map shared by the whole
  /// process, which leaked two ways at once: every request was handed every
  /// other session's timers, and every response replaced the map wholesale, so
  /// one user's reply deleted another user's running timer. `_sessions`, three
  /// lines up, had always been keyed correctly; the timers beside it simply
  /// never were.
  final _timers = <String, Map<String, dynamic>>{};
  late final Set<String> locales;

  /// Translation for the error surface only, read straight off disk so a dead
  /// worker cannot take the error page down with it (task #46).
  late final ErrorCatalog _errorCatalog;

  /// Tail of the pending-request chain per session id — the per-session lock
  /// behind [_withSessionLock].
  final _sessionLocks = <String, Future<void>>{};

  /// Run [body] with exclusive access to session [sid]'s stored state.
  ///
  /// Requests for DIFFERENT sessions still run concurrently — serializing all
  /// of them would undo the multi-user separation task #53 just established.
  ///
  /// The gate is released in `whenComplete`, not on success: `_worker.dispatch`
  /// can throw, and since task #51 it can throw *after* an 850ms reboot. A lock
  /// released only on the happy path would wedge every later request for that
  /// session — trading a lost update for a permanent hang, which is worse.
  Future<T> _withSessionLock<T>(String sid, Future<T> Function() body) {
    final prev = _sessionLocks[sid] ?? Future<void>.value();
    final gate = Completer<void>();
    _sessionLocks[sid] = gate.future;
    return prev.then((_) => body()).whenComplete(() {
      gate.complete();
      // Only the tail clears the entry, or a slow request finishing after a
      // newer one would drop a lock another request is still queued behind,
      // and the map would leak an entry per session forever.
      if (identical(_sessionLocks[sid], gate.future)) _sessionLocks.remove(sid);
    });
  }

  static Map<String, String> _headerMap(HttpRequest req) {
    final h = <String, String>{};
    req.headers.forEach((k, v) => h[k] = v.join(','));
    return h;
  }

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

  /// The Design Dial (locked amendment 2026-08-23): baked into every served
  /// artifact page by default; the operator turns it off with --no-dial.
  /// Clients cannot hide it (watermark role) — there is no per-page switch.
  bool dialEnabled = true;

  /// The dial's store: Supabase when APPBOX_SUPABASE_URL +
  /// APPBOX_SUPABASE_SERVICE_KEY are set, else the honest per-process memory
  /// store (the island badges that mode 'local').
  late final DialStore dialStore;

  /// The pure request core behind /__dial/* (see design_dial.dart).
  late final DialApi dialApi;

  /// The Design Dial's Draft Overlay store (Design Mode): per-artifact local
  /// file state, never Supabase (decisions 5/11). Null when the dial is off.
  DraftFileStore? draftStore;

  /// Held-open dial event subscribers (GET /__dial/events) — separate from
  /// the reload stream: different audience, different cadence.
  final _dialEventClients = <HttpResponse>{};

  /// Artifact identity the dial scopes pins/links to (dir basename).
  String get _dialArtifact => p.basename(artifactDir);

  /// Host/Origin allowlist — see browser_trust.dart for what it defends and
  /// what it deliberately does not.
  late final BrowserTrust trust;

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
    Duration reloadGrace = _kReloadGrace,
    Duration eventHeartbeat = const Duration(seconds: 20),
    Iterable<String> trustedHosts = const [],
    Iterable<String> trustedOrigins = const [],
    bool dial = true,
    DialStore? dialStore,
    DraftFileStore? draftStore,
  }) async {
    // Absolutize up front: artifact files are served and re-scanned (worker
    // boot, watcher reload) against the process cwd at USE time, so a relative
    // dir silently breaks the worker's app.routes.js fetch the moment the
    // caller's cwd is not the long-lived server's. Resolve it once, here,
    // while the caller's cwd is still the right base.
    artifactDir = p.normalize(p.absolute(artifactDir));
    final srv = DesignServer._()
      ..artifactDir = artifactDir
      ..projectRoot = projectDir
      .._pidValue = _osPid
      ..host = host
      ..noWatch = noWatch
      .._reloadGrace = reloadGrace
      .._eventHeartbeat = eventHeartbeat
      ..locales = _scanLocales(artifactDir, projectDir: projectDir)
      .._errorCatalog =
          ErrorCatalog(_l10nDirs(artifactDir, projectDir: projectDir))
      ..dialEnabled = dial
      ..dialStore = dialStore ??
          SupabaseDialStore.fromConfig(
              credentialsFileText: readSupabaseCredentialsFile()) ??
          MemoryDialStore()
      ..draftStore = dial
          ? (draftStore ?? DraftFileStore(artifactDir: artifactDir))
          : null;
    srv.dialApi = DialApi(
        store: srv.dialStore,
        artifact: srv._dialArtifact,
        draftStore: srv.draftStore,
        artifactDir: srv.artifactDir,
        media: DialMediaProxy(
          unsplashKey: Platform.environment['UNSPLASH_ACCESS_KEY'] ?? '',
          pexelsKey: Platform.environment['PEXELS_API_KEY'] ?? '',
        ));
    if (dial) {
      stderr.writeln('[design-server] dial store: ${srv.dialStore.kind}'
          '${srv.dialStore.kind == 'memory' ? ' (set APPBOX_SUPABASE_URL + APPBOX_SUPABASE_SERVICE_KEY, or ~/.appbox/supabase, for the shared store)' : ''}');
    }
    // Let SocketException propagate (EADDRINUSE/EACCES) — designServe maps it
    // via bindExitCode; tests assert the bind path directly.
    srv._http = await HttpServer.bind(_bindAddress(host), port);
    // After bind, because the allowlist is keyed on the REAL port (`--port 0`
    // and every test ask the OS for one).
    srv.trust = BrowserTrust(
      boundHost: host,
      port: srv._http.port,
      trustedHosts: trustedHosts,
      trustedOrigins: trustedOrigins,
    );
    if (srv.trust.wildcardBind) stderr.writeln(BrowserTrust.wildcardWarning);

    // `dart:io` puts `X-Frame-Options: SAMEORIGIN` in
    // `HttpServer.defaultResponseHeaders` on its own — it is in no source file
    // here, so grepping for it finds nothing while every response carries it.
    // It refused the arxa design panel and the `gen_ui` RungLadder, which
    // frame us cross-origin. There is no allowlist form of that header
    // (`ALLOW-FROM` is obsolete and makes browsers ignore it entirely), so it
    // goes and CSP `frame-ancestors` takes over in the same breath — dropping
    // it alone would let ANY page frame this server.
    //
    // Set on defaultResponseHeaders rather than in `_handle` so a route that
    // returns early cannot ship a document without the policy.
    srv._http.defaultResponseHeaders
      ..removeAll('x-frame-options')
      ..set('Content-Security-Policy',
          'frame-ancestors ${srv.trust.frameAncestors}');
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

      // The browser-trust gate, ahead of every route: a request that failed it
      // must not reach a handler, and Host checking has to cover the static
      // and artifact paths too (rebinding reads whatever it can get). Plain
      // text, not the localized error surface — this answer goes to an
      // attacker's page far more often than to a person.
      final verdict = trust.check(
        method: method,
        path: path,
        host: req.headers.value(HttpHeaders.hostHeader),
        origin: req.headers.value('Origin'),
        secFetchSite: req.headers.value('Sec-Fetch-Site'),
      );
      if (!verdict.allowed) {
        // Name the caller in the log — a refusal that does not say WHO was
        // refused cannot be told apart from an attack or a misconfigured
        // first-party client without packet capture.
        stderr.writeln('[design-server] refused $method $path '
            '(origin=${req.headers.value('Origin')}, '
            'sec-fetch-site=${req.headers.value('Sec-Fetch-Site')}, '
            'dest=${req.headers.value('Sec-Fetch-Dest')}, '
            'referer=${req.headers.value('Referer')}): '
            '${verdict.reason}');
        // Opaque-origin READS (origin literally "null" — a sandboxed mirror
        // frame whose island predates its quiet-mirror boot, or any stray
        // viewer) get a CORS-CLEAN empty 200 instead of an error status:
        // Chrome logs every non-2xx fetch as a console line no JS can
        // suppress, which read as "sync is broken" even though the frame
        // was inert by design. The body carries nothing; writes and every
        // named origin keep the full refusal.
        final originHeader = req.headers.value('Origin');
        if (method == 'GET' &&
            (originHeader == null || originHeader == 'null')) {
          req.response.statusCode = 200;
          req.response.headers
            ..contentType = ContentType.parse('application/json; charset=utf-8')
            ..set('Access-Control-Allow-Origin', '*');
          req.response.write('{"mirror":true}');
          await req.response.close();
          return;
        }
        req.response.statusCode = verdict.status;
        req.response.headers.contentType =
            ContentType.parse('text/plain; charset=utf-8');
        req.response.write(verdict.reason);
        await req.response.close();
        return;
      }
      if (verdict.corsOrigin != null) {
        // Echo the one matched origin, never `*`, and no
        // Access-Control-Allow-Credentials at all — nothing here is
        // authenticated by cookie, so granting credentialed access would only
        // widen the blast radius of a mistake in the allowlist.
        req.response.headers
          ..set('Access-Control-Allow-Origin', verdict.corsOrigin!)
          ..add('Vary', 'Origin');
      }

      // Every `return` in this try is `return await` on purpose. `return f();`
      // inside a try hands the future back before it completes, so the catch
      // below never sees its error — it escapes as an unhandled async error and
      // takes the server process down instead of producing a 500. That is how a
      // dead worker turned one bad request into a dead studio (task #64).
      if (path == '/__worker_page') {
        return await _serveFile(req,
            p.join(_workerAssetsDir, 'worker_page.html'),
            'text/html; charset=utf-8');
      }
      if (path.startsWith('/__worker_assets/')) {
        final rel = Uri.decodeComponent(path.substring('/__worker_assets/'.length));
        return await _serveFile(
            req, p.join(_workerAssetsDir, rel), _contentType(rel),
            root: _workerAssetsDir);
      }
      // The live-reload stream. Answered HERE, ahead of everything that can
      // touch the worker: it needs no worker, so it must not queue behind a
      // reload — a subscriber that got a 503 during the very reload it was
      // subscribed to hear about would be the one request in the server that
      // cannot afford the reload gate.
      if (method == 'GET' && path == '/__events') {
        _openEventStream(req);
        return;
      }
      if ((method == 'GET' || method == 'POST') && path == '/prefs/lang') {
        return await _handlePrefsLang(req);
      }
      // Project write channel (the studio edits the current project): the JS
      // worker POSTs {path, body}; the write is confined to the project dir.
      if (method == 'POST' && path == '/__project_write') {
        return await _handleProjectWrite(req);
      }
      // The Design Dial API + event stream (design_dial.dart). The stream is
      // answered ahead of the API for the same reason /__events is: a
      // subscriber must never queue behind work it is waiting to hear about.
      if (dialEnabled && path.startsWith('/__dial')) {
        if (method == 'GET' && path == '/__dial/events') {
          _openDialEventStream(req);
          return;
        }
        return await _handleDial(req, method, path);
      }
      // The dashboard's live project grid: every project in ~/.appbox with
      // its derived stage + honest output counts.
      // GET /__routes -> {"routes":[{"method":"GET","path":"/design"}, …]}
      //
      // Design-agnostic route discovery for the contract probe suite (task
      // #21): a contract probe asserts the appbox opinion against ANY served
      // design, so it cannot hard-code `/design` or `/intake` — it has to ask
      // the design what it serves.
      //
      // This exposes [_routeTable], which the server already resolved once at
      // boot from `_worker.routes()`. Two alternatives were rejected on
      // evidence:
      //   - parsing the served `app.routes.js` from Dart: its default export
      //     is assembled from imports and spreads (`...appRoutes`), so reading
      //     it means re-implementing JS module evaluation that the worker
      //     already performed to build this very table. Two parsers for one
      //     fact is the duplication this consolidation exists to remove.
      //   - keying off `registry.json`: the `hello-hda` example has none, and
      //     the contract suite must pass against it to prove it is not
      //     studio-specific. That option fails the acceptance bar by
      //     construction.
      //
      // Read-only introspection, same family as /__projects.
      if (method == 'GET' && path == '/__routes') {
        req.response.headers.contentType =
            ContentType.parse('application/json; charset=utf-8');
        req.response.write(jsonEncode({
          'routes': [
            for (final r in _routeTable)
              if (r.length >= 2) {'method': r[0], 'path': r[1]},
          ],
        }));
        await req.response.close();
        return;
      }
      if (method == 'GET' && path == '/__projects') {
        req.response.headers.contentType =
            ContentType.parse('application/json; charset=utf-8');
        req.response.write(jsonEncode({
          'current': currentProject(),
          // `current` is a live read of the GLOBAL ~/.appbox/current marker,
          // which is NOT this process's project: a server started with
          // --project never touches the marker, and any other process can flip
          // it while this one stays bound underneath. Anything asking "what
          // would a write here actually hit?" must not use it — the probe
          // guard (task #63) did, and therefore passed in precisely the case
          // it existed to prevent.
          //
          // `boundProject` is that fact: the project resolved ONCE at boot
          // (--project > APPBOX_PROJECT > the marker as it stood then) and
          // held in projectRoot. null means no project is bound and the server
          // is serving the artifact alone.
          'boundProject':
              projectRoot == null ? null : p.basename(projectRoot!),
          'projects': projectCards(),
        }));
        await req.response.close();
        return;
      }
      // Point `current` at another project (the overlay itself rebinds on the
      // next serve — the marker + grid update immediately).
      if (method == 'POST' && path == '/__project_use') {
        // Same guard as _handleProjectWrite: a body the client got wrong is a
        // 400, not a 500. Unguarded, jsonDecode threw on a malformed body and
        // the cast threw on valid-but-non-object JSON (null, [], "x") — both
        // landed in the catch-all and were reported as a server fault.
        final Map<String, dynamic> payload;
        try {
          payload = jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>;
        } catch (_) {
          req.response.statusCode = 400;
          req.response.headers.contentType =
              ContentType.parse('application/json; charset=utf-8');
          req.response.write(jsonEncode({'ok': false, 'error': 'bad JSON body'}));
          await req.response.close();
          return;
        }
        final name = (payload['name'] ?? '').toString();
        try {
          useProject(name);
        } on ArgumentError catch (e) {
          // e.message here is authored prose from project.dart (`no such
          // project: …`), not a raw error object — safe on the wire. It only
          // ever lacked a content type.
          req.response.statusCode = 404;
          req.response.headers.contentType =
              ContentType.parse('text/plain; charset=utf-8');
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
        return await _dispatch(req, method, path);
      }
      if (path.startsWith('/assets/vendor/')) {
        final rel = Uri.decodeComponent(path.substring('/assets/vendor/'.length));
        return await _serveFile(req, p.join(_vendorDir, rel), _contentType(rel),
            root: _vendorDir);
      }
      if (method == 'GET' && _tryServeArtifactFile(req, path)) return;

      // The artifact's own not-found surface. A design that registers a
      // GET /unknown route (the '<shell>.unknown' surface — e.g.
      // appbox-studio's app.unknown) has authored where a whole-page miss
      // should land, so render THAT under a 404 by dispatching internally to
      // its registered route. Fragment (htmx) misses fall through to the
      // toast retarget below: a retargeted panel fragment must not be a whole
      // page. An artifact with no such route gets the server's own error
      // page, exactly as before.
      if (method == 'GET' &&
          !_isHtmx(req) &&
          _matchRoute('GET', '/unknown') != null) {
        return await _dispatch(req, method, path,
            dispatchPath: '/unknown', statusOverride: 404);
      }

      await _writeError(req, 404, 'errorSurface.notFound', _msgNotFound,
          vars: {'method': method, 'path': path});
    } catch (e, st) {
      // The full detail — exception AND stack — is for the serve log only.
      stderr.writeln('[design-server] $e\n$st');
      try {
        await _writeError(
            req, 500, 'errorSurface.serverError', _msgServerError);
      } catch (_) {
        // Headers already went out (a mid-stream _serveFile, say). Nothing
        // left to say on this socket.
      }
    }
  }

  /// True when htmx issued this request (a fragment fetch or a boosted nav)
  /// rather than the browser loading a whole page.
  static bool _isHtmx(HttpRequest req) =>
      req.headers.value('HX-Request') != null;

  /// The user-facing error channel. What lands on the wire is always a HUMAN
  /// message — never a raw error object (the bad-state leak; see
  /// blueprint.dart:589).
  ///
  /// [key] is looked up in the ARB catalogs for the request's resolved locale
  /// (task #46); [fallbackEn] is the authored English used when the key is
  /// absent or a catalog is unreadable, so the worst case is exactly the
  /// pre-l10n behaviour rather than a raw key on screen.
  ///
  /// htmx is configured (ui/common/base.tsx) to retarget 404/5xx into the
  /// always-rendered `#toasts` tray; the blanket 4xx rule is swap:none, so an
  /// error can never overwrite a good panel. A full-page request gets a real
  /// page instead of a bare string.
  ///
  /// `Vary: Accept-Language` joins `Vary: HX-Request` now that the body depends
  /// on the negotiated locale — without it a cache would serve one visitor's
  /// language to the next.
  ///
  /// [detail] appends a raw diagnosis (e.g. the esbuild stderr for a broken
  /// TSX bundle) — developer-facing, never localized, escaped like the message.
  Future<void> _writeError(
    HttpRequest req,
    int status,
    String key,
    String fallbackEn, {
    Map<String, String> vars = const {},
    String? detail,
  }) async {
    final headers = _headerMap(req);
    final prefs = _parsePrefs(_parseCookies(headers)['kdh_prefs']);
    final locale = _resolveLocale(
        locales, req.uri.queryParameters, prefs, headers['accept-language'],
        path: req.uri.path);
    final cat = _errorCatalog;
    var message = cat.t(locale, key, fallbackEn, vars);
    if (detail != null) message = '$message — $detail';

    req.response.statusCode = status;
    req.response.headers.contentType =
        ContentType.parse('text/html; charset=utf-8');
    req.response.headers.add('Vary', 'HX-Request');
    req.response.headers.add('Vary', 'Accept-Language');
    req.response.write(_isHtmx(req)
        ? _errorToast(
            message, cat.t(locale, 'errorSurface.dismiss', _msgDismiss))
        : _errorPage(
            status,
            message,
            locale,
            cat.t(locale, 'errorSurface.pageHint', _msgErrorHint),
            cat.t(locale, 'errorSurface.backHome', _msgBackHome)));
    await req.response.close();
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

  /// [dispatchPath] forwards the request to a DIFFERENT worker route than the
  /// one asked for (the 404 catch-all rendering the artifact's `/unknown`
  /// surface); [statusOverride] pins the wire status regardless of what the
  /// handler answered, because that surface's own route correctly answers 200
  /// while a miss must say 404.
  Future<void> _dispatch(HttpRequest req, String method, String path,
      {String? dispatchPath, int? statusOverride}) async {
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
    final prefs = _parsePrefs(cookies['kdh_prefs']);
    final locale = _resolveLocale(
        locales, req.uri.queryParameters, prefs, headers['accept-language'],
        path: req.uri.path);
    // SERIALIZED PER SESSION (task #55). Everything from reading the session to
    // writing it back is one critical section, because it is a read-modify-write
    // spanning an await and concurrent requests on one session were silently
    // losing each other's writes — measured at 1 of 8 surviving.
    //
    // The trigger is ordinary studio use, not a stress test: every tile in the
    // canvas is an iframe, `/build/screens/:surface` is a real route (not a
    // static file), and one stage re-render fans out into ~20 concurrent GETs
    // carrying the same session cookie. A canvas mutation pushes onto
    // undoStacks.canvas and returns; the iframe requests already in flight then
    // write back their older snapshot and erase the push. Undo afterwards pops
    // nothing, so redo never enables — while the mutation itself already
    // reached disk. That is #55's "redo never re-enabled" plus its data loss.
    //
    // The body read above stays OUTSIDE the lock deliberately: a slow client
    // must not be able to hold a session's lock while it dribbles out a body.
    // Task #19: never dispatch into a worker whose route table is empty
    // because a reload is in flight — see [JsWorker.reloadInFlight], which is
    // the one signal for BOTH reload paths: the watcher's, and the self-heal
    // reboot `JsWorker.dispatch` performs when it finds a lost realm. Tracking
    // it here instead would only ever see the watcher's, so a self-heal reboot
    // would leave concurrent requests 404ing exactly as before.
    //
    // Deliberately OUTSIDE the session lock: a reload is process-wide, and
    // holding one session's lock while waiting on it would serialize that
    // session behind a wait it has nothing to do with.
    //
    // This defers; it does not translate. A route that genuinely does not
    // exist still reaches the worker and still answers 404 — after the wait,
    // not instead of it — so the deferral cannot mask a real routing bug.
    final reloading = _worker.reloadInFlight;
    if (reloading != null) {
      final settled = await reloading
          .timeout(_reloadGrace)
          .then((_) => true, onError: (_) => false);
      if (!settled) {
        stderr.writeln('[design-server] $method ${req.uri.path}: waited '
            '${_reloadGrace.inMilliseconds}ms for a hot reload that has not '
            'finished — answering 503 rather than a 404 from an empty route table');
        await _writeError(req, 503, 'errorSurface.reloading', _msgReloading);
        return;
      }
    }

    // A TSX syntax error breaks the render bundle, not the studio: every
    // route answers with the esbuild diagnosis on the 5xx surface (toast for
    // htmx, page otherwise) until a save rebuilds clean — stderr alone is
    // invisible (M9).
    final bundleError = _worker.bundleError;
    if (bundleError != null) {
      await _writeError(req, 500, 'errorSurface.serverError', _msgServerError,
          detail: bundleError);
      return;
    }

    final resp = await _withSessionLock(sid, () async {
      final sessionData = Map<String, dynamic>.from(_sessions[sid] ?? {});
      final state = <String, dynamic>{
        'locale': locale,
        'session': {'id': sid, 'data': sessionData},
        // Only THIS session's timers cross into the worker. Sending the whole
        // map meant a viewmodel could read a timer belonging to someone else.
        'timers': Map<String, dynamic>.from(_timers[sid] ?? const {}),
      };
      final r = await _worker.dispatch(method, dispatchPath ?? req.uri.toString(),
          headers: headers, body: body, state: state);
      if (r.session != null) {
        _sessions[sid!] =
            Map<String, dynamic>.from(r.session!['data'] as Map? ?? {});
      }
      // Store back under this session only. The old `_timers..clear()..addAll()`
      // replaced the process-wide map on every single response, so two browsers
      // using the studio at once destroyed each other's timers continuously.
      _timers[sid!] = Map<String, dynamic>.from(r.timers);
      return r;
    });

    req.response.statusCode = statusOverride ?? resp.status;
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
    var respBody = resp.body;
    // Design-time eager islands (M10): every full HTML page gets the eager
    // loader — hx-island-when conditions are ignored, islands init on boot —
    // so a lens check sees the real island, not the inert pre-condition
    // markup. Full documents only: a fragment carries no shell, and the
    // loader's MutationObserver arms islands swapped in later. The ejected
    // app never passes through here; its lazy loader is untouched.
    if (respBody != null &&
        (resp.headers['content-type'] ?? '').contains('text/html') &&
        respBody.contains('</body>')) {
      respBody = respBody.replaceFirst(
          '</body>',
          '<script type="module" src="/__worker_assets/islands_eager.js">'
          '</script></body>');
      // The Design Dial (locked amendment 2026-08-23): baked into every full
      // page of every artifact — never fragments (no shell), never the ejected
      // app (its own runtime injects). A valid ?dial= token flips the island
      // into guest mode (the Share Link preview); an INVALID token still
      // boots guest mode but flagged, so the island can say 'this link is
      // dead' instead of silently being the author. Full documents only.
      if (dialEnabled) {
        final dialToken = req.uri.queryParameters['dial'];
        final grant = dialToken == null
            ? null
            : await dialStore.resolveShareLink(dialToken);
        // Design Mode's Draft Overlay (decision 5): the Author's page carries
        // the uncommitted patch set; any ?dial= path — guest or dead link —
        // gets the last published state, i.e. source as-is. Stale and
        // refused patches are reported through GET /__dial/draft consumers,
        // not per-request stderr.
        final ds = draftStore;
        if (dialToken == null && ds != null) {
          final draft = await ds.load();
          if (draft != null && !draft.isEmpty) {
            respBody = draft.apply(respBody).html;
          }
        }
        final config = jsonEncode({
          'v': 1,
          'artifact': _dialArtifact,
          'store': dialStore.kind,
          'mode': dialToken == null
              ? 'author'
              : (grant == null ? 'invalid' : 'guest'),
          if (grant != null) 'token': dialToken,
        });
        respBody = respBody.replaceFirst(
            '</body>',
            '<script type="application/json" id="arxa-dial-config">'
            '$config</script>'
            '<script src="/assets/vendor/dial_island.js"></script></body>');
      }
    }
    // Scrollbars are the preview harness showing through, not the design.
    // Injected ONLY for a framed navigation, so opening the same URL in a tab
    // is untouched and still scrolls with visible bars.
    //
    // This has to happen HERE, in the server: the arxa design panel and the
    // `gen_ui` RungLadder both frame us cross-origin, so neither can reach
    // this document's stylesheets. `Sec-Fetch-Dest` is a forbidden header
    // name — page script cannot set or strip it — and the browser sends
    // `iframe` only on the frame's own navigation, never on its sub-resources,
    // so this lands on the document and nothing else.
    //
    // Both properties are needed and neither breaks scrolling: `scrollbar-width`
    // is the standard one, `::-webkit-scrollbar` covers engines that predate it.
    // `*` rather than `html` because the bars that show up in a scaled preview
    // come from the design's own inner scrollers (carousels, overflow panes),
    // not from the root.
    if (respBody != null &&
        (resp.headers['content-type'] ?? '').contains('text/html') &&
        req.headers.value('Sec-Fetch-Dest') == 'iframe' &&
        respBody.contains('</head>')) {
      // HEAD, not body: these pages run hx-boost, whose swap replaces body
      // innerHTML - a body-mounted style dies on the first in-site
      // navigation and the preview scrollbars come back mid-session.
      respBody = respBody.replaceFirst('</head>', '$_kFramedCss</head>');
    }
    if (respBody != null) req.response.add(utf8.encode(respBody));
    await req.response.close();
  }

  /// Hides scrollbars without disabling scrolling, for a framed preview.
  static const String _kFramedCss = '<style id="__appbox_framed">'
      '*{scrollbar-width:none!important}'
      '*::-webkit-scrollbar{width:0!important;height:0!important}'
      '</style>';

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
    // These two serve assets (/assets/vendor/*, artifact files), never htmx
    // targets — so they stay plain text, not the HTML surface. They were
    // silent (empty body, no content type), which is not the same defect as
    // leaking; the path is deliberately NOT echoed back.
    if (root != null && !_isInside(root, absPath)) {
      req.response.statusCode = 403;
      req.response.headers.contentType =
          ContentType.parse('text/plain; charset=utf-8');
      req.response.write('403 — outside the served root');
      await req.response.close();
      return;
    }
    if (!f.existsSync()) {
      req.response.statusCode = 404;
      req.response.headers.contentType =
          ContentType.parse('text/plain; charset=utf-8');
      req.response.write('404 — no such file');
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType.parse(contentType);
    await req.response.addStream(f.openRead());
    await req.response.close();
  }

  // Both watchers debounce into here. The reload stays unawaited — a watcher
  // that blocked for the ~850ms of a reboot would coalesce the next save into
  // this one — but unawaited is not the same as unwatched: a reload that throws
  // (the worker's Chrome died) is an unhandled async error, and one raised from
  // a Timer callback has no handler anywhere above it, so it terminates the
  // whole server. Saving a file could kill the studio outright, entirely
  // independently of any request (task #64). Report it and keep serving; the
  // next request through JsWorker.dispatch reboots the worker anyway.
  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (_stopped) return;
      unawaited(_reloadAndRefreshRoutes().catchError((Object e) {
        stderr.writeln('[design-server] hot reload failed: $e');
      }));
    });
  }

  /// Reload the worker, then re-register the route table from the reloaded
  /// `app.routes.js`. The table is data derived from the artifact, exactly like
  /// the served views — a reload that renames or adds a route path would
  /// otherwise leave the server matching the boot-time table, 404ing the new
  /// path until a human restarts the process (observed live: renaming
  /// `POST /prefs/accent` to `POST /preferences/accent` hot-reloaded the view
  /// but the route stayed dead). Refresh AFTER the reload settles so the table
  /// and the module cache always describe the same artifact generation.
  Future<void> _reloadAndRefreshRoutes() async {
    await _worker.reload();
    if (_stopped) return;
    _routeTable = await _worker.routes();
    // Only after the table refreshes: a subscriber that remounts on this
    // signal must find the NEW routes already registered, or it races the
    // 404 window this very ordering exists to close.
    _broadcastReload();
  }

  // ── the Design Dial (GET/POST /__dial/*, GET /__dial/events) ────────────
  // The adapter between the wire and DialApi's pure core: read the body,
  // resolve the caller (a valid ?dial= token makes a guest; anything else on
  // loopback is the Author — see browser_trust.dart), call, answer JSON.
  // Every mutation broadcasts on the dial stream so open dials repaint.

  Future<void> _handleDial(HttpRequest req, String method, String path) async {
    final sub = path.substring('/__dial'.length); // includes leading /
    Map<String, dynamic>? body;
    if (method == 'POST' || method == 'PUT' || method == 'PATCH') {
      final raw = await utf8.decoder.bind(req).join();
      if (raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          body = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
        } catch (_) {
          body = null; // malformed JSON → DialApi's 400 via _map
        }
      }
    }
    final token = req.uri.queryParameters['dial'];
    final grant = token == null ? null : await dialStore.resolveShareLink(token);
    final r =
        await dialApi.handle(method, sub, req.uri.queryParameters, body, grant);
    req.response.statusCode = r.status;
    req.response.headers.contentType =
        ContentType.parse('application/json; charset=utf-8');
    req.response.write(jsonEncode(r.json));
    await req.response.close();
    // Broadcast AFTER the answer so the writer's own repaint races nothing.
    // MUTATIONS ONLY: a GET /pins broadcast made every subscriber refetch,
    // and that refetch broadcast again — a self-sustaining storm (measured
    // 2026-08-24: 6 pins GETs per rung within seconds of boot) that held the
    // browser's per-host socket pool busy enough to starve real edits and
    // leave sibling rungs stale.
    if (r.status < 300 &&
        method != 'GET' &&
        (sub == '/pins' || sub == '/pins/status' || sub == '/pins/reply')) {
      _broadcastDial();
    }
    if (r.status < 300 && sub == '/draft' && method != 'GET') {
      _broadcastDial('draft');
    }
    if (r.status < 300 && sub == '/commit') {
      _broadcastDial('commit', r.json);
    }
  }

  void _openDialEventStream(HttpRequest req) {
    final res = req.response;
    res.statusCode = 200;
    res.headers
      ..contentType = ContentType.parse('text/event-stream; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache, no-store, no-transform')
      ..set('X-Accel-Buffering', 'no')
      ..set('X-Content-Type-Options', 'nosniff');
    res.bufferOutput = false;
    _push(res, 'retry: 500\n\n');
    _push(res, ': dial subscribed\n\n');
    _dialEventClients.add(res);
    unawaited(res.done
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() {
      _dialEventClients.remove(res);
      _maybeStopEventHeartbeat();
    }));
    _ensureEventHeartbeat();
    // Held open; never closed here — the response IS the subscription.
  }

  /// [kind] tells subscribers what changed: 'pins' (feedback store), 'draft'
  /// (the Author's overlay), 'commit' (a commit request — [data] carries the
  /// ops payload the studio agent consumes).
  void _broadcastDial([String kind = 'pins', Object? data]) {
    if (_dialEventClients.isEmpty) return;
    final frame = 'event: dial\ndata: ${jsonEncode({
      'kind': kind,
      'data': ?data,
    })}\n\n';
    for (final c in _dialEventClients.toList()) {
      _push(c, frame);
    }
  }

  // ── the live-reload stream (GET /__events) ───────────────────────────────
  // Server-Sent Events rather than a WebSocket: the traffic is one-way and
  // tiny, EventSource reconnects on its own, and it rides the HttpServer this
  // file already has. The subscriber is the arxa design panel, which cannot
  // see the artifact's file watcher from another origin — before this it had
  // only a manual remount button.

  /// Held-open responses, one per subscriber.
  final _eventClients = <HttpResponse>{};

  /// One timer for all subscribers, alive only while at least one is.
  Timer? _heartbeat;

  /// How often a comment frame goes out.
  ///
  /// It does two jobs, and the second is the load-bearing one. Obviously it
  /// keeps an idle socket from being reaped. Less obviously it is the ONLY way
  /// this server learns a subscriber left: dart:io surfaces a dead peer as an
  /// error on `HttpResponse.done`, and that error is raised by a WRITE — an
  /// idle held-open response never notices the client vanished. So the
  /// heartbeat is also the reaper, and a departed subscriber sits in the set
  /// until the next one or two fire. Injectable because 20s is far too long
  /// for a test to sit through.
  late final Duration _eventHeartbeat;

  /// Monotonic per-process counter, so a client that missed a frame can still
  /// tell that something happened rather than comparing timestamps.
  int _generation = 0;

  /// Subscribers right now (test-only assertion seam).
  int get eventSubscribersForTest => _eventClients.length;

  void _openEventStream(HttpRequest req) {
    final res = req.response;
    res.statusCode = 200;
    res.headers
      ..contentType = ContentType.parse('text/event-stream; charset=utf-8')
      // no-transform matters as much as no-cache: a proxy that "helpfully"
      // compresses or rebuffers an event stream holds every frame until it has
      // enough bytes, which looks exactly like a server that never fires.
      ..set(HttpHeaders.cacheControlHeader, 'no-cache, no-store, no-transform')
      // nginx's own buffering, which the Cache-Control hint does not reach.
      ..set('X-Accel-Buffering', 'no')
      ..set('X-Content-Type-Options', 'nosniff');
    // dart:io buffers response bytes by default and flushes when the buffer
    // fills or the response closes — neither of which an event stream ever
    // does. Without this the connection opens, stays open, and delivers
    // nothing.
    res.bufferOutput = false;
    // Reconnect fast: this is loopback, and the gap that matters is the one
    // where the server restarted and the panel is showing a dead frame.
    _push(res, 'retry: 500\n\n');
    _push(res, ': subscribed\n\n');
    _eventClients.add(res);
    _ensureEventHeartbeat();
    // `done` completes with an ERROR when the peer vanishes (a closed panel,
    // the normal case), so both arms have to drop the subscriber or a dead
    // socket stays in the set and every later heartbeat throws on it.
    unawaited(res.done
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _dropEventClient(res)));
    // Deliberately not awaited and never closed here: the response IS the
    // subscription.
  }

  void _push(HttpResponse res, String frame) {
    try {
      res.write(frame);
    } catch (_) {
      // Writing to a socket the peer already dropped. `done` will fire too,
      // but not necessarily before the next frame.
      _dropEventClient(res);
    }
  }

  /// The one heartbeat for BOTH event streams (reload + dial). Its writes
  /// keep idle sockets from being reaped and — load-bearing — are the only
  /// way a departed subscriber surfaces: the write throws, the set reaps.
  void _ensureEventHeartbeat() {
    _heartbeat ??= Timer.periodic(_eventHeartbeat, (_) {
      // A comment frame — legal SSE, ignored by EventSource.
      for (final c in _eventClients.toList()) {
        _push(c, ': keep-alive\n\n');
      }
      for (final c in _dialEventClients.toList()) {
        _push(c, ': keep-alive\n\n');
      }
    });
  }

  void _dropEventClient(HttpResponse res) {
    _eventClients.remove(res);
    _maybeStopEventHeartbeat();
  }

  void _maybeStopEventHeartbeat() {
    if (_eventClients.isEmpty && _dialEventClients.isEmpty) {
      // A live Timer.periodic keeps the Dart VM alive; leaving one running
      // would stop this server's own test suite from ever exiting.
      _heartbeat?.cancel();
      _heartbeat = null;
    }
  }

  void _broadcastReload() {
    if (_eventClients.isEmpty) return;
    _generation++;
    final frame = 'event: reload\ndata: {"generation":$_generation}\n\n';
    for (final c in _eventClients.toList()) {
      _push(c, frame);
    }
  }

  void _startWatcher(String dir) {
    try {
      _watcherSub = Directory(dir).watch(recursive: true).listen((e) {
        if (_ignoreRe.hasMatch(e.path)) return;
        _scheduleReload();
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
        _scheduleReload();
      });
    } catch (_) {
      // watch unsupported — hot reload simply disabled.
    }
  }

  /// Reload the worker now (used by tests; production uses the file watcher).
  /// Same contract as the watcher path: routes re-register with the reload.
  Future<void> reload() => _reloadAndRefreshRoutes();

  /// Put the worker tab into the lost-realm state task #51 recovers from.
  /// Test-only; see [JsWorker.breakDispatchForTest].
  Future<void> breakWorkerForTest() => _worker.breakDispatchForTest();

  /// Test-only; see [JsWorker.reloadRunsForTest].
  int get workerReloadRunsForTest => _worker.reloadRunsForTest;

  /// Test-only; see [JsWorker.bundleError].
  String? get workerBundleErrorForTest => _worker.bundleError;

  /// Kill the worker's browser, the state task #64 recovers from.
  /// Test-only; see [JsWorker.killChromeForTest].
  bool killWorkerChromeForTest() => _worker.killChromeForTest();

  /// Test-only; see [JsWorker.breakRelaunchForTest].
  void breakWorkerRelaunchForTest() => _worker.breakRelaunchForTest();

  /// Test-only; see [JsWorker.relaunchRunsForTest].
  int get workerRelaunchRunsForTest => _worker.relaunchRunsForTest;

  /// The worker's pid right now. [workerPid] is the one captured at boot and
  /// reported in the startup JSON; this one follows a browser replacement.
  int get currentWorkerPid => _worker.workerPid;

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _debounce?.cancel();
    await _watcherSub?.cancel();
    await _projectWatcherSub?.cancel();
    _heartbeat?.cancel();
    _heartbeat = null;
    for (final c in _eventClients.toList()) {
      try {
        await c.close();
      } catch (_) {
        // Peer already gone; `_http.close(force: true)` gets the socket.
      }
    }
    _eventClients.clear();
    for (final c in _dialEventClients.toList()) {
      try {
        await c.close();
      } catch (_) {}
    }
    _dialEventClients.clear();
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
        '[--port N] [--host H] [--json] [--no-watch] [--no-dial]\n'
        '       [--trusted-host NAME]…   extra Host names to answer to\n'
        '       [--trusted-origin URL]…  origins allowed to call /__* '
        'cross-origin (e.g. a studio panel)\n'
        '       …or list them one per line in '
        '${p.join(appboxHome(), kTrustedOriginsFile)}');
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
  // Take over from the instance we are actually replacing — same artifact dir
  // AND same port — and nothing else. Guarded on `a.port != 0` because port 0
  // means "any free port": there is no incumbent to replace, and matching on a
  // recorded 0 would make every ephemeral-port server a sibling of every other,
  // which is the global-kill bug this task exists to remove.
  if (!a.noWatch && a.port != 0) {
    // stderr, not stdout: `--json` makes stdout a machine-readable stream (see
    // the ready record below), and a prose line in front of it breaks every
    // consumer parsing it. stderr keeps the human told in EVERY mode, which is
    // the whole point of announcing — and matches how this file already routes
    // diagnostics.
    final replaced = sweepSiblingInstances(_osPid, resolved.dir,
        port: a.port, announce: stderr.writeln);
    // The incumbent's signal handler disposes a worker and reaps a Chrome tree
    // before it releases the socket, so the port is NOT free the instant the
    // signal is delivered. Binding on the same tick raced it and surfaced as a
    // spurious exit 69. Bounded: if it never frees, fall through and let the
    // bind below report "already in use" honestly.
    if (replaced.isNotEmpty) await _awaitPortFree(a.host, a.port);
  }

  try {
    srv = await DesignServer.start(
      artifactDir: resolved.dir,
      port: a.port,
      host: a.host,
      noWatch: a.noWatch || a.worker,
      projectDir: resolvedProject,
      trustedHosts: a.trustedHosts,
      // Read here, not in _parseArgs: arg parsing stays free of file IO, so
      // the CLI tests never depend on the operator's home directory.
      trustedOrigins: [...readTrustedOriginsFile(), ...a.trustedOrigins],
      dial: a.dial,
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
    // Register the BOUND port (srv.port), not the requested one — with `--port 0`
  // the requested value is a placeholder and the bound value is the identity.
  registerServeInstance(srv.pid, srv.artifactDir, port: srv.port);
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
        url: srv.url,
        host: srv.host,
        artifactDir: srv.artifactDir,
        port: srv.port)) {
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

  // Every catchable exit must reach shutdown() — that is what disposes the
  // worker and reaps its Chrome tree. Measured before this change: SIGTERM
  // exited clean, SIGHUP and SIGKILL each orphaned a Chrome. SIGHUP was
  // unhandled entirely, so closing the terminal leaked a tree every time,
  // and SIGINT was only wired under `!noWatch`, so `--no-watch` + ^C leaked
  // the same way. SIGKILL is uncatchable by definition — _ChromeHandle
  // sweeps those leftovers at the next boot.
  //
  // Only SIGINT sweeps siblings, and the sweep is scoped to this artifact dir
  // ON THIS PORT — a duplicate of exactly this instance, nothing else. It must
  // NOT spread to SIGTERM/SIGHUP, which stop just this one.
  final intSub = ProcessSignal.sigint.watch().listen((_) {
    if (!a.noWatch) {
      sweepSiblingInstances(srv.pid, srv.artifactDir,
          port: srv.port, announce: stderr.writeln);
    }
    shutdown(0);
  });
  final termSub = ProcessSignal.sigterm.watch().listen((_) => shutdown(0));
  final hupSub = ProcessSignal.sighup.watch().listen((_) => shutdown(0));

  final code = await completer.future;
  await termSub.cancel();
  await intSub.cancel();
  await hupSub.cancel();
  return code;
}

// ── ready output (extracted for testing the --host 0.0.0.0 warning) ────────
List<String> humanReadyLines(
    {required String url,
    required String host,
    required String artifactDir,
    required int port}) {
  final out = <String>[
    'appbox-designer serving $artifactDir',
    '→ $url',
  ];
  if (host == '0.0.0.0' || host == '::') {
    out.add('  (bound to every interface — reachable from your network)');
  }
  // Says what is actually true after task #69. The old line promised "stops
  // every instance of this design", and the implementation delivered something
  // even broader than that overclaim — it stopped every design server running,
  // because the key ignored the port and every server here serves the same dir.
  // The scope is now one instance, identified by dir AND port, so the banner
  // names the port too.
  out.add('  watching for changes — Ctrl+C stops this server, and any other '
      'instance of this design on port $port');
  return out;
}

/// Wait (bounded) for [port] to become bindable again after the instance
/// holding it was signalled. See the call site in [serve]: the incumbent tears
/// down a Chrome tree before releasing the socket, so "signal delivered" is not
/// "port free", and racing that produced a spurious exit 69.
Future<void> _awaitPortFree(String host, int port,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final s = await ServerSocket.bind(host, port);
      await s.close();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
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

/// The l10n directories the error surface reads, in precedence order (project
/// last, so a project's catalog wins) — the same pair [_scanLocales] scans, so
/// a locale that resolves is always a locale the catalog can be read for.
List<String> _l10nDirs(String artifactDir, {String? projectDir}) => [
      p.join(artifactDir, 'l10n'),
      if (projectDir != null) p.join(projectDir, 'design', 'l10n'),
    ];

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

/// Locale resolution: path prefix → ?lang= → prefs.lang → Accept-Language →
/// 'en'. The path is checked FIRST (the locale-route convention: /, /fr, /mfe -
/// the URL itself is the most explicit signal, ahead of every ambient cue),
/// and only when the leading segment names a declared locale; unknown
/// segments fall through untouched, so a route that happens to collide
/// with a locale code never gets hijacked silently.
String _resolveLocale(Set<String> locales, Map<String, String> query,
    Map<String, dynamic> prefs, String? acceptLanguage, {String? path}) {
  if (locales.isEmpty) return 'en';
  if (path != null && path != '/' && path.length > 1) {
    final seg = path.substring(1).split('/').first;
    if (seg.isNotEmpty && locales.contains(seg)) return seg;
  }
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

/// Record this instance. [port] is the BOUND port, not the requested one —
/// `--port 0` asks the OS for any free port, and a registry full of entries
/// all claiming port 0 would collide with each other exactly the way the
/// artifactDir-only key used to (see [sweepSiblingInstances]).
void registerServeInstance(int pid, String artifactDir, {required int port}) {
  serveRegistryDir.createSync(recursive: true);
  File(p.join(serveRegistryDir.path, '$pid.json'))
      .writeAsStringSync(jsonEncode({'artifactDir': artifactDir, 'port': port}));
}

void deregisterServeInstance(int pid) {
  try {
    File(p.join(serveRegistryDir.path, '$pid.json')).deleteSync();
  } catch (_) {}
}

/// SIGINT stops EVERY instance serving the same artifact. For each sibling
/// pidfile whose artifactDir AND port both match, verify via `ps` that the pid
/// is still a design-server process (pids get reused) before signalling; sweep
/// stale ones. Returns the sibling pids that were signalled (for tests).
///
/// The key is (artifactDir, port), and BOTH halves are load-bearing (task #69).
/// It used to be artifactDir alone, which sounds narrow and is not: in practice
/// every server in this repo serves the same studio design dir (v1 then;
/// `designs/appbox-studio-v2` since 2026-08-16), so
/// the predicate was a constant and the sweep was global. Measured on the live
/// registry while writing this: 14 pidfiles, every one of them the identical
/// artifactDir. One ^C therefore SIGTERMed every design server on the machine —
/// which is how the user's studio on 4319 died twice with nothing on screen but
/// an exit code, and how a parallel agent's server was killed 3x from a session
/// that never touched its path. Two servers on different designs, or the same
/// design on two ports (comparing a design before/after a change side by side),
/// are legitimate and must coexist.
///
/// [announce] receives a human line for every process actually signalled.
/// Silently reaping someone else's server is the invisible-failure trap this
/// codebase keeps getting bitten by, so the kill is always narrated.
List<int> sweepSiblingInstances(int selfPid, String artifactDir,
    {required int port,
    void Function(int pid)? kill,
    void Function(String line)? announce}) {
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
    // `port` round-trips through JSON as a num, so compare as int — a silent
    // type mismatch here would make the predicate never match and turn the
    // takeover into a mystery "address already in use".
    final otherPort = (entry['port'] as num?)?.toInt();
    // An entry written before the port was recorded cannot be PROVEN to be the
    // instance we are replacing, and this registry is a graveyard of stale
    // files — a wrong guess here kills a live server someone is using. So a
    // portless entry is never signalled; it is only reaped once `ps` says its
    // pid is gone (handled below).
    if (otherPort != null && otherPort != port) continue;
    try {
      final r = Process.runSync('ps', ['-p', '$other', '-o', 'command=']);
      if (r.exitCode != 0) {
        try {
          f.deleteSync();
        } catch (_) {}
        continue;
      }
      if (otherPort == null) continue; // alive, but not provably ours
      final cmd = (r.stdout as String).trim();
      if (cmd.contains('appbox') ||
          cmd.contains('design_server') ||
          cmd.contains('design serve')) {
        announce?.call(
            'stopping the existing instance of $artifactDir on port $port (pid $other)');
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
  // Anchor 1 — the checkout that is executing ([scriptRepoRoot]): the vendored
  // runtime lives at <repo>/skills/…, found from ANY cwd. A pub-cache
  // deployment has no repo marker, the derived path won't exist, and the
  // walk below applies.
  final repo = scriptRepoRoot();
  if (repo != null) {
    final c = p.join(
        repo, 'skills', 'appbox-designer', 'runtime', 'vendor');
    if (Directory(c).existsSync()) return c;
  }
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
