// arxa-builder: status surface over the TransportService stream; retries per
// dial-attempt constants live in the real transport, not here.
import 'dart:async';

import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show BaseViewModel, RouterService;

import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app.router.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

class PairingConnectingViewModel extends BaseViewModel {
  final _transport = locator<TransportService>();
  final _router = locator<RouterService>();

  StreamSubscription<ArxaConnectionStatus>? _sub;
  bool _handedOff = false;

  ArxaConnectionState get state => _transport.current.state;
  String? get connectionError => _transport.current.error;

  void start() {
    _sub = _transport.status.listen((s) {
      notifyListeners();
      if (s.state == ArxaConnectionState.connected) _handoff();
    });
    if (state == ArxaConnectionState.connected) _handoff();
  }

  void _handoff() {
    if (_handedOff) return;
    _handedOff = true;
    // First pair: push permission before the session handoff.
    _router.replaceWith(PairingPushPermissionViewRoute());
  }

  Future<void> refresh() async {}

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
