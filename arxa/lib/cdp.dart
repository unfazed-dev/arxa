// Chrome DevTools Protocol (CDP) client over dart:io WebSocket.
//
// The substrate for:
// - emit_htmx/emit_playground replacement (DOM extraction via Runtime.evaluate)
// - arxa lens visual gate (screenshots via Page.captureScreenshot)
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

/// Opt-in visual mode for the arxa lens. Set by `lens_cli` when `--visible`
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

  /// iframe-child sessions discovered by [attachIframeSession], by their
  /// CDP session id — the client-level registry its poll matches against.
  final _iframeChildren = <String, CdpSession>{};

  /// Page sessions whose Target.auto-attach watcher is already armed.
  final _iframeWatched = <CdpSession>{};
  final _browserEvents = StreamController<CdpEvent>.broadcast();
  bool _closed = false;

  /// Reentrancy guard for [close], separate from [_closed] because the two
  /// answer different questions: `_closing` means "teardown has begun",
  /// `_closed` means "the socket is no longer usable". Collapsing them is what
  /// made the graceful `Browser.close` unreachable — see [close].
  bool _closing = false;
  Directory? _tmpDir;

  /// Did THIS client start the browser?
  ///
  /// [close] tears the browser down, and until 2026-08-21 it decided that on
  /// `_chrome == null` — which is true both for the `open -g` launch path AND
  /// for [connect]. So a client attached to someone else's browser sent
  /// `Browser.close` on the way out and killed it, while [connect]'s own
  /// comment claimed "close() won't kill it". Not a latent problem for the
  /// lens as it stands (nothing shares a browser yet); a hard blocker for the
  /// daemon, whose entire premise is guests attaching to a browser they must
  /// leave running. Ownership is now recorded, not inferred.
  bool _ownsBrowser = false;

  /// Pid of the browser on the `open -g` path, where there is no [Process].
  /// Resolved from the profile dir at launch — see [launch].
  int? _chromePid;

  /// The unique `--user-data-dir` this client launched Chrome with, and the pid
  /// that owns it. Both null for [connect] (someone else's browser, not ours to
  /// kill). Exposed so the teardown test can assert what actually happened to
  /// the process and the profile, rather than that `close()` returned.
  Directory? get userDataDir => _tmpDir;
  int? get chromePid => _chromePid ?? _chrome?.pid;

  /// The DevTools browser endpoint this client is attached to. The daemon
  /// records it so a later CLI run can [connect] to the same browser.
  String? get wsUrl => _wsUrl;
  String? _wsUrl;

  /// Screenshots taken through this client, counted at the single CDP
  /// chokepoint rather than by any caller. The lens daemon's recycle policy
  /// reads it — see [CdpSession._screenshotB64].
  int get screenshotsTaken => _screenshotsTaken;
  int _screenshotsTaken = 0;

  /// Invoked with [screenshotsTaken] when a GUEST client closes, so the daemon
  /// can bank the count against the browser it is lending out. Never called
  /// for a client that owns its browser — that browser is about to die, and
  /// its tally with it.
  void Function(int screenshots)? onGuestClose;

  /// Give up ownership so [close] leaves the browser running.
  ///
  /// Exactly one caller: the lens daemon's `start`, which launches Chrome and
  /// then needs its own process to exit while the browser stays up. Without
  /// this, `close()` would tear down the daemon it just created; skipping the
  /// `close()` instead would leak the socket and the profile handle.
  void disownBrowser() {
    _ownsBrowser = false;
    _tmpDir = null;
    _chromePid = null;
  }

  CdpClient._(this._chrome, this._ws) {
    _ws.listen(
      _onData,
      onError: (e) => _browserEvents.addError(e),
      onDone: () => _browserEvents.close(),
    );
  }

  // ── launch / connect ──────────────────────────────────────────────

  /// Launch Chrome headless and connect via CDP.
  ///
  /// Two attempts, not one, and every failed attempt cleans up after itself.
  /// Both are lessons the design worker's launcher (`worker.dart
  /// _ChromeHandle.launch`) already paid for, and this launcher had neither:
  ///
  ///  * Under CPU oversubscription Chrome can take >30s to boot — reproduced
  ///    on 2026-08-21 (full suite + 12 spinners on 10 cores: DevToolsActivePort
  ///    never written inside the timeout, test failed in setUp). A transient
  ///    failure that is never retried is a guaranteed failure.
  ///  * The failure paths threw with the spawned Chrome alive and the profile
  ///    dir on disk. A launch that times out while Chrome is still booting is
  ///    exactly how a green-looking session leaves warm orphans behind.
  static Future<CdpClient> launch({
    String? chromePath,
    List<String> extraArgs = const [],
  }) async {
    chromePath ??= defaultChromePath();
    if (!await File(chromePath).exists()) {
      throw StateError('Chrome not found at: $chromePath');
    }
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        return await _launchOnce(chromePath, extraArgs);
      } catch (e) {
        lastError = e;
        if (attempt < 2) {
          stderr.writeln(
              'cdp: Chrome launch attempt $attempt failed ($e) — retrying');
          await Future.delayed(Duration(milliseconds: 250 * attempt));
        }
      }
    }
    throw StateError('Chrome failed to launch after 2 attempts — $lastError');
  }

  static Future<CdpClient> _launchOnce(
    String chromePath,
    List<String> extraArgs,
  ) async {
    final tmpDir = await Directory.systemTemp.createTemp('arxa-cdp-');
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
      // Browser-wide UA override, opt-in via env (same opt-in style as
      // --visible riding LensSession). Exists for surfaces that gate on the
      // UA — e.g. arxa-studio's waiting-page referee parks any plain-browser
      // tab while the desktop shell is alive; ARXA_LENS_UA="… ArxaShell/1.0"
      // makes the lens render the real shell surface instead of the parked
      // card. A flag (not CDP Network.setUserAgentOverride) so every tab in
      // the launched browser inherits it, daemon guests included.
      if (Platform.environment['ARXA_LENS_UA'] case final ua?
          when ua.isNotEmpty)
        '--user-agent=$ua',
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
      try {
        await Process.run('open', ['-g', '-n', '-a', app, '--args', ...args]);
        final wsUrl =
            await _waitForDevToolsPortFile('${tmpDir.path}/DevToolsActivePort');
        final ws = await WebSocket.connect(wsUrl);
        final client = CdpClient._(null, ws);
        client._ownsBrowser = true;
        client._wsUrl = wsUrl;
        client._tmpDir = tmpDir;
        // `open` hands back no Process, so close() had nothing to kill and fell
        // back to asking Chrome nicely + a pattern kill — which did not always
        // land: a 6-launch lens storm left 2 Chromes resident. DevToolsActivePort
        // is already written by here, so the browser certainly exists, and the
        // profile dir is unique to this launch, so its pid is resolvable now.
        final owners = _pidsOwningProfile(tmpDir.path, browserOnly: true);
        if (owners.isNotEmpty) client._chromePid = owners.first;
        return client;
      } catch (_) {
        // `open` returns before Chrome finishes booting, so on a timeout the
        // browser may be alive — or may come up AFTER this cleanup runs. Kill
        // whatever owns the profile now and delete the dir; a straggler that
        // boots later against the deleted dir is sweepOrphans' case.
        await _reapFailedLaunch(tmpDir);
        rethrow;
      }
    }

    Process? proc;
    try {
      proc = await Process.start(chromePath, args);
      final wsUrl = await _waitForDevToolsUrl(proc);
      final ws = await WebSocket.connect(wsUrl);
      final client = CdpClient._(proc, ws);
      client._ownsBrowser = true;
      client._wsUrl = wsUrl;
      client._tmpDir = tmpDir;
      return client;
    } catch (_) {
      try {
        proc?.kill(ProcessSignal.sigkill);
      } catch (_) {}
      await _reapFailedLaunch(tmpDir);
      rethrow;
    }
  }

  /// A failed attempt must not leave a browser or a profile dir behind —
  /// SIGKILL by scoped ownership, then delete once nothing holds the dir.
  static Future<void> _reapFailedLaunch(Directory tmpDir) async {
    try {
      await awaitProfileReleased(tmpDir.path);
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    } catch (_) {
      // cleanup is best-effort; the launch error is the one worth throwing.
    }
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
  /// Public face of [_pidsOwningProfile], for the lens daemon.
  ///
  /// The daemon must never reap by the `arxa-cdp-` prefix: every browser
  /// this repo has ever launched matches it, so one `pkill -f arxa-cdp-`
  /// from any script kills a daemon that has been warm for hours. Ownership is
  /// the exact `--user-data-dir=<dir>`, and this is the one implementation of
  /// that question in the codebase.
  static List<int> pidsOwningProfile(String dir, {bool browserOnly = false}) =>
      _pidsOwningProfile(dir, browserOnly: browserOnly);

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
      // Whole dir, not a prefix: `arxa-cdp-AB` must not claim `…-ABC`'s pid.
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
  /// Public because the design worker's launch-failure path needs the same
  /// guarantee for its own profile dirs (`worker.dart`). Shared rather than
  /// reimplemented there: a second copy of a kill-and-wait loop is how the two
  /// drift, and this one already encodes the bounded-wait reasoning below.
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
  static Future<void> awaitProfileReleased(
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

  /// Connect to an already-running Chrome's DevTools endpoint as a GUEST.
  ///
  /// [close] on the returned client closes the socket and nothing else: no
  /// `Browser.close`, no SIGKILL, no profile-dir delete. That is the whole
  /// point — the browser belongs to whoever launched it.
  static Future<CdpClient> connect(String wsUrl) async {
    final ws = await WebSocket.connect(wsUrl);
    // _ownsBrowser stays false. It used to be inferred from `_chrome == null`,
    // which is ALSO true on the `open -g` launch path, so a guest's close()
    // shut the host's browser down.
    return CdpClient._(null, ws).._wsUrl = wsUrl;
  }

  /// Find Chrome at the default platform path.
  ///
  /// `ARXA_CHROME` overrides it — the same escape hatch `archives/tooling-pre-dart/tools/studio-probes/probe-*.mjs`
  /// already honours, for machines where Chrome is not at the platform default
  /// and for exercising the launch-failure paths against a stub binary.
  static String defaultChromePath() {
    final override = Platform.environment['ARXA_CHROME'];
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

  /// An isolated browser context — Chrome's incognito-profile equivalent, with
  /// its own cookie jar, storage and cache.
  ///
  /// The cookie jar is the point. The studio keys its session off a `kdh_sid`
  /// cookie, so everything a probe leaves behind that is neither DOM nor disk —
  /// which viewer lens is showing, where a flow walk has advanced to, whether
  /// the inspector is locked, what is pinned into chat context — travels with
  /// that cookie. Tabs opened by [newTab] with no context share the default one
  /// and therefore share all of it.
  ///
  /// The `.mjs` suite got this isolation for free by running each probe in its
  /// own `node` process, hence its own browser. A Dart runner that shares one
  /// browser across `probe all` loses it, and the loss is not hypothetical:
  /// the retired `explode` probe left the viewer on the flows lens, and
  /// `flowwalk`'s first section then read flows-lens toolbars while asserting
  /// about the views lens, reporting a walk control the views lens does not
  /// offer.
  ///
  /// Pair with [disposeBrowserContext] — contexts outlive the tabs in them.
  Future<String> createBrowserContext() async {
    final res = await send('Target.createBrowserContext');
    return res['result']['browserContextId'] as String;
  }

  /// Dispose a context created by [createBrowserContext], closing every tab
  /// still in it.
  ///
  /// Best-effort: a context whose tabs are already gone is a normal state at
  /// teardown, and failing there would turn cleanup into the reported error of
  /// a probe whose actual work succeeded.
  Future<void> disposeBrowserContext(String browserContextId) async {
    try {
      await send('Target.disposeBrowserContext',
          {'browserContextId': browserContextId});
    } on CdpException {
      // already gone
    }
  }

  /// Create a new browser tab and return a session attached to it.
  ///
  /// [browserContextId] puts the tab in an isolated context from
  /// [createBrowserContext]; omitted, it opens in the shared default context.
  Future<CdpSession> newTab({
    String url = 'about:blank',
    String? browserContextId,
  }) async {
    final res = await send('Target.createTarget', {
      'url': url,
      'browserContextId': ?browserContextId,
    });
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

  /// Attach a session to the out-of-process (OOPIF) target of an `<iframe>`
  /// embedded in [page], so a probe can evaluate inside a CROSS-ORIGIN frame.
  /// [CdpSession.evaluateInFrame] cannot reach those: the frame's execution
  /// context lives in a target the page session was never attached to (see
  /// its own doc on that failure).
  ///
  /// Matching: a child target of type `iframe` whose frame URL starts with
  /// [urlPrefix]; when the page embeds several frames of the same URL at
  /// different sizes — the studio design panel's rung ladder is exactly that
  /// — [wantInnerWidth] picks the one whose own `window.innerWidth` matches,
  /// which is unique per rung. Returns null when no match attaches within
  /// [timeout] (frame not mounted yet, or same-process and reachable through
  /// [CdpSession.evaluateInFrame] without a session of its own).
  Future<CdpSession?> attachIframeSession(
    CdpSession page, {
    required String urlPrefix,
    int? wantInnerWidth,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    // The watcher is armed ONCE per page session and never canceled while
    // the client lives: re-issuing Target.setAutoAttach does NOT re-fire
    // attachedToTarget for children Chrome already attached (learned the
    // hard way: the second call of this method on the same page — the
    // studio panel's next rung — timed out with the frame long loaded).
    if (_iframeWatched.add(page)) {
      page.events.listen((ev) {
        if (ev.method != 'Target.attachedToTarget') return;
        final params = (ev.params as Map?)?.cast<String, dynamic>() ?? {};
        final info =
            (params['targetInfo'] as Map?)?.cast<String, dynamic>() ?? {};
        if (info['type'] != 'iframe') return;
        final childSid = params['sessionId'] as String?;
        if (childSid == null || _sessions.containsKey(childSid)) return;
        final child =
            CdpSession._(this, childSid, info['targetId'] as String? ?? '');
        _sessions[childSid] = child;
        _iframeChildren[childSid] = child;
      });
      await page.send('Target.setAutoAttach', {
        'autoAttach': true,
        'waitForDebuggerOnStart': false,
        'flatten': true,
      });
    }
    // Auto-attach fires for already-existing child targets as they come up;
    // frames mounted later attach as they appear. Matching happens here, in
    // a poll, so a child that is briefly unaskable (about:blank mid-commit,
    // a crashed frame) is retried instead of dropped: leave it attached —
    // close() tears down every session the client owns, matched or not.
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final child in _iframeChildren.values.toList()) {
        try {
          final state = await child.evaluate(
              'JSON.stringify({url: location.href, iw: window.innerWidth})');
          final m = state is String ? jsonDecode(state) as Map : null;
          final url = m?['url'] as String? ?? '';
          final iw = m?['iw'] as int?;
          if (url.startsWith(urlPrefix) &&
              (wantInnerWidth == null || iw == wantInnerWidth)) {
            return child;
          }
        } catch (_) {
          // Not askable yet — the next poll retries.
        }
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  // ── teardown ──────────────────────────────────────────────────────

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    for (final s in _sessions.values) {
      await s._close();
    }
    _sessions.clear();
    // A guest closes its socket and stops there. Every teardown step below is
    // destructive to a browser this client may not have started.
    if (!_ownsBrowser) {
      _closed = true;
      await _ws.close();
      await _browserEvents.close();
      // Banked after the socket is down, so a throwing listener cannot leave
      // a half-closed client behind.
      try {
        onGuestClose?.call(_screenshotsTaken);
      } catch (_) {}
      return;
    }
    if (_chrome == null) {
      // open-launched (headless, no dock bounce): ask Chrome to exit cleanly.
      //
      // This ran for the first time on 2026-08-21. `close()` used to set
      // `_closed = true` as its second statement, and `send()` throws
      // StateError when `_closed` — inside a bare `catch (_) {}`. So the
      // graceful shutdown threw on every single call and was swallowed every
      // single time, for as long as it had existed. The pattern-kill it was
      // paired with was the thing that "did not always land" (see [launch]);
      // the pid SIGKILL added afterwards is what actually ends the browser.
      // Ordering the send before the flag is what makes the step real.
      try {
        await send('Browser.close');
      } catch (_) {}
    }
    _closed = true;
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
      await awaitProfileReleased(_tmpDir!.path);
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
  bool _domEnabled = false;

  /// frameId → the id of that frame's DEFAULT (page-world) execution context.
  ///
  /// Maintained from `Runtime.executionContext*` events rather than asked for
  /// on demand, because CDP has no "give me this frame's context" command —
  /// the events are the only place the frame↔context pairing is stated.
  final _frameContexts = <String, int>{};

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

  /// Seed cookies into this tab's context before navigation, so guarded
  /// routes (a boot ceremony, a sign-in gate) are capturable without
  /// clicking the guard — the seeded cookie IS the session the guard
  /// checks. [origin] scopes every cookie to the served design's scheme
  /// and host (Network.setCookie requires a url or domain).
  Future<void> seedCookies(Uri origin, Map<String, String> cookies) async {
    if (cookies.isEmpty) return;
    await send('Network.enable');
    for (final entry in cookies.entries) {
      await send('Network.setCookie', {
        'name': entry.key,
        'value': entry.value,
        'url': origin.toString(),
      });
    }
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

  /// Put every in-page animation into a fixed, reproducible state.
  ///
  /// The rule is Playwright's, and it is not "pause everything": pausing alone
  /// leaves an arbitrary phase on the clock, which is the defect, not the fix.
  ///
  ///   * **finite** animation → `finish()`. A golden should show the settled
  ///     page, not a fade caught mid-flight.
  ///   * **infinite** animation → `pause()` + `currentTime = 0`. There is no
  ///     "end" to jump to, so the only stable choice is the first frame.
  ///     (`cancel()` reaches the same picture but CSS may re-create the
  ///     animation immediately; pinning survives that.)
  ///
  /// `getAnimations()` covers CSS animations, CSS transitions and WAAPI only.
  /// SMIL and `<video>` are handled separately below. **GIF and APNG have no
  /// pause API at all** — that hole is real and Playwright has it too.
  ///
  /// **Pinning the phase is not enough, and that is the non-obvious part.**
  /// Measured: a page whose animation is provably pinned (`currentTime` 0,
  /// computed transform identity, every run) still produced 3 distinct images
  /// out of 4, worst case 13,345 pixels (4%). An element that merely *has* an
  /// animation is promoted to its own compositor layer, and that layer rasters
  /// differently run to run. Removing the `animation` property afterwards took
  /// the same page to 4/4 byte-identical. So this commits the frozen computed
  /// values inline and *then* drops the animation, de-promoting the layer.
  /// Committing first is what makes it safe: a bare `animation: none` would
  /// throw away the end state that `animation-fill-mode: forwards` was holding
  /// and snap the element back to its pre-animation style.
  ///
  /// **This MUTATES the DOM** — it writes inline `!important` declarations onto
  /// every animated element. That is fine for a screenshot and wrong for an
  /// observation: `lens dom`, `lens tokens` and `lens a11y` would report
  /// injected inline styles that are nowhere in the source. Those verbs stay on
  /// [navigateAndSettle] for exactly this reason. Pixels here, data there.
  ///
  /// Returns what it actually froze, per kind. A caller that gets
  /// `{finite: 0, infinite: 0}` on a page it believes is animated has learned
  /// something — a silent no-op would not have told it.
  Future<Map<String, int>> freezeAnimations() async {
    final result = await evaluate(r'''
(function () {
  var finite = 0, infinite = 0, smil = 0, videos = 0, committed = 0;
  var SKIP = {offset: 1, computedOffset: 1, easing: 1, composite: 1};
  var targets = [];
  var list = document.getAnimations ? document.getAnimations() : [];
  for (var i = 0; i < list.length; i++) {
    var a = list[i];
    try {
      var timing = a.effect && a.effect.getComputedTiming
        ? a.effect.getComputedTiming() : null;
      var end = timing ? timing.endTime : null;
      if (end == null || !isFinite(end)) {
        a.pause(); a.currentTime = 0; infinite++;
      } else {
        a.finish(); finite++;
      }
      // Collect the element + which properties this animation drives, so the
      // de-promotion pass below knows what to preserve.
      if (a.effect && a.effect.target && a.effect.getKeyframes) {
        var props = {};
        var frames = a.effect.getKeyframes();
        for (var f = 0; f < frames.length; f++) {
          for (var key in frames[f]) {
            if (!SKIP[key]) props[key] = 1;
          }
        }
        targets.push({el: a.effect.target, props: props});
      }
    } catch (e) { /* a detached or already-finished animation is fine */ }
  }
  // Second pass, after every animation is pinned: read the settled computed
  // value of each animated property, write it inline as !important, then drop
  // the animation so the element leaves the compositor.
  for (var t = 0; t < targets.length; t++) {
    try {
      var el = targets[t].el;
      if (!el.style) continue;
      var cs = getComputedStyle(el);
      for (var camel in targets[t].props) {
        var kebab = camel.replace(/[A-Z]/g, function (m) {
          return '-' + m.toLowerCase();
        });
        var value = cs.getPropertyValue(kebab);
        if (value) el.style.setProperty(kebab, value, 'important');
      }
      el.style.setProperty('animation', 'none', 'important');
      el.style.setProperty('transition', 'none', 'important');
      committed++;
    } catch (e) { /* cross-origin or detached target */ }
  }
  // SMIL and video: the ACTION is unconditional (a page can restart a video
  // between passes, so re-pausing must always happen) but the COUNT is of
  // elements this call is seeing for the first time.
  //
  // Measured 2026-08-21: without the mark, a second call recounts every svg
  // and video still in the DOM — including static, never-animated ones. That
  // made `smil`/`videos` element censuses rather than freeze counts, so a
  // second pass reported the same numbers as the first whether or not
  // anything new had appeared. Two consequences, both bad: a caller could not
  // use them to detect late-arriving media, and anything summing them would
  // fire on every page containing an <svg>. The expando is a JS property, not
  // an attribute, so it cannot match a selector or change a screenshot.
  var svgs = document.querySelectorAll('svg');
  for (var j = 0; j < svgs.length; j++) {
    try {
      svgs[j].pauseAnimations();
      if (!svgs[j].__abxFrozen) { svgs[j].__abxFrozen = true; smil++; }
    } catch (e) {}
  }
  var vids = document.querySelectorAll('video');
  for (var k = 0; k < vids.length; k++) {
    try {
      vids[k].pause(); vids[k].currentTime = 0;
      if (!vids[k].__abxFrozen) { vids[k].__abxFrozen = true; videos++; }
    } catch (e) {}
  }
  return {finite: finite, infinite: infinite, smil: smil, videos: videos,
          committed: committed};
})()
''');
    return (result as Map).map((k, v) => MapEntry('$k', v as int));
  }

  /// Capture repeatedly until [consecutive] captures in a row are byte-equal,
  /// or [timeoutMs] elapses. Returns how long it took and whether it converged.
  ///
  /// This is the signal-agnostic backstop, and the only settle step that does
  /// not depend on enumerating the right readiness signals — it is what
  /// Playwright actually does. A fixed `Future.delayed` is deterministic only
  /// while page load time is constant; vary the load and the same timer lands
  /// at a different point in the render, which is the measured defect this
  /// replaces (variable-load page × 5 at a fixed 1500ms settle → 2 distinct
  /// images).
  ///
  /// [minWaitMs] is a floor before the first capture. Without it a framework
  /// page that has fired `load` but not yet painted returns two identical
  /// BLANK frames and "converges" instantly on the wrong picture.
  ///
  /// Known and accepted failure mode: a stable-but-wrong state passes. A page
  /// with a running infinite animation cannot converge at all — it burns the
  /// full timeout and then captures at an arbitrary phase. Freeze animations
  /// before calling this, or don't call it (the motion verbs need them live).
  ///
  /// Returns `converged: false` on timeout rather than throwing, but the
  /// caller MUST NOT read that as success — a timed-out settle is precisely
  /// the "did not run" outcome wearing a "passed" coat.
  Future<({int elapsedMs, bool converged, int captures})> settleUntilStable({
    int pollMs = 120,
    int timeoutMs = 6000,
    int minWaitMs = 150,
    int consecutive = 2,
    bool fullPage = false,
  }) async {
    final started = DateTime.now();
    if (minWaitMs > 0) await Future.delayed(Duration(milliseconds: minWaitMs));
    String? prev;
    var matches = 0;
    var captures = 0;
    while (DateTime.now().difference(started).inMilliseconds < timeoutMs) {
      final shot = await _screenshotB64(fullPage: fullPage);
      captures++;
      if (prev != null && shot == prev) {
        // `consecutive` counts CAPTURES that agree, so the first agreement is
        // already two matching captures — hence the `+ 1`.
        if (++matches + 1 >= consecutive) {
          return (
            elapsedMs: DateTime.now().difference(started).inMilliseconds,
            converged: true,
            captures: captures,
          );
        }
      } else {
        matches = 0;
      }
      prev = shot;
      await Future.delayed(Duration(milliseconds: pollMs));
    }
    return (
      elapsedMs: DateTime.now().difference(started).inMilliseconds,
      converged: false,
      captures: captures,
    );
  }

  /// The full settle sequence for a *capture*. Call this instead of
  /// [navigateAndSettle] anywhere the output is a golden, a diff, or a gate.
  ///
  /// The order is not arbitrary — every step is here because leaving it out was
  /// measured to break something (5 captures per page, fresh Chrome each time):
  ///
  /// | page          | flat 1500ms | loop only        | this sequence |
  /// |---------------|-------------|------------------|---------------|
  /// | static        | 1 distinct  | 1 distinct 339ms | 1 distinct    |
  /// | animated      | 4 distinct  | 5 distinct, TIMEOUT ×5 | 1 distinct |
  /// | variable-load | 2 distinct  | 2 distinct       | 1 distinct    |
  ///
  /// 1. **Freeze early.** An infinite animation never stops changing, so the
  ///    loop below can never converge on it — it would burn the whole timeout
  ///    (measured: 6.1s every time) and then capture an arbitrary frame anyway.
  /// 2. **Floor ([minWaitMs]).** The loop's failure mode is converging on the
  ///    "before" state: a page that fetches and renders 300ms after `load`
  ///    looks perfectly stable at 150ms. The floor defaults to the same 1500ms
  ///    the old flat settle used, so this is never *earlier* than the old path
  ///    — only later when the page is genuinely still moving.
  /// 3. **Loop** until two consecutive captures match.
  /// 4. **Freeze again.** Anything that started during the floor — a transition
  ///    fired by late-arriving data — did not exist at step 1. This pass also
  ///    de-promotes it off the compositor, which is what actually buys the
  ///    byte-determinism (see [freezeAnimations]).
  /// 5. **Short loop** to let that de-promotion repaint.
  ///
  /// Not covered, honestly: GIF/APNG (no pause API exists), cross-origin
  /// iframes, and a page that is stable-but-wrong for longer than [minWaitMs].
  Future<({int elapsedMs, bool converged, Map<String, int> frozen, int screenshots, Map<String, int> frozenLate})>
      settleForCapture({
    int minWaitMs = 1500,
    int pollMs = 120,
    int timeoutMs = 8000,
    bool fullPage = false,
  }) async {
    final started = DateTime.now();
    // The FIRST freeze is the meaningful one and must be the one reported.
    // This returned the second until 2026-08-21, which inverted the
    // diagnostic exactly: the first pass writes `animation: none !important`
    // onto every animated element, so the second finds nothing left and
    // returns all zeros — on a correctly frozen page. That made `frozen`'s
    // "it worked" value identical to its "it never ran" value, the precise
    // failure shape [freezeAnimations] warns about when it says a caller
    // seeing `{finite: 0, infinite: 0}` on a page it believes is animated
    // "has learned something". Routed through here, every caller saw that
    // always. Caught by a warm-Chrome probe that asserted `committed > 0`
    // and found the assertion fires when the freeze is WORKING.
    final frozen = await freezeAnimations();
    if (minWaitMs > 0) await Future.delayed(Duration(milliseconds: minWaitMs));
    final first = await settleUntilStable(
      pollMs: pollMs,
      timeoutMs: timeoutMs,
      minWaitMs: 0,
      fullPage: fullPage,
    );
    // The second pass catches what STARTED during the floor — a transition
    // fired by late-arriving data. Non-zero here is the interesting case, and
    // it is reported separately rather than summed: adding them would hide
    // which pass did the work, and "18 frozen at load" and "18 that appeared
    // mid-settle" are different pages with different problems.
    final frozenLate = await freezeAnimations();
    final second = await settleUntilStable(
      pollMs: pollMs,
      timeoutMs: timeoutMs ~/ 4,
      minWaitMs: 0,
      fullPage: fullPage,
    );
    // Either loop failing to converge means the capture is not trustworthy.
    // Reporting `true` because the *second* one happened to settle would be
    // the "pass outcome == did-not-run outcome" bug this codebase keeps
    // getting bitten by.
    final converged = first.converged && second.converged;
    // Warn HERE, not at the call sites. Returning the flag and trusting six
    // callers to check it is how this becomes silent again the first time
    // someone adds a seventh — and a non-converged settle is exactly the
    // failure that looks like success. Real cases that land here: an animated
    // GIF or APNG (no pause API exists, so nothing can freeze them), a widget
    // repainting on setInterval, a video that keeps buffering.
    if (!converged) {
      stderr.writeln('lens: SETTLE DID NOT CONVERGE after ${elapsed(started)}ms '
          '(loop1 ${first.converged ? "ok" : "timed out"}, '
          'loop2 ${second.converged ? "ok" : "timed out"}) — this capture is '
          'NOT reproducible. Likely an animated GIF/APNG, a timer-driven '
          'repaint, or a video.');
    }
    // Same reasoning as `converged` above, for the same reason it needs saying
    // twice: `frozenLate` was returned and read by nothing but its own test —
    // measured, correct, and discarded by every caller. That is the third
    // shape of "pass outcome == did-not-run outcome" this codebase collects,
    // and shipping a field nobody reads is worse than shipping none, because
    // its presence reads as coverage.
    //
    // Non-zero is not a failure: loop 2 ran after this pass and converged, so
    // the capture is sound. It means the two-pass depth was LOAD-BEARING on
    // this page — a third wave of animations would land after loop 2 with
    // nothing left to catch it. So it is a warning, not an error, and the page
    // it names is the first place to look when a capture drifts anyway.
    // All four categories, not just the CSS pair: a lazy-loaded <video> or an
    // SVG injected with the content is the canonical "appears after load"
    // case, and counting only finite+infinite would leave exactly those two
    // silent. This sum is only meaningful because [freezeAnimations] counts
    // each element once per page — see the expando there.
    final late = (frozenLate['finite'] ?? 0) +
        (frozenLate['infinite'] ?? 0) +
        (frozenLate['smil'] ?? 0) +
        (frozenLate['videos'] ?? 0);
    if (late > 0) {
      stderr.writeln('lens: $late animation(s)/media element(s) APPEARED '
          'during settle and were frozen by the second pass '
          '(finite ${frozenLate['finite']}, infinite ${frozenLate['infinite']}, '
          'smil ${frozenLate['smil']}, video ${frozenLate['videos']}). The '
          'capture is settled, but this page needed both passes — if it ever '
          'drifts, start here.');
    }
    return (
      elapsedMs: elapsed(started),
      converged: converged,
      frozen: frozen,
      // The two loops' screenshot counts were computed and thrown away until
      // 2026-08-21, which made this method's real cost unobservable from
      // outside. That is not academic: a warm-Chrome memory probe had to
      // REPLICATE the whole sequence out of public methods just to learn the
      // rate, because the genuine method would not say. Excludes the caller's
      // own final screenshot(), which happens after this returns — typically
      // 4 here, 5 end to end, and ~66 when a loop times out at the default
      // 8000ms/120ms poll. That spread is why callers should report a
      // distribution and never a mean.
      screenshots: first.captures + second.captures,
      frozenLate: frozenLate,
    );
  }

  /// Milliseconds since [from]. Named so the settle code reads as prose.
  static int elapsed(DateTime from) =>
      DateTime.now().difference(from).inMilliseconds;

  /// Navigate and run the full capture settle. The drop-in replacement for
  /// [navigateAndSettle] on every still-image path; the motion verbs
  /// (`anim`, `record`, `flipbook`, `burst`, `states`) must NOT use it — they
  /// exist to observe animation, and this deliberately destroys it.
  Future<({int elapsedMs, bool converged, Map<String, int> frozen, int screenshots, Map<String, int> frozenLate})>
      navigateAndSettleForCapture(
    String url, {
    int settleMs = 1500,
    int timeoutMs = 8000,
    bool fullPage = false,
  }) async {
    await navigate(url);
    if (LensSession.visible) await injectLensGlow();
    final r = await settleForCapture(
      minWaitMs: settleMs,
      timeoutMs: timeoutMs,
      fullPage: fullPage,
    );
    if (LensSession.visible) await removeLensGlow();
    return r;
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
    return base64Decode(await _screenshotB64(fullPage: fullPage));
  }

  /// The raw base64 payload, before decode. [settleUntilStable] compares
  /// hundreds of these; decoding each one to bytes only to throw them away
  /// would triple the cost of the loop for nothing.
  Future<String> _screenshotB64({bool fullPage = false}) async {
    final params = <String, dynamic>{
      'format': 'png',
      'fromSurface': true,
    };
    if (fullPage) params['captureBeyondViewport'] = true;

    final res = await send('Page.captureScreenshot', params);
    // Counted HERE and nowhere else: this is the one chokepoint both
    // `screenshot()` and the settle loop pass through, and the lens daemon's
    // recycle policy is denominated in screenshots, not captures. A caller
    // counting its own captures undercounts by 4-6x, because settleForCapture
    // takes that many per capture depending on the page — the policy would
    // fire an order of magnitude late.
    _client._screenshotsTaken++;
    return res['result']['data'] as String;
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

  /// Move the pointer onto the first element matching [selector], without
  /// clicking. Returns false if it never appeared.
  ///
  /// The reveal-then-act shape: hover a tile to bring out its tool rail, then
  /// click a tool that did not exist as a hit target a moment ago. [clickSelector]
  /// hovers its own target, which is not the same thing — there the pointer
  /// lands on the element being clicked, and here it lands on that element's
  /// container.
  ///
  /// [selector] should target the container, not the revealed child: aiming
  /// at the child instead works by accident on a rail that overlaps its
  /// container and not at all on one that does not.
  ///
  /// Deliberately does not wait for whatever the hover reveals: this verb
  /// cannot know what that is. Follow it with the [clickSelector] or
  /// [waitForSelector] for the revealed element, which waits on its own.
  Future<bool> hoverSelector(
    String selector, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!await waitForSelector(selector, timeout: timeout)) return false;
    final centre = await _centreOf(jsonEncode(selector), scroll: true);
    if (centre == null) return false;
    await hover(centre.$1, centre.$2);
    return true;
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

  // ── frames ───────────────────────────────────────────────────────────────
  //
  // Everything above this line addresses the top-level document. The studio
  // renders every screen inside an `<iframe>`, so without these a probe can
  // assert on the box around a screen but never on the screen.
  //
  // Reading a same-origin child through the parent's `contentDocument` looks
  // like a way around all of this, and for a plain DOM read it is one. It is
  // wrong for the two things in-frame checks actually ask:
  //
  // - `window.parent.htmx` evaluated in the PARENT resolves against the
  //   parent's own window, so the bridge check passes whether or not code
  //   inside the frame can reach it. The assertion becomes vacuous, which is
  //   the failure mode this whole suite exists to avoid.
  // - the viewer CSS-`scale`s its tiles. `iframeRect.left + elementRect.left`
  //   is the obvious arithmetic and it is off by that scale factor, so the
  //   pointer lands outside the element it was aimed at.

  /// Enable the DOM domain, once per session.
  ///
  /// Not folded into [enable]: only the quad lookup below needs it, and every
  /// session that never touches a frame would otherwise pay for the node
  /// bookkeeping it turns on.
  Future<void> _enableDom() async {
    if (_domEnabled) return;
    await send('DOM.enable');
    _domEnabled = true;
  }

  /// Release a remote object handle, ignoring a failure to.
  ///
  /// Best-effort on purpose: the handle is already unreachable if the frame
  /// navigated out from under it, and turning that into a thrown error would
  /// fail a probe on cleanup after its actual work succeeded.
  Future<void> _releaseObject(String objectId) async {
    try {
      await send('Runtime.releaseObject', {'objectId': objectId});
    } on CdpException {
      // already gone
    }
  }

  /// Every frame in this page, root first, each parent before its children.
  Future<List<CdpFrame>> frames() async {
    final res = await send('Page.getFrameTree');
    final out = <CdpFrame>[];
    void walk(Map<String, dynamic> node) {
      final f = node['frame'] as Map<String, dynamic>;
      out.add(CdpFrame(
        id: '${f['id']}',
        parentId: f['parentId'] as String?,
        url: '${f['url'] ?? ''}',
        name: '${f['name'] ?? ''}',
      ));
      for (final child in (node['childFrames'] as List? ?? const [])) {
        walk((child as Map).cast<String, dynamic>());
      }
    }

    walk((res['result']['frameTree'] as Map).cast<String, dynamic>());
    return out;
  }

  /// The frame owned by the `<iframe>` matching [selector], or null when no
  /// such element is on the page or it owns no frame.
  ///
  /// Resolved through the element rather than by matching [frames] on URL:
  /// two tiles routinely show the same screen, and a URL match would return
  /// whichever of them the frame tree happened to list first.
  Future<CdpFrame?> frameForSelector(
    String selector, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!await waitForSelector(selector, timeout: timeout, visible: false)) {
      return null;
    }
    await _enableDom();
    final handle = await send('Runtime.evaluate', {
      'expression': 'document.querySelector(${jsonEncode(selector)})',
      'returnByValue': false,
    });
    final objectId =
        (handle['result']['result'] as Map?)?['objectId'] as String?;
    if (objectId == null) return null;
    String? frameId;
    try {
      final described = await send('DOM.describeNode', {'objectId': objectId});
      frameId = ((described['result']['node'] as Map?)?['frameId']) as String?;
    } on CdpException {
      frameId = null;
    } finally {
      await _releaseObject(objectId);
    }
    if (frameId == null) return null;
    for (final f in await frames()) {
      if (f.id == frameId) return f;
    }
    return null;
  }

  /// The execution context [frame] currently runs in.
  ///
  /// Polls rather than reading the map once: a frame is announced in the frame
  /// tree before its context exists, so resolving a frame and immediately
  /// evaluating in it is a race that a single lookup loses.
  Future<int> _contextIdFor(CdpFrame frame,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final id = _frameContexts[frame.id];
      if (id != null) return id;
      if (!DateTime.now().isBefore(deadline)) {
        throw CdpException(
            'frame ${frame.id} (${frame.url}) has no execution context after'
            ' ${timeout.inMilliseconds}ms — it never finished loading, or it is'
            ' cross-origin and runs in a target this session is not attached to',
            -32000);
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// True when [e] is Chrome refusing a context id it has already torn down.
  static bool _isStaleContext(CdpException e) =>
      e.message.contains('Cannot find context');

  /// Evaluate [expression] inside [frame]'s own page world.
  ///
  /// Retries once on a stale context. The studio arms a tile by re-navigating
  /// its iframe, so "resolve the frame, then read it" has a real window in
  /// which the context named by the first step no longer exists by the second.
  /// One retry closes that window; a second failure is a genuine one and
  /// propagates.
  Future<dynamic> evaluateInFrame(
    CdpFrame frame,
    String expression, {
    bool awaitPromise = true,
  }) async {
    try {
      return await _evaluateInFrameOnce(frame, expression, awaitPromise);
    } on CdpException catch (e) {
      if (!_isStaleContext(e)) rethrow;
      _frameContexts.remove(frame.id);
      return await _evaluateInFrameOnce(frame, expression, awaitPromise);
    }
  }

  Future<dynamic> _evaluateInFrameOnce(
      CdpFrame frame, String expression, bool awaitPromise) async {
    final res = await send('Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
      'awaitPromise': awaitPromise,
      'contextId': await _contextIdFor(frame),
    });
    final result = res['result'] as Map<String, dynamic>;
    if (result['exceptionDetails'] != null) {
      final details = result['exceptionDetails'] as Map<String, dynamic>;
      throw CdpException(
          'evaluateInFrame threw: ${details['text']} ${details['exception']?['description'] ?? ''}',
          -32000);
    }
    return (result['result'] as Map<String, dynamic>)['value'];
  }

  /// [waitForFunction], scoped to [frame].
  Future<bool> waitForFunctionInFrame(
    CdpFrame frame,
    String expression, {
    Duration timeout = const Duration(seconds: 8),
    Duration polling = const Duration(milliseconds: 100),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await evaluateInFrame(frame, expression) == true) return true;
      } on CdpException {
        // The frame is mid-navigation, or the expression touched something not
        // there yet. Both are ordinary while waiting; keep polling.
      }
      await Future.delayed(polling);
    }
    return false;
  }

  /// Top-level viewport centre of [selector] inside [frame], or null if gone.
  ///
  /// The quads come from `DOM.getContentQuads`, which reports in the main
  /// frame's coordinate space with every transform between the element and the
  /// top document already applied. That is the whole reason this is not
  /// in-frame `getBoundingClientRect()` plus the iframe's offset: the viewer
  /// scales its tiles, and the two spaces differ by exactly that scale.
  /// Centre and size of [sel] inside [frame], in top-level viewport pixels.
  ///
  /// [sel] is a JSON-encoded selector, matching [_centreOf]'s contract. The
  /// size comes back because [hoverSelectorInFrame] needs a second point that
  /// is provably still inside the same element, and the element's own extent
  /// is the only thing that can say how far away that may be.
  Future<({int x, int y, int w, int h})?> _boxOfInFrame(
    CdpFrame frame,
    String sel, {
    required bool scroll,
  }) async {
    await _enableDom();
    final handle = await send('Runtime.evaluate', {
      'expression': '(() => { const e = document.querySelector($sel);'
          ' if (!e) return null;'
          "${scroll ? " e.scrollIntoView({block: 'center', inline: 'center'});" : ''}"
          ' return e; })()',
      'returnByValue': false,
      'contextId': await _contextIdFor(frame),
    });
    final objectId =
        (handle['result']['result'] as Map?)?['objectId'] as String?;
    if (objectId == null) return null;
    try {
      final res = await send('DOM.getContentQuads', {'objectId': objectId});
      final quads = res['result']['quads'] as List?;
      if (quads == null || quads.isEmpty) return null;
      final q = (quads.first as List).cast<num>();
      // A quad is x1,y1,x2,y2,x3,y3,x4,y4; its centre is the mean of the four
      // corners, which is right for a rotated box as well as an upright one.
      var x = 0.0, y = 0.0;
      var minX = double.infinity, maxX = -double.infinity;
      var minY = double.infinity, maxY = -double.infinity;
      for (var i = 0; i < 8; i += 2) {
        x += q[i];
        y += q[i + 1];
        minX = q[i] < minX ? q[i].toDouble() : minX;
        maxX = q[i] > maxX ? q[i].toDouble() : maxX;
        minY = q[i + 1] < minY ? q[i + 1].toDouble() : minY;
        maxY = q[i + 1] > maxY ? q[i + 1].toDouble() : maxY;
      }
      return (
        x: (x / 4).round(),
        y: (y / 4).round(),
        w: (maxX - minX).round(),
        h: (maxY - minY).round(),
      );
    } on CdpException {
      // No layout box: display:none, or detached between the two calls.
      return null;
    } finally {
      await _releaseObject(objectId);
    }
  }

  /// Wait for [selector] inside [frame] to have a layout box that has stopped
  /// moving, and return it.
  ///
  /// Existence is not enough, and this is where the top-level verbs' use of
  /// `waitForSelector(visible: true)` has to be re-earned for frames. Arming a
  /// tile re-navigates its iframe, and the studio brings the tile back through
  /// a view transition, so an element can be present and answer with a box
  /// that is still on its way to where it will end up. A pointer aimed at that
  /// box lands next to the element rather than on it — no `pointermove` on any
  /// `[data-el]`, no island reaction, and a probe that reports a broken
  /// inspector because it measured too early.
  ///
  /// Two identical measurements [settleMs] apart is the test. Zero-sized boxes
  /// never count as settled: an element that is present but not yet laid out
  /// reports 0×0 consistently, which a bare equality check would accept.
  Future<({int x, int y, int w, int h})?> _settledBoxInFrame(
    CdpFrame frame,
    String selector, {
    required Duration timeout,
    required bool scroll,
    int settleMs = 60,
  }) async {
    final sel = jsonEncode(selector);
    final deadline = DateTime.now().add(timeout);
    ({int x, int y, int w, int h})? prev;
    while (DateTime.now().isBefore(deadline)) {
      ({int x, int y, int w, int h})? now;
      try {
        now = await _boxOfInFrame(frame, sel, scroll: scroll);
      } on CdpException {
        now = null; // frame mid-navigation; keep waiting
      }
      if (now != null && now.w > 0 && now.h > 0 && now == prev) return now;
      prev = now;
      await Future.delayed(Duration(milliseconds: settleMs));
    }
    return prev != null && prev.w > 0 && prev.h > 0 ? prev : null;
  }

  /// [hover], on an element inside [frame]. False when it never appeared.
  Future<bool> hoverSelectorInFrame(
    CdpFrame frame,
    String selector, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final box = await _settledBoxInFrame(frame, selector,
        timeout: timeout, scroll: true);
    if (box == null) return false;
    // TWO moves, and the offset on the first is load-bearing.
    //
    // The first `mouseMoved` that crosses into a child document delivers
    // pointerover/mouseover to it but NO pointermove: the child's pointer
    // state is created by that very event, so there is no previous position to
    // have moved from. An island that tracks hovers the ordinary way — by
    // listening for `pointermove` — therefore never hears a single-dispatch
    // hover arrive. Measured against the studio's inspect island on a frame
    // the pointer had not yet entered: one move in produced 1 pointerover and
    // 0 pointermove, and the inspector pane never updated.
    //
    // Approaching in two steps makes the second dispatch a move WITHIN the
    // frame, which is what a real pointer does: it arrives along a path rather
    // than teleporting. The step must be big enough not to be coalesced away —
    // a 1px approach measured the same 0 pointermove as no approach at all —
    // and small enough to stay inside the element, or the two points hit
    // different targets and the hover reports on the wrong one. A quarter of
    // the element's shorter side is inside it by construction; the 2px floor
    // keeps the step real for an element too small for that to matter.
    final step = [(box.w < box.h ? box.w : box.h) ~/ 4, 2]
        .reduce((a, b) => a > b ? a : b);
    // Chrome also coalesces moves that land in the same compositor frame, so
    // the dispatches are spaced: back to back they arrive as the one move this
    // is here to avoid being. A frame is ~16ms; 40 leaves room on a loaded
    // machine. Three points rather than two because a single approach was
    // measured landing both ways on the same machine — with one intermediate
    // point the arrival is a move from a position the frame already knows,
    // whichever of them registered first.
    for (var i = 2; i >= 0; i--) {
      await hover(box.x - step * i ~/ 2, box.y - step * i ~/ 2);
      await Future.delayed(const Duration(milliseconds: 40));
    }
    return true;
  }

  /// [clickSelector], on an element inside [frame]. False when it never
  /// appeared.
  ///
  /// Hover-then-click for the same reason the top-level version is: the box is
  /// re-measured after the hover, because a hover can move what it revealed.
  /// [synthetic] dispatches the DOM event instead of steering the pointer, for
  /// a target a real pointer cannot reach in a headless run.
  Future<bool> clickSelectorInFrame(
    CdpFrame frame,
    String selector, {
    Duration timeout = const Duration(seconds: 8),
    bool synthetic = false,
  }) async {
    if (!await waitForFunctionInFrame(
        frame, 'document.querySelector(${jsonEncode(selector)}) !== null',
        timeout: timeout)) {
      return false;
    }
    if (synthetic) {
      return await evaluateInFrame(
              frame,
              '(() => { const e = document.querySelector(${jsonEncode(selector)});'
              ' if (!e) return false; e.click(); return true; })()') ==
          true;
    }
    if (!await hoverSelectorInFrame(frame, selector, timeout: timeout)) {
      return false;
    }
    // Re-measured after the hover, for the same reason clickSelector does it:
    // revealing something can move it.
    final box = await _settledBoxInFrame(frame, selector,
        timeout: timeout, scroll: false);
    if (box == null) return false;
    await click(box.x, box.y);
    return true;
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
  ///
  /// [beforeRelease] runs after the final move and before the release, with
  /// the button still down. Some state only exists during a drag — a size
  /// badge that `pointerup` removes, a request attributable to the release
  /// specifically — and reading it afterwards finds nothing, which is worse
  /// than failing: an assertion against a vanished element passes vacuously.
  /// Capture what you need through a closure:
  ///
  /// ```dart
  /// String? badge;
  /// await session.drag(x1, y1, x2, y2, beforeRelease: () async {
  ///   badge = await session.evaluate("document.querySelector('.badge')?.textContent");
  /// });
  /// ```
  ///
  /// The release is in a `finally`: a throw from [beforeRelease], or from any
  /// move, must not leave the button down. One stuck button would corrupt
  /// every later interaction in the same browser — and the probe runner shares
  /// one browser across a whole suite, so that damage would land on some other
  /// probe and be diagnosed there.
  Future<void> drag(
    int fromX,
    int fromY,
    int toX,
    int toY, {
    int steps = 14,
    Duration stepDelay = const Duration(milliseconds: 16),
    Future<void> Function()? beforeRelease,
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
    try {
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
      if (beforeRelease != null) await beforeRelease();
    } finally {
      await send('Input.dispatchMouseEvent', {
        'type': 'mouseReleased',
        'x': toX,
        'y': toY,
        'button': 'left',
        'buttons': 0,
        'clickCount': 1,
      });
    }
  }

  /// Drag the element matching [selector] by ([dx], [dy]) viewport pixels.
  /// Returns false if the element is not there to grab.
  ///
  /// [beforeRelease] is forwarded to [drag] — see there for what it is for.
  Future<bool> dragSelector(
    String selector, {
    required int dx,
    required int dy,
    int steps = 14,
    Duration timeout = const Duration(seconds: 8),
    Future<void> Function()? beforeRelease,
  }) async {
    if (!await waitForSelector(selector, timeout: timeout)) return false;
    final from = await _centreOf(jsonEncode(selector), scroll: true);
    if (from == null) return false;
    await drag(from.$1, from.$2, from.$1 + dx, from.$2 + dy,
        steps: steps, beforeRelease: beforeRelease);
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

  /// Inject the arxa lens status glow: an animated inset border + a corner
  /// status pill, colored by [LensSession.verb]. Appended to documentElement
  /// so body-scoped probes (tokens) never see it. No-op if already present.
  Future<void> injectLensGlow() async {
    final verb = LensSession.verb ?? 'lens';
    final color = lensGlowColors[verb] ?? '#38bdf8';
    final detail = LensSession.detail;
    final label = detail == null ? verb : '$verb · $detail';
    final labelJson = jsonEncode('◉ arxa lens · $label');
    await evaluate('''
(function(){
  if (document.getElementById('arxa-lens-glow')) return;
  var c = ${jsonEncode(color)}, label = $labelJson;
  var s = document.createElement('style'); s.id='arxa-lens-glow-style';
  s.textContent='@keyframes arxa-lens-breathe{0%,100%{opacity:.2}50%{opacity:.42}}';
  var b = document.createElement('div'); b.id='arxa-lens-glow';
  b.style.cssText='position:fixed;inset:0;pointer-events:none;z-index:2147483647;box-shadow:inset 0 0 0 2px '+c+', inset 0 0 60px 6px '+c+';animation:arxa-lens-breathe 1s ease-in-out infinite;';
  var p = document.createElement('div'); p.id='arxa-lens-glow-label';
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
  ['arxa-lens-glow','arxa-lens-glow-style','arxa-lens-glow-label']
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
      case 'Runtime.executionContextCreated':
        final context = event.params['context'] as Map<String, dynamic>?;
        final aux = context?['auxData'] as Map<String, dynamic>?;
        // Only the default world is recorded. An isolated world shares the
        // frame's DOM but not its JavaScript, so page globals an in-frame
        // check reads — `document._inspect`, `window.parent.htmx` — are simply
        // absent there. A probe pointed at an isolated world would report a
        // working island broken, which is worse than not reaching the frame.
        if (context != null &&
            aux != null &&
            aux['isDefault'] == true &&
            aux['frameId'] is String &&
            context['id'] is num) {
          _frameContexts['${aux['frameId']}'] = (context['id'] as num).toInt();
        }
        break;
      case 'Runtime.executionContextDestroyed':
        final gone = (event.params['executionContextId'] as num?)?.toInt();
        if (gone != null) _frameContexts.removeWhere((_, id) => id == gone);
        break;
      case 'Runtime.executionContextsCleared':
        _frameContexts.clear();
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

/// One frame in a page's frame tree.
///
/// A handle, not a snapshot of state: [id] is stable across the frame's
/// navigations, which is what makes it usable to re-resolve an execution
/// context after the frame reloads. [url] is the URL at the moment [frames]
/// was called and can be stale by the next line.
class CdpFrame {
  /// Chrome's frame id. Stable for the life of the frame.
  final String id;

  /// The parent frame's id, or null for the main frame.
  final String? parentId;

  /// The frame's URL when it was enumerated.
  final String url;

  /// The `name`/`id` attribute of the owning `<iframe>`, or ''.
  final String name;

  const CdpFrame({
    required this.id,
    required this.parentId,
    required this.url,
    required this.name,
  });

  /// True for the page's top-level frame.
  bool get isMain => parentId == null;

  @override
  String toString() => 'CdpFrame($id${isMain ? ', main' : ''}, $url)';
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

