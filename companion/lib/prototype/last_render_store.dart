import 'package:flutter/foundation.dart';

/// What the WebView is showing.
///
/// Deliberately decoupled from [PrototypeChannelService]. A WebView loads a URL
/// once and keeps the rendered page even after its origin dies — a browser
/// does not blank a loaded page when the server goes away. That persistence is
/// exactly why the FAB must read the channel heartbeat and **not** this store:
/// a non-null [lastUrl] after the server is killed is the stale-render failure
/// mode, not evidence of liveness.
///
/// This store only changes when a **new** render is served — never when the
/// channel dies. The harness proof asserts that invariant (kill the server and
/// the render is unchanged while the FAB reads dead).
class LastRenderStore extends ChangeNotifier {
  String? _url;
  DateTime? _loadedAt;

  /// The URL the WebView currently shows, or null before the first serve.
  String? get lastUrl => _url;
  DateTime? get loadedAt => _loadedAt;
  bool get hasRender => _url != null;

  /// Record a freshly served render. Called when the desktop delivers a new
  /// prototype URL over the channel — not on every heartbeat.
  void serve(String url) {
    _url = url;
    _loadedAt = DateTime.now();
    notifyListeners();
  }

  /// Explicitly drop the render (e.g. the user leaves the prototype view).
  /// There is no `clearOnChannelDeath` — that method is intentionally absent.
  void clear() {
    _url = null;
    _loadedAt = null;
    notifyListeners();
  }
}
