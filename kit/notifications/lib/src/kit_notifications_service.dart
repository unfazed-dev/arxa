import 'kit_notifications_types.dart';

/// The device-notifications port for appbox_kit apps: permission, push token
/// and foreground-message seams, local notifications, and badge management.
///
/// DISTINCT FROM the kit core's `KitNotificationService` (singular), which is
/// the in-app transient-feedback surface (toast / snackbar). This service
/// (plural — *Notifications*) is about OS-level device notifications and push.
///
/// The working default is [LocalKitNotificationsService] (backed by
/// flutter_local_notifications), which implements the local + permission + badge
/// surface. The push seams ([tokenStream], [foregroundMessages]) are owned by a
/// push backend (FCM/APNs) — the local default emits nothing on them.
abstract class KitNotificationsService {
  /// Initialize the underlying plugin(s). Idempotent; call once at boot.
  Future<void> initialize();

  /// Prompt the OS for notification permission. Returns the resulting status
  /// rather than throwing when the user declines.
  Future<KitNotificationPermissionResult> requestPermission([
    KitNotificationPermissionRequest request,
  ]);

  /// Current permission status without prompting.
  Future<KitNotificationPermissionResult> permissionStatus();

  /// Push registration tokens (APNs/FCM): emits on first registration and on
  /// every refresh. Local-only implementations emit nothing.
  Stream<KitPushToken> get tokenStream;

  /// The most recent push token, or null if not registered / local-only.
  Future<KitPushToken?> currentToken();

  /// Remote messages delivered while the app is foregrounded. Local-only
  /// implementations emit nothing.
  Stream<KitRemoteMessage> get foregroundMessages;

  /// Show a local notification now.
  Future<void> showLocalNotification(KitLocalNotification notification);

  /// Cancel a shown/scheduled notification by id.
  Future<void> cancel(int id);

  /// Cancel every notification from this app.
  Future<void> cancelAll();

  /// Set the app-icon badge to [count]. NOTE: a *standalone* badge is a push-
  /// payload concern — the local default throws [UnsupportedError] here; set
  /// [KitLocalNotification.badgeCount] on a shown notification instead.
  Future<void> setBadgeCount(int count);

  /// Clear the app-icon badge (see [setBadgeCount] caveats).
  Future<void> clearBadge();

  /// Release streams / resources.
  Future<void> dispose();
}
