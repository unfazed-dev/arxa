import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_studio_mobile/services/iroh_transport_service.dart';
import 'package:arxa_studio_mobile/services/push_token_service.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/approvals_shell/approvals_list/approvals_list_view.dart';
import 'package:arxa_studio_mobile/ui/views/pairing_shell/pairing_connecting/pairing_connecting_view.dart';
import 'package:arxa_studio_mobile/ui/views/pairing_shell/pairing_scan/pairing_scan_view.dart';
import 'package:arxa_studio_mobile/ui/views/pairing_shell/pairing_push_permission/pairing_push_permission_view.dart';
import 'package:arxa_studio_mobile/ui/views/settings_shell/settings_home/settings_home_view.dart';
import 'package:arxa_studio_mobile/ui/views/studio_shell/studio_session/studio_session_view.dart';

/// Routes mirror design/structure.json (frozen). Pairing scan is initial;
/// studio session is the webview handoff; approvals is notification-driven.
@StackedApp(
  routes: [
    AdaptiveRoute(page: PairingScanView, initial: true),
    AdaptiveRoute(page: PairingConnectingView),
    AdaptiveRoute(page: PairingPushPermissionView),
    AdaptiveRoute(page: StudioSessionView),
    AdaptiveRoute(page: ApprovalsListView),
    AdaptiveRoute(page: SettingsHomeView),
  ],
  dependencies: [
    LazySingleton(classType: RouterService),
    // Real iroh-backed transport (arxa_kit_studio_transport) behind the same
    // interface; tests re-register FakeTransportService or inject
    // MockStudioTransport.connect via the StudioConnect seam.
    LazySingleton(classType: IrohTransportService, asType: TransportService),
    // Push seam: FCM backend by default; tests swap in
    // FakeArxaKitNotificationsService from arxa_kit_notifications/testing.
    LazySingleton(
        classType: ArxaKitFcmPushBackend,
        asType: ArxaKitNotificationsService),
    LazySingleton(classType: PushTokenService),
  ],
)
class App {}
