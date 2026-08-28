// arxa-builder: OS permission + set_push_token equivalent -> transport PUSH
// frame + cairn registerPushToken, via PushTokenService (ArxaKitCairnPushBridge).
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show BaseViewModel, RouterService;

import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app.router.dart';
import 'package:arxa_studio_mobile/services/push_token_service.dart';

class PairingPushPermissionViewModel extends BaseViewModel {
  final _push = locator<PushTokenService>();
  final _router = locator<RouterService>();

  Future<void> allow() async {
    // Denial is not an error surface — the session works without push;
    // approvals just stay in-app only.
    await runBusyFuture(_push.requestPermission());
    await _router.replaceWith(StudioSessionViewRoute());
  }

  Future<void> skip() => _router.replaceWith(StudioSessionViewRoute());

  Future<void> refresh() async {}
}
