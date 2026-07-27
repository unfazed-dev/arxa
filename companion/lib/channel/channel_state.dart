/// The channel state the FAB carries (§15).
///
/// This is the liveness of the **paired channel** — the HTTP heartbeat to the
/// prototype server the desktop spawned — and is deliberately independent of
/// whether the WebView last painted. A dead server can leave a stale render on
/// screen; the FAB must say DEAD anyway. That is the failure mode this exists
/// to prevent.
enum ChannelState {
  /// The last heartbeat reached the server. The prototype is live.
  live,

  /// A heartbeat missed; retrying within grace ([reconnectAttempts]) before
  /// declaring death. A single dropped packet must not read as a dead server.
  reconnecting,

  /// [deadAfterFailures] heartbeats have missed in a row. The server is gone.
  /// The WebView may still show the last render — that is stale, not live.
  dead,
}

/// The P09 spawn contract — one JSON object the desktop emits once the
/// prototype server is listening. The companion matches [readyLineTag] to find
/// the URL/port/host in the channel payload, never a literal URL (R3).
///
/// Shape (from `pipeline/prototype/serve.py` + the desktop's
/// `PrototypeServerService`):
/// ```json
/// {"tag":"app-box-prototype-ready","url":"http://...","port":1234,"host":"..."}
/// ```
class ReadyLine {
  static const String tag = 'app-box-prototype-ready';

  final String url;
  final int port;
  final String host;

  const ReadyLine({required this.url, required this.port, required this.host});

  /// Parse the ready-line payload. Returns `null` unless [tag] matches — a
  /// channel that delivers anything else is not the prototype-ready signal.
  static ReadyLine? tryParse(Map<String, dynamic> json) {
    if (json['tag'] != tag) return null;
    final url = json['url'];
    final port = json['port'];
    final host = json['host'];
    if (url is! String || port is! num || host is! String) return null;
    return ReadyLine(url: url, port: port.toInt(), host: host);
  }

  @override
  String toString() => 'ReadyLine(url: $url, port: $port, host: $host)';
}
