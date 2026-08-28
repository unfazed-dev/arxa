// arxa-builder: unpair = drop stored NodeId + session token (transport) +
// push-bridge detach (sign-out hook auto-deregisters the push token).
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show BaseViewModel, RouterService;

import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app.router.dart';
import 'package:arxa_studio_mobile/services/push_token_service.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

class SettingsHomeViewModel extends BaseViewModel {
  final _transport = locator<TransportService>();
  final _push = locator<PushTokenService>();
  final _router = locator<RouterService>();

  Future<void> unpair() async {
    await runBusyFuture(
      Future.wait([_push.detach(), _transport.unpair()]),
    );
    await _router.clearStackAndShow(PairingScanViewRoute());
  }

  Future<void> refresh() async {}
}
