// arxa-builder: deps wire (pairing facade -> TransportService seam).
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show BaseViewModel, RouterService;

import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app.router.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

class PairingScanViewModel extends BaseViewModel {
  final _transport = locator<TransportService>();
  final _router = locator<RouterService>();

  bool _submitted = false;

  /// One ticket per scan session — mobile_scanner fires repeatedly on the
  /// same code; first hit wins. Also the manual-entry submit path.
  Future<void> submitTicket(String ticket) async {
    if (_submitted) return;
    final t = ticket.trim();
    if (t.isEmpty) return;
    _submitted = true;
    await runBusyFuture(_transport.beginPairing(t));
    await _router.navigateTo(PairingConnectingViewRoute());
    _submitted = false;
  }

  Future<void> refresh() async {}
}
