import 'arxa_kit_notifications_types.dart';

/// The device-notifications port for arxa_kit apps: permission, push token
/// and foreground-message seams, local notifications, and badge management.
///
/// DISTINCT FROM the kit core's `ArxaKitNotificationService` (singular), which is
/// the in-app transient-feedback surface (toast / snackbar). This service
/// (plural — *Notifications*) is about OS-level device notifications and push.
///
/// The working default is [LocalArxaKitNotificationsService] (backed by
/// flutter_local_notifications), which implements the local + permission + badge
/// surface. The push seams ([tokenStream], [foregroundMessages]) are owned by a
/// push backend (FCM/APNs) — the local default emits nothing on them.
abstract class ArxaKitNotificationsService {
  /// Initialize the underlying plugin(s). Idempotent; call once at boot.
  Future<void> initialize();

  /// Prompt the OS for notification permission. Returns the resulting status
  /// rather than throwing when the user declines.
  Future<ArxaKitNotificationPermissionResult> requestPermission([
    ArxaKitNotificationPermissionRequest request,
  ]);

  /// Current permission status without prompting.
  Future<ArxaKitNotificationPermissionResult> permissionStatus();

  /// Push registration tokens (APNs/FCM): emits on first registration and on
  /// every refresh. Local-only implementations emit nothing.
  Stream<ArxaKitPushToken> get tokenStream;

  /// The most recent push token, or null if not registered / local-only.
  Future<ArxaKitPushToken?> currentToken();

  /// Remote messages delivered while the app is foregrounded. Local-only
  /// implementations emit nothing.
  Stream<ArxaKitRemoteMessage> get foregroundMessages;

  /// Show a local notification now.
  Future<void> showLocalNotification(ArxaKitLocalNotification notification);

  /// Cancel a shown/scheduled notification by id.
  Future<void> cancel(int id);

  /// Cancel every notification from this app.
  Future<void> cancelAll();

  /// Set the app-icon badge to [count]. NOTE: a *standalone* badge is a push-
  /// payload concern — the local default throws [UnsupportedError] here; set
  /// [ArxaKitLocalNotification.badgeCount] on a shown notification instead.
  Future<void> setBadgeCount(int count);

  /// Clear the app-icon badge (see [setBadgeCount] caveats).
  Future<void> clearBadge();

  /// Release streams / resources.
  Future<void> dispose();
}
