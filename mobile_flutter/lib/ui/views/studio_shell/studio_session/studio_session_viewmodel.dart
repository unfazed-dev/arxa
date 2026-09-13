// arxa-builder: webview handoff — loads the transport's studioUrl
// (loopback proxy, http://127.0.0.1:<port>/), UA pinned to ArxaShell/0.1.
import 'dart:async';

import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show BaseViewModel, RouterService;
import 'package:webview_flutter/webview_flutter.dart';

import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app.router.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

class StudioSessionViewModel extends BaseViewModel {
  static const userAgent = 'Mozilla/5.0 (Mobile) ArxaShell/0.1';

  final _transport = locator<TransportService>();
  final _router = locator<RouterService>();

  WebViewController? controller;

  StreamSubscription<ArxaConnectionStatus>? _statusSub;
  bool _leftForPairing = false;

  // Cold-start tunnel flap: the fresh dial settles ~150ms in, and a webview
  // load that lands in that window fails ("Could not connect to the
  // server"). Bounded, backoff retry on main-frame failure — success resets.
  bool _needsReload = false;
  int _loadRetries = 0;

  Uri? get studioUrl => _transport.current.studioUrl;

  void start() {
    // This view is the cold-start home whenever a pairing payload is
    // stored: the boot resume() may still be dialing, so wait for the link
    // here instead of routing through the scanner first.
    _statusSub = _transport.status.listen((s) {
      if (s.state == ArxaConnectionState.connected &&
          (controller == null || _needsReload)) {
        _needsReload = false;
        controller = null;
        _connectWebview();
        notifyListeners();
      } else if (s.state == ArxaConnectionState.notPaired && s.error != null) {
        _leaveForPairing();
      }
    });
    _connectWebview();
  }

  /// Pairing revoked or a terminal dial failure — the scanner is the only
  /// way back (the transport has already wiped the stored payload).
  void _leaveForPairing() {
    if (_leftForPairing) return;
    _leftForPairing = true;
    _router.replaceWith(PairingScanViewRoute());
  }

  void _connectWebview() {
    if (controller != null) return; // webview already built
    final url = studioUrl;
    if (url == null) return; // link not up yet — status listener waits
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (u) => _loadSucceeded(),
          onWebResourceError: _onLoadError,
        ),
      )
      ..loadRequest(url);
    notifyListeners();
  }

  /// Main-frame failure during a tunnel flap must not leave a white
  /// screen: bounded backoff retry (the shell's own web-runtime retries its
  /// lost connections the same way). Success resets the budget; when the
  /// budget is spent the view falls back to its not-connected state.
  void _onLoadError(WebResourceError e) {
    if (e.isForMainFrame != true) return;
    _needsReload = true;
    if (_loadRetries >= 6) {
      controller = null;
      notifyListeners();
      return;
    }
    final delay = Duration(milliseconds: 600 * (1 << _loadRetries));
    _loadRetries += 1;
    Future<void>.delayed(delay).then((_) {
      if (!_needsReload) return;
      final s = _transport.current;
      if (s.state == ArxaConnectionState.connected && s.studioUrl != null) {
        _needsReload = false;
        controller = null;
        _connectWebview();
        notifyListeners();
      }
      // else: the next connected status (listener) carries the retry.
    });
  }

  void _loadSucceeded() {
    _needsReload = false;
    _loadRetries = 0;
  }

  Future<void> openSettings() => _router.navigateTo(SettingsHomeViewRoute());

  /// The approvals shell (B2 phase-1b): the bell lands here so the owner can
  /// review pending asks without leaving the session (back returns here).
  Future<void> openApprovals() => _router.navigateTo(ApprovalsListViewRoute());

  /// The code shell (sessions list): the folder lands here so the owner can
  /// browse code sessions without leaving the session (back returns here).
  Future<void> openCodeSessions() =>
      _router.navigateTo(CodeSessionsViewRoute());

  Future<void> refresh() async {
    _loadSucceeded();
    controller = null;
    _connectWebview();
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}
