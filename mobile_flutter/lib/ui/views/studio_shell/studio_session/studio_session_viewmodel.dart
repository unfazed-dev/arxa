// arxa-builder: webview handoff — loads the transport's studioUrl
// (loopback proxy, http://127.0.0.1:<port>/), UA pinned to ArxaShell/0.1.
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

  Uri? get studioUrl => _transport.current.studioUrl;

  void start() {
    final url = studioUrl;
    if (url == null) return; // not connected — view shows the fallback
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(userAgent)
      ..loadRequest(url);
    notifyListeners();
  }

  Future<void> openSettings() =>
      _router.navigateTo(SettingsHomeViewRoute());

  Future<void> refresh() async => start();
}
