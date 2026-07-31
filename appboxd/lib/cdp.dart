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
      ...extraArgs,
      'about:blank',
    ];

    final proc = await Process.start(chromePath, args);
    final wsUrl = await _waitForDevToolsUrl(proc);

    final ws = await WebSocket.connect(wsUrl);
    final client = CdpClient._(proc, ws);
    client._tmpDir = tmpDir;
    return client;
  }

  /// Connect to an already-running Chrome's DevTools endpoint.
  static Future<CdpClient> connect(String wsUrl) async {
    final ws = await WebSocket.connect(wsUrl);
    // The Process is null — close() won't kill it.
    return CdpClient._(null, ws);
  }

  /// Find Chrome at the default platform path.
  static String defaultChromePath() {
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
    await _ws.close();
    _chrome?.kill(ProcessSignal.sigkill);
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
  Future<void> navigateAndSettle(String url, {int settleMs = 1500}) async {
    await navigate(url);
    await Future.delayed(Duration(milliseconds: settleMs));
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

