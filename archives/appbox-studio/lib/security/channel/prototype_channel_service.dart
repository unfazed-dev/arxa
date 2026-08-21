import 'dart:async';
import 'dart:io';

import '../config/companion_config.dart';
import 'channel_state.dart';

/// Heartbeats the prototype URL over HTTP and emits the channel state
/// (live / reconnecting / dead) the FAB carries.
///
/// This is the paired channel's liveness signal — **not** whether the WebView
/// painted. The companion's WebView loads the URL once and keeps the last
/// render even after the server dies (a browser does not blank a loaded page
/// when its origin goes away). The heartbeat is the only honest way to know
/// the server is still there, which is why the FAB reads [current] and never
/// the WebView. Closes plan-09 done-when #5.
///
/// State machine (driven by [config.deadAfterFailures]):
///   success            → live, reset failure count
///   failure (1..n-1)   → reconnecting
///   failure == n       → dead
///
/// Time-to-dead after a kill is bounded by `deadAfterFailures × heartbeatInterval`,
/// so the FAB reflects death within a heartbeat window, not minutes.
class PrototypeChannelService {
  PrototypeChannelService({required CompanionConfig config, HttpClient? httpClient})
      : _config = config,
        _client = httpClient ?? HttpClient()..connectionTimeout = config.heartbeatTimeout;

  final CompanionConfig _config;
  final HttpClient _client;
  StreamController<ChannelState>? _controller;
  Timer? _timer;
  String? _url;
  int _failures = 0;
  ChannelState _state = ChannelState.reconnecting;
  bool _disposed = false;

  /// The live channel state. The FAB binds to this.
  ///
  /// Replays the current state to each new subscriber (a view that mounts
  /// mid-session must see the state at once, not wait for the next transition),
  /// then forwards subsequent transitions.
  Stream<ChannelState> get states {
    final c = _controller;
    if (c == null) {
      throw StateError('start(url) must be called before reading states');
    }
    final snapshot = _state;
    return Stream.multi((controller) {
      controller.add(snapshot);
      final sub = c.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  /// The most recent state (for synchronous reads, e.g. the FAB's first frame).
  ChannelState get current => _state;

  /// Begin heartbeating [url] — the prototype URL from the P09 ready-line.
  /// Emits the initial state immediately, then polls every heartbeat interval.
  Future<void> start(String url) async {
    if (_disposed) throw StateError('PrototypeChannelService is disposed');
    await stop();
    _url = url;
    _failures = 0;
    _controller = StreamController<ChannelState>.broadcast(sync: true);
    _emit(ChannelState.reconnecting);
    await _beat(); // resolve the first state without waiting a full interval
    _timer = Timer.periodic(_config.heartbeatInterval, (_) => _beat());
  }

  /// Stop heartbeating. Safe to call repeatedly.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _url = null;
    final c = _controller;
    _controller = null;
    if (c != null && !c.isClosed) {
      await c.close();
    }
  }

  Future<void> _beat() async {
    final url = _url;
    if (url == null) return;
    bool ok = false;
    try {
      final req = await _client.getUrl(Uri.parse(url)).timeout(
        _config.heartbeatTimeout,
      );
      final resp = await req.close().timeout(_config.heartbeatTimeout);
      // Any 2xx is alive. A redirect to an error page (3xx/4xx/5xx) is not —
      // the prototype server returns 200 for served routes and 404 otherwise.
      ok = resp.statusCode >= 200 && resp.statusCode < 300;
      // Drain so the socket can be reused by the next heartbeat.
      await resp.drain<void>();
    } on TimeoutException {
      ok = false;
    } on Exception {
      ok = false; // timeout, connection refused, socket closed — all "not alive"
    }

    if (ok) {
      _failures = 0;
      _emit(ChannelState.live);
    } else {
      _failures += 1;
      _emit(
        _failures >= _config.deadAfterFailures
            ? ChannelState.dead
            : ChannelState.reconnecting,
      );
    }
  }

  void _emit(ChannelState next) {
    if (next == _state) return;
    _state = next;
    final c = _controller;
    if (c != null && !c.isClosed) c.add(next);
  }

  /// Release the HTTP client. The service is unusable afterwards.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _controller?.close();
    _client.close();
  }
}
