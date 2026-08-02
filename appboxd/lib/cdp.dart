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
    // Fallback: if Chrome was open-launched and Browser.close didn't end it,
    // kill any process still holding our temp user-data-dir.
    if (_chrome == null && _tmpDir != null) {
      try {
        await Process.run('pkill', ['-f', _tmpDir!.path]);
      } catch (_) {}
    }
    if (_tmpDir != null) {
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

