// The platform-aware notifications backend selector (D68 phone leg).
// Registered ONCE as the app's ArxaKitNotificationsService — a plain
// concrete class, so stacked_generator's annotation stays untouched and
// regeneration cannot revert the switch. iOS gets the raw-APNs backend
// (Runner-side ApnsBridge); every other platform keeps the FCM backend
// (a deliberate stub until the FCM rail's Firebase project exists).
// Tests keep swapping the whole registration for fakes, as before.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';

import 'apns_notifications_backend.dart';

class AppNotificationsBackend implements ArxaKitNotificationsService {
  AppNotificationsBackend()
    : _inner = Platform.isIOS
          ? ApnsNotificationsBackend()
          : ArxaKitFcmPushBackend();

  final ArxaKitNotificationsService _inner;

  /// The iOS APNs backend when present — the phone leg subscribes its tap
  /// stream to route buzzes into the approvals shell.
  ApnsNotificationsBackend? get apns =>
      _inner is ApnsNotificationsBackend ? _inner : null;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<ArxaKitNotificationPermissionResult> requestPermission([
    ArxaKitNotificationPermissionRequest request =
        const ArxaKitNotificationPermissionRequest(),
  ]) => _inner.requestPermission(request);

  @override
  Future<ArxaKitNotificationPermissionResult> permissionStatus() =>
      _inner.permissionStatus();

  @override
  Stream<ArxaKitPushToken> get tokenStream => _inner.tokenStream;

  @override
  Future<ArxaKitPushToken?> currentToken() => _inner.currentToken();

  @override
  Stream<ArxaKitRemoteMessage> get foregroundMessages =>
      _inner.foregroundMessages;

  @override
  Future<void> showLocalNotification(ArxaKitLocalNotification notification) =>
      _inner.showLocalNotification(notification);

  @override
  Future<void> cancel(int id) => _inner.cancel(id);

  @override
  Future<void> cancelAll() => _inner.cancelAll();

  @override
  Future<void> setBadgeCount(int count) => _inner.setBadgeCount(count);

  @override
  Future<void> clearBadge() => _inner.clearBadge();

  @override
  Future<void> dispose() => _inner.dispose();
}
