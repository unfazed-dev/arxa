import '../appbox_kit_notifications_service.dart';
import '../appbox_kit_notifications_types.dart';

/// STUB — Firebase Cloud Messaging (FCM/APNs) push backend.
///
/// TODO(appbox_kit_notifications): implement against
/// `firebase_messaging: ^16.1.0` (verified latest on pub.dev, 2026). Mapping:
///   - requestPermission  -> FirebaseMessaging.instance.requestPermission(...)
///                           -> NotificationSettings.authorizationStatus
///   - tokenStream        -> onTokenRefresh (seed with getToken())
///   - currentToken       -> getToken()  (APNs: getAPNSToken() first on iOS)
///   - foregroundMessages -> FirebaseMessaging.onMessage
///   - showLocalNotification -> delegate to LocalAppBoxKitNotificationsService (FCM
///                              does not render foreground alerts itself)
///   - setBadgeCount      -> deliver via the APNs `badge` field server-side
///
/// This stub intentionally does NOT import `firebase_messaging`, so the package
/// pulls no Firebase dependency until a host opts in and wires this backend.
class AppBoxKitFcmPushBackend implements AppBoxKitNotificationsService {
  AppBoxKitFcmPushBackend();

  Never _stub(String member) =>
      throw UnimplementedError('AppBoxKitFcmPushBackend.$member is a stub');

  @override
  Future<void> initialize() async => _stub('initialize');

  @override
  Future<AppBoxKitNotificationPermissionResult> requestPermission([
    AppBoxKitNotificationPermissionRequest request =
        const AppBoxKitNotificationPermissionRequest(),
  ]) async =>
      _stub('requestPermission');

  @override
  Future<AppBoxKitNotificationPermissionResult> permissionStatus() async =>
      _stub('permissionStatus');

  @override
  Stream<AppBoxKitPushToken> get tokenStream => _stub('tokenStream');

  @override
  Future<AppBoxKitPushToken?> currentToken() async => _stub('currentToken');

  @override
  Stream<AppBoxKitRemoteMessage> get foregroundMessages => _stub('foregroundMessages');

  @override
  Future<void> showLocalNotification(AppBoxKitLocalNotification notification) async =>
      _stub('showLocalNotification');

  @override
  Future<void> cancel(int id) async => _stub('cancel');

  @override
  Future<void> cancelAll() async => _stub('cancelAll');

  @override
  Future<void> setBadgeCount(int count) async => _stub('setBadgeCount');

  @override
  Future<void> clearBadge() async => _stub('clearBadge');

  @override
  Future<void> dispose() async => _stub('dispose');
}
