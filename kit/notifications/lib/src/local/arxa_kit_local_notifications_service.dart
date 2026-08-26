import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../arxa_kit_notifications_service.dart';
import '../arxa_kit_notifications_types.dart';

/// The working default [ArxaKitNotificationsService]: local notifications,
/// permission prompting, and per-notification badge via
/// flutter_local_notifications (native-first — UNUserNotificationCenter on
/// iOS/macOS, NotificationManager on Android).
///
/// This is NOT a push provider. [tokenStream] and [foregroundMessages] emit
/// nothing; attach the FCM/APNs push backend for those seams. [setBadgeCount]
/// is likewise unsupported standalone (see the method doc).
class LocalArxaKitNotificationsService implements ArxaKitNotificationsService {
  LocalArxaKitNotificationsService({
    FlutterLocalNotificationsPlugin? plugin,
    this.androidDefaultIcon = '@mipmap/ic_launcher',
    this.defaultChannelId = 'default',
    this.defaultChannelName = 'Default',
    this.onDidReceiveResponse,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Android small-icon resource used at initialize time.
  final String androidDefaultIcon;

  /// Android channel applied when a [ArxaKitLocalNotification] omits its own.
  final String defaultChannelId;
  final String defaultChannelName;

  /// Invoked when the user taps a notification (foreground/background tap).
  final DidReceiveNotificationResponseCallback? onDidReceiveResponse;

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      _initialized = true;
      return;
    }
    // Defer the OS prompt to requestPermission() so the app controls timing.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    final settings = InitializationSettings(
      android: AndroidInitializationSettings(androidDefaultIcon),
      iOS: darwin,
      macOS: darwin,
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onDidReceiveResponse,
    );
    _initialized = true;
  }

  @override
  Future<ArxaKitNotificationPermissionResult> requestPermission([
    ArxaKitNotificationPermissionRequest request =
        const ArxaKitNotificationPermissionRequest(),
  ]) async {
    if (kIsWeb) {
      return const ArxaKitNotificationPermissionResult(
          ArxaKitNotificationAuthorization.notDetermined);
    }
    bool? granted;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        granted = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      case TargetPlatform.iOS:
        granted = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: request.alert,
              badge: request.badge,
              sound: request.sound,
            );
      case TargetPlatform.macOS:
        granted = await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: request.alert,
              badge: request.badge,
              sound: request.sound,
            );
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        granted = null;
    }
    return ArxaKitNotificationPermissionResult(switch (granted) {
      true => ArxaKitNotificationAuthorization.authorized,
      false => ArxaKitNotificationAuthorization.denied,
      null => ArxaKitNotificationAuthorization.notDetermined,
    });
  }

  @override
  Future<ArxaKitNotificationPermissionResult> permissionStatus() async {
    // flutter_local_notifications 21 has no cross-platform status query that
    // avoids prompting; report notDetermined. A push backend (FCM) or a
    // permission_handler-backed service can override with a real status.
    return const ArxaKitNotificationPermissionResult(
        ArxaKitNotificationAuthorization.notDetermined);
  }

  // Local notifications are not a push provider — no tokens, no remote messages.
  @override
  Stream<ArxaKitPushToken> get tokenStream => const Stream.empty();

  @override
  Future<ArxaKitPushToken?> currentToken() async => null;

  @override
  Stream<ArxaKitRemoteMessage> get foregroundMessages => const Stream.empty();

  @override
  Future<void> showLocalNotification(ArxaKitLocalNotification notification) async {
    await initialize();
    final darwin = DarwinNotificationDetails(badgeNumber: notification.badgeCount);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        notification.androidChannelId ?? defaultChannelId,
        notification.androidChannelName ?? defaultChannelName,
      ),
      iOS: darwin,
      macOS: darwin,
    );
    await _plugin.show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
      payload: notification.payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> setBadgeCount(int count) async {
    // flutter_local_notifications sets the iOS badge only as a side effect of a
    // delivered notification (DarwinNotificationDetails.badgeNumber); there is
    // no standalone app-icon badge setter in v21, and Android badges are
    // launcher-specific. A standalone count is a push-payload / dedicated-badge-
    // plugin concern owned by the FCM/APNs backend. Set
    // ArxaKitLocalNotification.badgeCount on a shown notification instead.
    throw UnsupportedError(
      'LocalArxaKitNotificationsService: standalone setBadgeCount is not supported '
      'by flutter_local_notifications. Set ArxaKitLocalNotification.badgeCount on a '
      'shown notification, or attach the FCM/APNs push backend.',
    );
  }

  @override
  Future<void> clearBadge() => setBadgeCount(0);

  @override
  Future<void> dispose() async {}
}
