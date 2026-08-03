// Chrome DevTools Protocol (CDP) client over dart:io WebSocket.
//
// The substrate for:
// - emit_htmx/emit_playground replacement (DOM extraction via Runtime.evaluate)
// - appbox lens visual gate (screenshots via Page.captureScreenshot)
//
// Uses raw dart:io — no external dependencies. CDP is JSON-RPC 2.0 over
// WebSocket text frames.
//
// References:
//   https://chromedevtools.github.io/devtools-protocol/tot/Page/
//   https://chromedevtools.github.io/devtools-protocol/tot/Emulation/
//   https://chromedevtools.github.io/devtools-protocol/tot/Runtime/

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A CDP error returned by Chrome.
class CdpException implements Exception {
  final String message;
  final int? code;
  final dynamic data;
  CdpException(this.message, [this.code, this.data]);

  @override
  String toString() => 'CdpException($code): $message${data != null ? ' — $data' : ''}';
}

/// A CDP event (unsolicited notification from Chrome).
class CdpEvent {
  final String method;
  final Map<String, dynamic> params;
  CdpEvent(this.method, this.params);
}

/// Opt-in visual mode for the appbox lens. Set by `lens_cli` when `--visible`
/// is passed; read by [CdpClient.launch] (to drop --headless) and
/// [CdpSession.navigateAndSettle] (to inject/remove the per-verb glow).
///
/// A static holder avoids threading a param through every lens verb, since
/// each verb spawns its own `CdpClient.launch()` + `CdpSession`. Defaults to
/// headless + no glow, so existing automation is unchanged.
class LensSession {
  LensSession._();
  static bool visible = false;
  static String? verb; // e.g. 'shot', 'tokens', 'record'
  static String? detail; // e.g. '390x844'
  // Parsed viewport (W/H) from the verb's positionals, when present. In visible
  // mode CdpClient.launch sizes the Chrome window to (windowW, windowH+chrome)
  // so the emulated content fills the window and the inset glow reads as the
  // *window* glowing, not a small box inside a default-size window.
  static int? windowW;
  static int? windowH;
}

/// Chrome's tab+toolbar chrome height in px. Added to the emulated viewport
/// height when sizing the visible window so the content area ≈ the viewport.
const int _kWindowChrome = 96;

/// Per-verb glow colors. The label pill + inset border use this.
const Map<String, String> lensGlowColors = {
  'shot': '#22d3ee', 'shoot': '#22d3ee', 'check': '#22d3ee', 'color': '#22d3ee',
  'compare': '#f59e0b',
  'tokens': '#10b981',
  'dom': '#8b5cf6',
  'a11y': '#14b8a6',
  'net': '#f97316',
  'record': '#ef4444',
  'burst': '#ec4899',
  'anim': '#d946ef',
  'flipbook': '#f43f5e',
  'crawl': '#3b82f6',
  'skeleton': '#6366f1', 'skeleton-diff': '#6366f1',
  'states': '#f472b6',
  'ocr': '#eab308',
  'text-diff': '#84cc16',
};

/// Chrome DevTools Protocol browser-level client.
///
/// Launches Chrome headless and connects via WebSocket to the browser-level
/// DevTools endpoint. Page-level work happens through [newTab] → [CdpSession].
class CdpClient {
  final Process? _chrome;
  final WebSocket _ws;
  int _nextId = 1;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _sessions = <String, CdpSession>{};
  final _browserEvents = StreamController<CdpEvent>.broadcast();
  bool _closed = false;
  Directory? _tmpDir;

  /// Pid of the browser on the `open -g` path, where there is no [Process].
  /// Resolved from the profile dir at launch — see [launch].
  int? _chromePid;

  /// The unique `--user-data-dir` this client launched Chrome with, and the pid
  /// that owns it. Both null for [connect] (someone else's browser, not ours to
  /// kill). Exposed so the teardown test can assert what actually happened to
  /// the process and the profile, rather than that `close()` returned.
  Directory? get userDataDir => _tmpDir;
  int? get chromePid => _chromePid ?? _chrome?.pid;

  CdpClient._(this._chrome, this._ws) {
    _ws.listen(
      _onData,
      onError: (e) => _browserEvents.addError(e),
      onDone: () => _browserEvents.close(),
    );
  }

  // ── launch / connect ──────────────────────────────────────────────

  /// Launch Chrome headless and connect via CDP.
  static Future<CdpClient> launch({
    String? chromePath,
    List<String> extraArgs = const [],
  }) async {
    chromePath ??= defaultChromePath();
    if (!await File(chromePath).exists()) {
      throw StateError('Chrome not found at: $chromePath');
    }

    final tmpDir = await Directory.systemTemp.createTemp('appbox-cdp-');
    final args = [
      if (!LensSession.visible) '--headless=new',
      if (LensSession.visible &&
          LensSession.windowW != null &&
          LensSession.windowH != null)
        '--window-size=${LensSession.windowW},${LensSession.windowH! + _kWindowChrome}',
      '--remote-debugging-port=0',
      '--user-data-dir=${tmpDir.path}',
      '--no-first-run',
      '--no-default-browser-check',
      // --no-startup-window: start with no initial tab (we create tabs via CDP).
      // Fewer GUI resources initialized at launch → less macOS app activation.
      '--no-startup-window',
      '--hide-scrollbars',
      ...extraArgs,
    ];

    // On macOS headless, launch via `open -g` (background) so Chrome never
    // registers as a foreground app — no dock bounce per launch (headless
    // Chrome otherwise bounces the dock for ~0.25s on every start, which storms
    // the dock during test runs). `open` gives no stderr, so the DevTools URL is
    // read from the DevToolsActivePort file Chrome writes in the user-data-dir.
    // Visible mode (+ non-macOS) keep the direct-exec path (process handle +
    // stderr URL) since a visible window is meant to appear.
    if (Platform.isMacOS && !LensSession.visible) {
      final app = _chromeAppBundle(chromePath);
      await Process.run('open', ['-g', '-n', '-a', app, '--args', ...args]);
      final wsUrl =
          await _waitForDevToolsPortFile('${tmpDir.path}/DevToolsActivePort');
      final ws = await WebSocket.connect(wsUrl);
      final client = CdpClient._(null, ws);
      client._tmpDir = tmpDir;
      // `open` hands back no Process, so close() had nothing to kill and fell
      // back to asking Chrome nicely + a pattern kill — which did not always
      // land: a 6-launch lens storm left 2 Chromes resident. DevToolsActivePort
      // is already written by here, so the browser certainly exists, and the
      // profile dir is unique to this launch, so its pid is resolvable now.
      final owners = _pidsOwningProfile(tmpDir.path, browserOnly: true);
      if (owners.isNotEmpty) client._chromePid = owners.first;
      return client;
    }

    final proc = await Process.start(chromePath, args);
    final wsUrl = await _waitForDevToolsUrl(proc);
    final ws = await WebSocket.connect(wsUrl);
    final client = CdpClient._(proc, ws);
    client._tmpDir = tmpDir;
    return client;
  }

  /// Derive the .app bundle path from the executable path
  /// (/…/Google Chrome.app/Contents/MacOS/Google Chrome → /…/Google Chrome.app).
  static String _chromeAppBundle(String exePath) {
    final idx = exePath.indexOf('.app/');
    return idx < 0 ? exePath : exePath.substring(0, idx + 4);
  }

  /// Pids whose command line carries `--user-data-dir=[dir]`.
  ///
  /// Same `ps` shape and same `--type=` exclusion as
  /// `_ChromeHandle.sweepOrphans`, deliberately: "who owns this profile" should
  /// have one convention in this codebase, not two. [browserOnly] drops the
  /// helpers (they all carry `--type=`), leaving the single process that owns
  /// the profile — that is the one worth remembering as a pid. At teardown we
  /// want the helpers too, since a live helper still holds files in the dir.
  static List<int> _pidsOwningProfile(String dir, {bool browserOnly = false}) {
    final ProcessResult ps;
    try {
      ps = Process.runSync('ps', ['-eo', 'pid=,command=']);
    } catch (_) {
      return const []; // no ps (unlikely) — degrade, never crash a teardown.
    }
    if (ps.exitCode != 0) return const [];
    final needle = '--user-data-dir=$dir';
    final out = <int>[];
    for (final line in (ps.stdout as String).split('\n')) {
      final at = line.indexOf(needle);
      if (at < 0) continue;
      // Whole dir, not a prefix: `appbox-cdp-AB` must not claim `…-ABC`'s pid.
      final rest = line.substring(at + needle.length);
      if (rest.isNotEmpty && !rest.startsWith(' ')) continue;
      if (browserOnly && line.contains('--type=')) continue;
      final pid = int.tryParse(line.trimLeft().split(RegExp(r'\s+')).first);
      if (pid != null) out.add(pid);
    }
    return out;
  }

  /// Wait until nothing holds [dir] any more, SIGKILLing by pid whatever still
  /// does.
  ///
  /// This replaces the old `pkill -f <dir>` fallback. The rescan is the whole
  /// point: it does not depend on launch-time pid resolution having succeeded,
  /// so it still covers the case the pattern kill existed for — by pid only,
  /// which the standing rule against broad `pkill -f` requires.
  ///
  /// Waiting (rather than firing and returning) is what makes the leak
  /// observable: `Browser.close` returns on acknowledgement, not on exit, and
  /// the recursive delete below fails while a process is still writing into the
  /// profile. Bounded, because a `close()` that can hang forever would be a
  /// worse bug than the leak — on timeout we delete anyway and leave the
  /// straggler to `sweepOrphans`.
  static Future<void> _awaitProfileReleased(
    String dir, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final owners = _pidsOwningProfile(dir);
      if (owners.isEmpty) return;
      for (final pid in owners) {
        try {
          Process.killPid(pid, ProcessSignal.sigkill);
        } catch (_) {}
      }
      if (!DateTime.now().isBefore(deadline)) return;
      await Future.delayed(const Duration(milliseconds: 25));
    }
  }

  /// Read the DevTools ws URL from the DevToolsActivePort file Chrome writes in
  /// the user-data-dir (used when launched via `open -g`, which gives no stderr).
  /// File format: line 1 = port, line 2 = ws path (e.g. /devtools/browser/GUID).
  static Future<String> _waitForDevToolsPortFile(
    String path, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final f = File(path);
      if (f.existsSync()) {
        final lines = f.readAsLinesSync();
        if (lines.length >= 2 && lines[0].isNotEmpty) {
          return 'ws://127.0.0.1:${lines[0]}${lines[1]}';
        }
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Chrome did not write DevToolsActivePort within 30s');
  }

  /// Connect to an already-running Chrome's DevTools endpoint.
  static Future<CdpClient> connect(String wsUrl) async {
    final ws = await WebSocket.connect(wsUrl);
    // The Process is null — close() won't kill it.
    return CdpClient._(null, ws);
  }

  /// Find Chrome at the default platform path.
  ///
  /// `APPBOX_CHROME` overrides it — the same escape hatch `tools/probe-*.mjs`
  /// already honours, for machines where Chrome is not at the platform default
  /// and for exercising the launch-failure paths against a stub binary.
  static String defaultChromePath() {
    final override = Platform.environment['APPBOX_CHROME'];
    if (override != null && override.isNotEmpty) return override;
    if (Platform.isMacOS) {
      return '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    }
    if (Platform.isLinux) {
      for (final p in [
        '/usr/bin/google-chrome',
        '/usr/bin/google-chrome-stable',
        '/usr/bin/chromium',
        '/usr/bin/chromium-browser',
      ]) {
        if (File(p).existsSync()) return p;
      }
    }
    throw UnsupportedError(
      'No default Chrome path for ${Platform.operatingSystem}. '
      'Pass chromePath explicitly.',
    );
  }

  /// Wait for Chrome to print the DevTools WS URL on stderr.
  static Future<String> _waitForDevToolsUrl(Process proc) async {
    final completer = Completer<String>();
    late StreamSubscription sub;
    sub = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final m = RegExp(r'ws://\S+').firstMatch(line);
            if (m != null && !completer.isCompleted) {
              completer.complete(m.group(0)!);
            }
          },
          onDone: () {
            if (!completer.isCompleted) {
              completer.completeError(
                StateError('Chrome exited before emitting DevTools URL'),
              );
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

  // ── low-level JSON-RPC ────────────────────────────────────────────

  /// Send a browser-level CDP command and await the response.
  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    return _send(method, params, null);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Map<String, dynamic>? params,
    String? sessionId,
  ) async {
    if (_closed) throw StateError('CdpClient is closed');
    final id = _nextId++;
    final msg = <String, dynamic>{'id': id, 'method': method};
    if (params != null && params.isNotEmpty) msg['params'] = params;
    if (sessionId != null) msg['sessionId'] = sessionId;

    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    _ws.add(jsonEncode(msg));

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('CDP command "$method" timed out (30s)');
      },
    );
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    final msg = jsonDecode(data) as Map<String, dynamic>;

    if (msg.containsKey('id')) {
      final id = msg['id'] as int;
      final c = _pending.remove(id);
      if (c == null || c.isCompleted) return;
      if (msg.containsKey('error')) {
        final err = msg['error'] as Map<String, dynamic>;
        c.completeError(CdpException(
          err['message'] as String? ?? 'Unknown CDP error',
          err['code'] as int?,
          err['data'],
        ));
      } else {
        c.complete(msg);
      }
      return;
    }

    if (msg.containsKey('method')) {
      final method = msg['method'] as String;
      final params = (msg['params'] as Map<String, dynamic>?) ?? {};
      final sid = msg['sessionId'] as String?;
      if (sid != null) {
        _sessions[sid]?._onEvent(CdpEvent(method, params));
      } else {
        _browserEvents.add(CdpEvent(method, params));
      }
    }
  }

  /// Browser-level event stream.
  Stream<CdpEvent> get events => _browserEvents.stream;

  // ── tab / session management ──────────────────────────────────────

  /// Create a new browser tab and return a session attached to it.
  Future<CdpSession> newTab({String url = 'about:blank'}) async {
    final res = await send('Target.createTarget', {'url': url});
    final targetId = res['result']['targetId'] as String;

    final att = await send('Target.attachToTarget', {
      'targetId': targetId,
      'flatten': true,
    });
    final sessionId = att['result']['sessionId'] as String;

    final session = CdpSession._(this, sessionId, targetId);
    _sessions[sessionId] = session;
    return session;
  }

  // ── teardown ──────────────────────────────────────────────────────

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final s in _sessions.values) {
      await s._close();
    }
    _sessions.clear();
    if (_chrome == null) {
      // open-launched (headless, no dock bounce): ask Chrome to exit cleanly.
      try {
        await send('Browser.close');
      } catch (_) {}
    }
    await _ws.close();
    _chrome?.kill(ProcessSignal.sigkill);
    // The open-launched browser now has a pid too, so it dies the same way the
    // direct-exec one always could, instead of only being asked to leave.
    if (_chromePid != null) {
      try {
        Process.killPid(_chromePid!, ProcessSignal.sigkill);
      } catch (_) {}
    }
    if (_tmpDir != null) {
      // Only ours ever carries this dir, so nothing else can be caught here —
      // and close() does not return until it is genuinely unowned, which is
      // both what the delete needs and what makes a leak assertable.
      await _awaitProfileReleased(_tmpDir!.path);
      try {
        await _tmpDir!.delete(recursive: true);
      } catch (_) {}
    }
    await _browserEvents.close();
  }
}

/// A CDP session attached to one page target (tab).
///
/// Owns the page-level event stream. Console errors and page errors are
/// captured automatically when [enable] is called.
class CdpSession {
  final CdpClient _client;
  final String sessionId;
  final String targetId;
  final _events = StreamController<CdpEvent>.broadcast();
  final consoleErrors = <String>[];
  final pageErrors = <String>[];
  bool _enabled = false;

  CdpSession._(this._client, this.sessionId, this.targetId);

  // ── commands ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    return _client._send(method, params, sessionId);
  }

  /// Enable Page + Runtime + Log domains. Captures console/page errors.
  Future<void> enable() async {
    if (_enabled) return;
    await send('Page.enable');
    await send('Runtime.enable');
    await send('Log.enable');
    _enabled = true;
  }

  /// Set viewport dimensions (emulates device metrics).
  Future<void> setViewport(
    int width,
    int height, {
    double deviceScaleFactor = 1,
    bool mobile = false,
  }) async {
    // In visible mode, let the page fill the actual browser window so the glow
    // spans the whole window. Chrome clamps narrow windows to a ~500px min, so
    // emulating the requested (narrower) viewport would shrink the glow to a
    // content-sized box inside a wider grey window. Headless mode (the default,
    // used by the gate) emulates the exact requested dimensions — unaffected.
    if (LensSession.visible) return;
    await send('Emulation.setDeviceMetricsOverride', {
      'width': width,
      'height': height,
      'deviceScaleFactor': deviceScaleFactor,
      'mobile': mobile,
    });
  }

  /// Navigate to [url] and wait for the load event.
  Future<void> navigate(String url, {Duration timeout = const Duration(seconds: 30)}) async {
    if (!_enabled) await enable();
    final loadCompleter = Completer<void>();
    late StreamSubscription sub;
    sub = events.where((e) => e.method == 'Page.loadEventFired').listen((_) {
      if (!loadCompleter.isCompleted) loadCompleter.complete();
    });
    try {
      await send('Page.navigate', {'url': url});
      await loadCompleter.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  /// Navigate, wait for load, then settle [settleMs] milliseconds.
  /// Mirrors emit_htmx.py's goto + wait_for_timeout(1500).
  ///
  /// In --visible mode the per-verb glow is injected for the settle window so
  /// the operator can see which verb is driving the page, then REMOVED before
  /// this returns — so every capture/data-read the verb performs afterwards is
  /// clean. All lens verbs call this first, so glow coverage is automatic.
  Future<void> navigateAndSettle(String url, {int settleMs = 1500}) async {
    await navigate(url);
    if (LensSession.visible) {
      await injectLensGlow();
    }
    await Future.delayed(Duration(milliseconds: settleMs));
    if (LensSession.visible) {
      await removeLensGlow();
    }
  }

  /// Evaluate a JavaScript expression in the page.
  /// Returns the result value (deserialised from JSON).
  Future<dynamic> evaluate(String expression, {bool awaitPromise = true}) async {
    final res = await send('Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
      'awaitPromise': awaitPromise,
    });
    final result = res['result']['result'] as Map<String, dynamic>?;
    if (result == null) return null;
    final exceptionDetails = res['result']['exceptionDetails'];
    if (exceptionDetails != null) {
      final ex = exceptionDetails['exception'];
      final text = ex?['description'] ??
          exceptionDetails['text'] ??
          'Evaluation error';
      throw CdpException(text);
    }
    return result['value'];
  }

  /// Evaluate a JS function with a JSON-serialisable argument.
  /// Mirrors Playwright's page.evaluate(fn, arg).
  Future<dynamic> evaluateFunction(
    String functionDeclaration,
    dynamic arg,
  ) async {
    // Serialize arg as a JSON string, then parse it inside the eval
    // to safely pass complex objects.
    final argJson = jsonEncode(arg);
    final expr = '($functionDeclaration)(JSON.parse(${jsonEncode(argJson)}))';
    return evaluate(expr);
  }

  /// Capture a screenshot as PNG bytes.
  Future<List<int>> screenshot({bool fullPage = false}) async {
    final params = <String, dynamic>{
      'format': 'png',
      'fromSurface': true,
    };
    if (fullPage) params['captureBeyondViewport'] = true;

    final res = await send('Page.captureScreenshot', params);
    final data = res['result']['data'] as String;
    return base64Decode(data);
  }

  /// Dispatch a key press (down + up) via Input.dispatchKeyEvent.
  /// Supports arrows, Enter, Escape, Space and single characters.
  ///
  // kimitail: windowsVirtualKeyCode/nativeVirtualKeyCode intentionally
  // omitted — in --headless=new Chrome they trigger an auto-repeat storm
  // of `Unidentified` keydown events (verified via diagnostic). `key` +
  // `code` alone yield the single correct keydown the page listeners (and
  // the game screen) expect.
  Future<void> key(String key) async {
    final code = key == ' '
        ? 'Space'
        : (key.length == 1 ? 'Key${key.toUpperCase()}' : key);
    for (final type in ['keyDown', 'keyUp']) {
      await send('Input.dispatchKeyEvent', {
        'type': type,
        'key': key,
        'code': code,
      });
    }
  }

  /// Click at viewport coordinates via Input.dispatchMouseEvent.
  Future<void> click(int x, int y) async {
    for (final type in ['mousePressed', 'mouseReleased']) {
      await send('Input.dispatchMouseEvent', {
        'type': type,
        'x': x,
        'y': y,
        'button': 'left',
        'clickCount': 1,
      });
    }
  }

  // ── waiting on a condition instead of on the clock ─────────────────

  /// Poll [expression] in the page until it is truthy, or [timeout] elapses.
  ///
  /// Returns true when the condition held, false on timeout — it does NOT
  /// throw. A caller driving a suite of checks has to be able to report every
  /// one of them, so a slow condition must not abort the checks behind it the
  /// way a thrown timeout does; the check that follows a false return reads
  /// the real state and fails on its own terms.
  ///
  /// The alternative this replaces is `Future.delayed` on a number picked on
  /// an idle machine: under load that reads the DOM mid-transition and reports
  /// a regression that is not there, and on a fast machine it is dead time in
  /// which a genuinely broken feature can still settle into a passing state.
  /// The timeout is bounded rather than open because an unbounded wait turns a
  /// real regression into a hang, which is harder to diagnose than a failure.
  ///
  /// [polling] is an interval, not an animation-frame hook: a rAF-driven poll
  /// runs its callback every frame, contending with the frames a running
  /// transition needs to finish.
  Future<bool> waitForFunction(
    String expression, {
    Duration timeout = const Duration(seconds: 8),
    Duration polling = const Duration(milliseconds: 100),
  }) async {
    if (!_enabled) await enable();
    // `!!` so the caller gets JavaScript truthiness rather than Dart's
    // stricter `== true` — a condition returning an element or a length is
    // idiomatic and must not read as false here.
    final expr = '!!($expression)';
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await evaluate(expr) == true) return true;
      } on CdpException {
        // Not yet false — unreadable. A navigation tears down the execution
        // context and the next evaluate in the new one throws; the deadline,
        // not the first exception, decides.
      }
      await Future.delayed(polling);
    }
    return false;
  }

  /// Wait for [selector] to be present, and by default to occupy space.
  ///
  /// `visible: false` asks only about presence — use it when the element is
  /// deliberately collapsed, or when the next act is a synthetic click that
  /// does not need pointer geometry.
  Future<bool> waitForSelector(
    String selector, {
    Duration timeout = const Duration(seconds: 8),
    bool visible = true,
  }) {
    final sel = jsonEncode(selector);
    // display:none, a zero-height rail and a detached node all report a 0×0
    // rect, and a pointer can be aimed at none of them.
    final expr = visible
        ? '(() => { const e = document.querySelector($sel); if (!e) return false;'
            ' const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; })()'
        : 'document.querySelector($sel) !== null';
    return waitForFunction(expr, timeout: timeout);
  }

  /// Move the pointer to viewport coordinates without pressing anything.
  ///
  /// A real pointer arrives before it clicks, and CSS `:hover` rules act on
  /// that arrival. Dispatching a click with no preceding move asks the page to
  /// respond to a pointer that was never anywhere.
  Future<void> hover(int x, int y) async {
    await send('Input.dispatchMouseEvent', {
      'type': 'mouseMoved',
      'x': x,
      'y': y,
    });
  }

  /// Click the first element matching [selector], waiting up to [timeout] for
  /// it to appear. Returns false if it never did.
  ///
  /// The pointer path is hover-then-click, always — not an option, because
  /// CDP has no equivalent of Playwright's actionability checks, and half the
  /// controls worth probing are revealed by `:hover` on an ancestor (tile tool
  /// rails, panel chrome). Clicking without hovering first lands on whatever
  /// occupied that point while the control was still hidden.
  ///
  /// The box is measured AGAIN after the hover: revealing a rail changes
  /// layout, so the pre-hover centre can be the wrong target — or another
  /// element entirely — by the time the press is dispatched.
  ///
  /// Two dispatch modes, because the elements a probe drives come in both
  /// shapes:
  /// - default — scroll into view, hover, re-measure, [click] at the centre.
  ///   The only mode that exercises hit-testing, z-order and `pointer-events`.
  /// - [synthetic] — dispatch the element's own `click()`. For controls no
  ///   pointer can reach in a headless run, where the page listens for the
  ///   click event rather than for the pointer that produced it. Presence, not
  ///   visibility, is the precondition. It cannot see an overlay covering the
  ///   control — that blind spot is the price of reaching the control at all.
  Future<bool> clickSelector(
    String selector, {
    Duration timeout = const Duration(seconds: 8),
    bool synthetic = false,
  }) async {
    final present = await waitForSelector(selector,
        timeout: timeout, visible: !synthetic);
    if (!present) return false;
    final sel = jsonEncode(selector);
    if (synthetic) {
      final hit = await evaluate(
          '(() => { const e = document.querySelector($sel);'
          ' if (!e) return false; e.click(); return true; })()');
      return hit == true;
    }
    final before = await _centreOf(sel, scroll: true);
    if (before == null) return false;
    await hover(before.$1, before.$2);
    // Let the reveal transition run before re-measuring; a rail that is still
    // animating open reports a box that is about to be wrong.
    await waitForFunction('(window.__vtBusy || 0) === 0',
        timeout: const Duration(seconds: 2),
        polling: const Duration(milliseconds: 25));
    final after = await _centreOf(sel, scroll: false);
    if (after == null) return false;
    await click(after.$1, after.$2);
    return true;
  }

  /// Viewport centre of [sel] (already JSON-encoded), or null if it is gone.
  Future<(int, int)?> _centreOf(String sel, {required bool scroll}) async {
    final box = await evaluate('(() => { const e = document.querySelector($sel);'
        ' if (!e) return null;'
        "${scroll ? " e.scrollIntoView({block: 'center', inline: 'center'});" : ''}"
        ' const r = e.getBoundingClientRect();'
        ' return {x: r.left + r.width / 2, y: r.top + r.height / 2}; })()');
    if (box == null) return null;
    return ((box['x'] as num).round(), (box['y'] as num).round());
  }

  /// Press at (from), move to (to) in [steps] increments, release.
  ///
  /// [steps] is not a smoothness knob — it is a correctness one. A drag
  /// dispatched as press → one move → release is invisible to anything that
  /// detects a drag by accumulating pointer movement over a threshold: the
  /// listener sees a single jump and treats it as a click, so a resize probe
  /// built on a two-point drag reports the divider broken when the divider is
  /// fine. The default is what the studio's resize interactions were tuned
  /// against; raise it for a longer travel, never lower it to 1.
  Future<void> drag(
    int fromX,
    int fromY,
    int toX,
    int toY, {
    int steps = 14,
    Duration stepDelay = const Duration(milliseconds: 16),
  }) async {
    if (steps < 1) throw ArgumentError.value(steps, 'steps', 'must be >= 1');
    // Arrive before pressing, same reason as clickSelector: a press at a point
    // the pointer never moved to skips every :hover and pointerenter handler
    // between here and the drag starting.
    await hover(fromX, fromY);
    await send('Input.dispatchMouseEvent', {
      'type': 'mousePressed',
      'x': fromX,
      'y': fromY,
      'button': 'left',
      'buttons': 1,
      'clickCount': 1,
    });
    for (var i = 1; i <= steps; i++) {
      await send('Input.dispatchMouseEvent', {
        'type': 'mouseMoved',
        'x': fromX + ((toX - fromX) * i / steps).round(),
        'y': fromY + ((toY - fromY) * i / steps).round(),
        // `buttons: 1` is what marks these as a drag rather than a hover; a
        // move without it is dispatched as though the button came back up.
        'button': 'left',
        'buttons': 1,
      });
      await Future.delayed(stepDelay);
    }
    await send('Input.dispatchMouseEvent', {
      'type': 'mouseReleased',
      'x': toX,
      'y': toY,
      'button': 'left',
      'buttons': 0,
      'clickCount': 1,
    });
  }

  /// Drag the element matching [selector] by ([dx], [dy]) viewport pixels.
  /// Returns false if the element is not there to grab.
  Future<bool> dragSelector(
    String selector, {
    required int dx,
    required int dy,
    int steps = 14,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!await waitForSelector(selector, timeout: timeout)) return false;
    final from = await _centreOf(jsonEncode(selector), scroll: true);
    if (from == null) return false;
    await drag(from.$1, from.$2, from.$1 + dx, from.$2 + dy, steps: steps);
    return true;
  }

  /// Set the value of the input/textarea matching [selector] and fire the
  /// events a real edit fires. Returns false if the element is absent.
  ///
  /// Assigning `.value` alone is invisible to everything that cares: htmx
  /// triggers, `hx-preserve` bookkeeping and framework bindings all key off
  /// the `input`/`change` events, so a probe that only assigns the property
  /// asserts on a state the user can never actually produce.
  Future<bool> fillSelector(String selector, String value) async {
    final sel = jsonEncode(selector);
    final val = jsonEncode(value);
    final ok = await evaluate('(() => { const e = document.querySelector($sel);'
        ' if (!e) return false; e.focus(); e.value = $val;'
        " e.dispatchEvent(new Event('input', {bubbles: true}));"
        " e.dispatchEvent(new Event('change', {bubbles: true}));"
        ' return true; })()');
    return ok == true;
  }

  /// Read [properties] off the computed style of [selector], or null when the
  /// element is absent — an assertion on a style has to be able to tell "this
  /// property is wrong" from "this element is not there".
  Future<Map<String, String>?> computedStyle(
    String selector,
    List<String> properties,
  ) async {
    final res = await evaluateFunction('''(a) => {
  const el = document.querySelector(a.selector);
  if (!el) return null;
  const cs = getComputedStyle(el);
  const out = {};
  for (const p of a.properties) out[p] = cs.getPropertyValue(p);
  return out;
}''', {'selector': selector, 'properties': properties});
    if (res == null) return null;
    return (res as Map).map((k, v) => MapEntry('$k', '$v'));
  }

  /// Fetch a response body by [requestId], or null if Chrome no longer has it.
  ///
  /// Null is a routine outcome, not an error: Chrome keeps response bodies in
  /// a bounded per-page buffer and drops them on navigation, so a body asked
  /// for after the fact may simply be gone. Callers that need bodies reliably
  /// should not poll for them — use [recordNetworkBodies], which fetches each
  /// one while it is still there.
  Future<String?> getResponseBody(String requestId) async {
    try {
      final res =
          await send('Network.getResponseBody', {'requestId': requestId});
      final result = res['result'] as Map<String, dynamic>;
      final body = result['body'] as String?;
      if (body == null) return null;
      return result['base64Encoded'] == true
          ? utf8.decode(base64Decode(body), allowMalformed: true)
          : body;
    } on CdpException {
      // "No resource with given identifier found" — evicted, or a request with
      // no body to begin with (a redirect, a 204). Indistinguishable here and
      // not worth distinguishing: both mean there is nothing to read.
      return null;
    }
  }

  /// Start recording response bodies, keyed by URL.
  ///
  /// Bodies are fetched on `Network.loadingFinished` — the earliest moment one
  /// exists and the latest moment it is still guaranteed to. Collecting the
  /// events first and fetching bodies at the end is the obvious shape and the
  /// broken one: by then the page has usually navigated and the buffer has
  /// been dropped, so the bodies that matter are exactly the ones missing.
  ///
  /// Caller stops it; [close] also ends it.
  Future<CdpNetworkBodies> recordNetworkBodies() async {
    await send('Network.enable');
    return CdpNetworkBodies._(this).._start();
  }

  /// Evaluate [source] in every document this target loads, before any of the
  /// page's own script runs — and across navigations, unlike [evaluate], which
  /// dies with the document it ran in.
  ///
  /// Must be installed BEFORE the first navigate: instrumentation that wraps a
  /// page API (counting swaps, shimming a browser hook) has to be in place
  /// before the page reads that API, or it wraps nothing.
  Future<void> addInitScript(String source) async {
    if (!_enabled) await enable();
    await send('Page.addScriptToEvaluateOnNewDocument', {'source': source});
  }

  // ── CDP domain extensions ─────────────────────────────────────────

  /// Start a screencast. Caller must stop() it; client.close() also ends it.
  Future<CdpScreencast> screencast({String format = 'jpeg', int quality = 80,
      int? maxWidth, int? maxHeight, int everyNthFrame = 1}) async {
    final cast = CdpScreencast._(this);
    await cast._start(format: format, quality: quality, maxWidth: maxWidth,
        maxHeight: maxHeight, everyNthFrame: everyNthFrame);
    return cast;
  }

  /// Collect Network domain events for [duration]. Enables Network,
  /// buffers requestWillBeSent/responseReceived/loadingFailed/loadingFinished
  /// events, disables, returns the raw event maps.
  Future<List<Map<String, dynamic>>> traceNetwork(Duration duration) async {
    await send('Network.enable');
    final events = <CdpEvent>[];
    final sub = on('Network.requestWillBeSent').listen(events.add);
    final subs = [
      sub,
      on('Network.responseReceived').listen(events.add),
      on('Network.loadingFailed').listen(events.add),
      on('Network.loadingFinished').listen(events.add),
    ];
    await Future.delayed(duration);
    for (final s in subs) {
      await s.cancel();
    }
    await send('Network.disable');
    return [for (final e in events) {'method': e.method, 'params': e.params}];
  }

  /// Full accessibility tree (Accessibility.getFullAXTree), raw node maps.
  Future<List<Map<String, dynamic>>> getFullAxTree() async {
    final r = await send('Accessibility.getFullAXTree');
    return [for (final n in r['result']['nodes'] as List) Map<String, dynamic>.from(n as Map)];
  }

  /// DOMSnapshot.captureSnapshot with the given computed style names.
  Future<Map<String, dynamic>> captureDomSnapshot(List<String> computedStyles) async {
    final r = await send('DOMSnapshot.captureSnapshot',
        {'computedStyles': computedStyles});
    return r['result'] as Map<String, dynamic>;
  }

  /// Emulation.setEmulatedMedia: media type and/or feature overrides
  /// (prefers-color-scheme, prefers-reduced-motion, color-gamut, …).
  Future<void> setEmulatedMedia({String? media, Map<String, String>? features}) async {
    await send('Emulation.setEmulatedMedia', {
      'media': ?media,
      if (features != null)
        'features': [for (final e in features.entries) {'name': e.key, 'value': e.value}],
    });
  }

  /// Screenshot clipped to a CSS selector's border box
  /// (DOM.getDocument -> querySelector -> getBoxModel).
  Future<List<int>> elementScreenshot(String selector) async {
    final doc = await send('DOM.getDocument');
    final node = await send('DOM.querySelector', {
      'nodeId': doc['result']['root']['nodeId'],
      'selector': selector,
    });
    if (node['result']['nodeId'] == 0) {
      throw CdpException('elementScreenshot: no element matches $selector');
    }
    final box = await send('DOM.getBoxModel', {'nodeId': node['result']['nodeId']});
    final border = box['result']['model']['border'] as List;
    final xs = [border[0], border[2], border[4], border[6]].map((v) => (v as num).toDouble());
    final ys = [border[1], border[3], border[5], border[7]].map((v) => (v as num).toDouble());
    final x = xs.reduce((a, b) => a < b ? a : b);
    final y = ys.reduce((a, b) => a < b ? a : b);
    final r = await send('Page.captureScreenshot', {
      'format': 'png',
      'clip': {
        'x': x,
        'y': y,
        'width': xs.reduce((a, b) => a > b ? a : b) - x,
        'height': ys.reduce((a, b) => a > b ? a : b) - y,
        'scale': 1,
      },
    });
    return base64Decode(r['result']['data'] as String);
  }

  /// Inject the appbox lens status glow: an animated inset border + a corner
  /// status pill, colored by [LensSession.verb]. Appended to documentElement
  /// so body-scoped probes (tokens) never see it. No-op if already present.
  Future<void> injectLensGlow() async {
    final verb = LensSession.verb ?? 'lens';
    final color = lensGlowColors[verb] ?? '#38bdf8';
    final detail = LensSession.detail;
    final label = detail == null ? verb : '$verb · $detail';
    final labelJson = jsonEncode('◉ appbox lens · $label');
    await evaluate('''
(function(){
  if (document.getElementById('appbox-lens-glow')) return;
  var c = ${jsonEncode(color)}, label = $labelJson;
  var s = document.createElement('style'); s.id='appbox-lens-glow-style';
  s.textContent='@keyframes appbox-lens-breathe{0%,100%{opacity:.2}50%{opacity:.42}}';
  var b = document.createElement('div'); b.id='appbox-lens-glow';
  b.style.cssText='position:fixed;inset:0;pointer-events:none;z-index:2147483647;box-shadow:inset 0 0 0 2px '+c+', inset 0 0 60px 6px '+c+';animation:appbox-lens-breathe 1s ease-in-out infinite;';
  var p = document.createElement('div'); p.id='appbox-lens-glow-label';
  p.style.cssText='position:fixed;top:14px;left:14px;z-index:2147483647;font:600 12px ui-monospace,Menlo,monospace;color:#0b0b0c;background:'+c+';padding:4px 10px;border-radius:999px;box-shadow:0 2px 10px rgba(0,0,0,.25);letter-spacing:.4px;pointer-events:none;opacity:.85';
  p.textContent=label;
  document.documentElement.appendChild(s);
  document.documentElement.appendChild(b);
  document.documentElement.appendChild(p);
})();''');
  }

  /// Remove the lens glow overlay (call before any capture/data-read).
  Future<void> removeLensGlow() async {
    await evaluate('''
(function(){
  ['appbox-lens-glow','appbox-lens-glow-style','appbox-lens-glow-label']
    .forEach(function(id){var e=document.getElementById(id);if(e)e.remove();});
})();''');
  }

  // ── events ────────────────────────────────────────────────────────

  /// Page-level event stream for this session.
  Stream<CdpEvent> get events => _events.stream;

  /// Subscribe to a specific event method.
  Stream<CdpEvent> on(String method) =>
      events.where((e) => e.method == method);

  void _onEvent(CdpEvent event) {
    _events.add(event);
    switch (event.method) {
      case 'Runtime.consoleAPICalled':
        if (event.params['type'] == 'error') {
          final args = event.params['args'] as List?;
          if (args != null && args.isNotEmpty) {
            consoleErrors.add(
              args.map((a) => a['value'] ?? a['description'] ?? '').join(' '),
            );
          }
        }
        break;
      case 'Runtime.exceptionThrown':
        final details = event.params['exceptionDetails'];
        if (details != null) {
          final ex = details['exception'];
          pageErrors.add(
            (ex?['description'] ?? details['text'] ?? '').toString(),
          );
        }
        break;
    }
  }

  /// Clear captured console/page errors (call between surfaces).
  void clearErrors() {
    consoleErrors.clear();
    pageErrors.clear();
  }

  Future<void> _close() async {
    await _events.close();
  }
}

/// One screencast frame delivered by Chrome.
/// One captured response: what was asked for, and what came back.
class CdpResponseRecord {
  /// Request URL.
  final String url;

  /// HTTP status, or null if the response never arrived.
  final int? status;

  /// MIME type as Chrome reported it.
  final String? mimeType;

  /// Decoded body, null when Chrome had nothing to give (evicted, or a
  /// response that never had one).
  final String? body;

  /// `encodedDataLength` — bytes on the wire, which is what a payload-size
  /// assertion should read. [body] length is post-decompression and will
  /// disagree, usually by a lot.
  final int? encodedLength;

  CdpResponseRecord({
    required this.url,
    this.status,
    this.mimeType,
    this.body,
    this.encodedLength,
  });
}

/// Response bodies captured as they land. See
/// [CdpSession.recordNetworkBodies].
class CdpNetworkBodies {
  final CdpSession _session;
  final _records = <CdpResponseRecord>[];
  final _meta = <String, Map<String, dynamic>>{};
  final _inFlight = <Future<void>>[];
  StreamSubscription? _responseSub;
  StreamSubscription? _finishedSub;

  CdpNetworkBodies._(this._session);

  void _start() {
    _responseSub = _session.on('Network.responseReceived').listen((e) {
      final response = e.params['response'] as Map<String, dynamic>?;
      if (response == null) return;
      _meta['${e.params['requestId']}'] = response;
    });
    _finishedSub = _session.on('Network.loadingFinished').listen((e) {
      final requestId = '${e.params['requestId']}';
      final response = _meta.remove(requestId);
      if (response == null) return;
      // Fetch now, while the body is still in the buffer. Held so [stop] can
      // await the ones already started rather than truncating them.
      final pending = () async {
        final body = await _session.getResponseBody(requestId);
        _records.add(CdpResponseRecord(
          url: '${response['url']}',
          status: (response['status'] as num?)?.toInt(),
          mimeType: response['mimeType'] as String?,
          body: body,
          encodedLength: (e.params['encodedDataLength'] as num?)?.toInt(),
        ));
      }();
      _inFlight.add(pending);
    });
  }

  /// Everything captured so far.
  List<CdpResponseRecord> get records => List.unmodifiable(_records);

  /// The first record whose URL contains [fragment], or null.
  CdpResponseRecord? firstMatching(String fragment) {
    for (final r in _records) {
      if (r.url.contains(fragment)) return r;
    }
    return null;
  }

  /// Stop recording and return what was captured, including bodies whose fetch
  /// was already in flight.
  Future<List<CdpResponseRecord>> stop() async {
    await _responseSub?.cancel();
    await _finishedSub?.cancel();
    await Future.wait(_inFlight);
    return records;
  }
}

class ScreencastFrame {
  ScreencastFrame(this.bytes, this.timestamp);
  final List<int> bytes; // jpeg or png, per the start() format
  final double? timestamp; // Page.screencastFrame metadata.timestamp
}

/// Handle for a running Page.startScreencast session. Chrome sends a
/// frame only after the previous one is acked (Page.screencastFrameAck)
/// and only when the page actually paints — an idle page produces no
/// frames, by protocol design. Frames are real-time and non-deterministic.
class CdpScreencast {
  CdpScreencast._(this._session);
  final CdpSession _session;
  final _controller = StreamController<ScreencastFrame>.broadcast();
  StreamSubscription<CdpEvent>? _sub;

  /// Frames as they arrive (already acked).
  Stream<ScreencastFrame> get frames => _controller.stream;

  Future<void> _start({required String format, required int quality, int? maxWidth,
      int? maxHeight, required int everyNthFrame}) async {
    _sub = _session.on('Page.screencastFrame').listen((event) async {
      final p = event.params;
      _controller.add(ScreencastFrame(
        base64Decode(p['data'] as String),
        ((p['metadata'] as Map?)?['timestamp'] as num?)?.toDouble(),
      ));
      await _session.send('Page.screencastFrameAck',
          {'sessionId': p['sessionId']});
    });
    await _session.send('Page.startScreencast', {
      'format': format,
      'quality': quality,
      'everyNthFrame': everyNthFrame,
      'maxWidth': ?maxWidth,
      'maxHeight': ?maxHeight,
    });
  }

  /// Stop the screencast and close the frame stream.
  Future<void> stop() async {
    await _session.send('Page.stopScreencast');
    await _sub?.cancel();
    await _controller.close();
  }
}

