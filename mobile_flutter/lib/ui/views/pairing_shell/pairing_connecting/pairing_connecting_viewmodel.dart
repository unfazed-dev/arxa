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
      if (s.state == ArxaConnectionState.connected) {
        _handoff();
      } else if (s.state == ArxaConnectionState.notPaired && s.error != null) {
        // Pairing failed or was revoked — never spin forever; the failure
        // branch renders on the way out and the user lands back on the
        // scanner.
        _leave();
      }
    });
    if (state == ArxaConnectionState.connected) _handoff();
  }

  void _leave() {
    if (_handedOff) return;
    _handedOff = true;
    _router.back();
  }

  void _handoff() {
    if (_handedOff) return;
    _handedOff = true;
    // First pair: push permission before the session handoff.
    _router.replaceWith(PairingPushPermissionViewRoute());
  }

  /// Try Again — the ticket is single-use and consumed; a retry means a
  /// fresh scan.
  Future<void> refresh() async => _leave();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
