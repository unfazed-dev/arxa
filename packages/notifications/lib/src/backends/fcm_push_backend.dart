import '../kit_notifications_service.dart';
import '../kit_notifications_types.dart';

/// STUB — Firebase Cloud Messaging (FCM/APNs) push backend.
///
/// TODO(appbox_kit_notifications): implement against
/// `firebase_messaging: ^16.1.0` (verified latest on pub.dev, 2026). Mapping:
///   - requestPermission  -> FirebaseMessaging.instance.requestPermission(...)
///                           -> NotificationSettings.authorizationStatus
///   - tokenStream        -> onTokenRefresh (seed with getToken())
///   - currentToken       -> getToken()  (APNs: getAPNSToken() first on iOS)
///   - foregroundMessages -> FirebaseMessaging.onMessage
///   - showLocalNotification -> delegate to LocalKitNotificationsService (FCM
///                              does not render foreground alerts itself)
///   - setBadgeCount      -> deliver via the APNs `badge` field server-side
///
/// This stub intentionally does NOT import `firebase_messaging`, so the package
/// pulls no Firebase dependency until a host opts in and wires this backend.
class FcmPushBackend implements KitNotificationsService {
  FcmPushBackend();

  Never _stub(String member) =>
      throw UnimplementedError('FcmPushBackend.$member is a stub');

  @override
  Future<void> initialize() async => _stub('initialize');

  @override
  Future<KitNotificationPermissionResult> requestPermission([
    KitNotificationPermissionRequest request =
        const KitNotificationPermissionRequest(),
  ]) async =>
      _stub('requestPermission');

  @override
  Future<KitNotificationPermissionResult> permissionStatus() async =>
      _stub('permissionStatus');

  @override
  Stream<KitPushToken> get tokenStream => _stub('tokenStream');

  @override
  Future<KitPushToken?> currentToken() async => _stub('currentToken');

  @override
  Stream<KitRemoteMessage> get foregroundMessages => _stub('foregroundMessages');

  @override
  Future<void> showLocalNotification(KitLocalNotification notification) async =>
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
