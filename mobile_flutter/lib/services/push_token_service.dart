import 'dart:io' show Platform;

import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';

import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'transport_service.dart';

/// Push-token seam: owns an [ArxaKitNotificationsService] backend and an
/// [ArxaKitCairnPushBridge] that forwards token (re)issues BOTH to cairn's
/// registerPushToken rail and to the transport's `set_push_token` port.
/// Fake-capable: pass any notifications impl (e.g.
/// FakeArxaKitNotificationsService from arxa_kit_testing) in tests; the
/// default is the FCM backend — a config-less build (no google-services.json)
/// stays green because nothing calls Firebase until permission is requested.
class PushTokenService {
  /// Locator-constructed (registered as a LazySingleton); [notifications]
  /// and [transport] resolve from the locator so tests can swap fakes by
  /// re-registering those seams before first use.
  PushTokenService({
    ArxaKitNotificationsService? notifications,
    TransportService? transport,
  }) : _notifications = notifications ?? locator<ArxaKitNotificationsService>(),
       _bridge = ArxaKitCairnPushBridge(
         notifications: notifications ?? locator<ArxaKitNotificationsService>(),
         register: (platform, token) =>
             (transport ?? locator<TransportService>()).setPushToken(
               platform,
               token,
             ),
       );

  final ArxaKitNotificationsService _notifications;
  final ArxaKitCairnPushBridge _bridge;

  static String get platformName => Platform.isIOS ? 'ios' : 'android';

  Future<ArxaKitNotificationPermissionResult> requestPermission() async {
    final result = await _notifications.requestPermission();
    await _bridge.attach();
    return result;
  }

  Future<void> detach() => _bridge.detach();
}
