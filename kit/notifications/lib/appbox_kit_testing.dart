/// Test doubles for appbox_kit_notifications.
///
/// [FakeAppBoxKitNotificationsService] scripts permission outcomes and injects token
/// and foreground-message streams:
///
/// ```dart
/// final notifications = FakeAppBoxKitNotificationsService()
///   ..permissionResult = const AppBoxKitNotificationPermissionResult(
///       AppBoxKitNotificationAuthorization.authorized);
/// await notifications.requestPermission();
/// notifications.emitToken(AppBoxKitPushToken(value: 't', issuedAt: DateTime.now()));
/// await notifications.showLocalNotification(
///     const AppBoxKitLocalNotification(id: 1, title: 'Hi'));
/// expect(notifications.shown, hasLength(1));
/// ```
library;

import 'dart:async';

import 'src/appbox_kit_notifications_service.dart';
import 'src/appbox_kit_notifications_types.dart';
import 'src/appbox_kit_outbound_message_sink.dart';

export 'src/appbox_kit_notifications_service.dart';
export 'src/appbox_kit_notifications_types.dart';
export 'src/appbox_kit_outbound_message_sink.dart';

/// A scriptable in-memory [AppBoxKitNotificationsService] for tests. Records shown
/// notifications and cancels, returns a scripted [permissionResult], and lets
/// the test drive the token and foreground-message streams by hand.
class FakeAppBoxKitNotificationsService implements AppBoxKitNotificationsService {
  FakeAppBoxKitNotificationsService({
    this.permissionResult = const AppBoxKitNotificationPermissionResult(
        AppBoxKitNotificationAuthorization.authorized),
  });

  /// Returned by [requestPermission] and [permissionStatus]. Reassign to script
  /// a denial / provisional / not-determined outcome.
  AppBoxKitNotificationPermissionResult permissionResult;

  final _tokenController = StreamController<AppBoxKitPushToken>.broadcast();
  final _messageController = StreamController<AppBoxKitRemoteMessage>.broadcast();

  AppBoxKitPushToken? _currentToken;

  /// Notifications passed to [showLocalNotification], in call order.
  final List<AppBoxKitLocalNotification> shown = [];

  /// Ids passed to [cancel], in call order.
  final List<int> cancelled = [];

  /// Permission requests received, in call order.
  final List<AppBoxKitNotificationPermissionRequest> permissionRequests = [];

  /// Values passed to [setBadgeCount] (a [clearBadge] appends 0).
  final List<int> badgeCounts = [];

  int cancelAllCount = 0;
  int initializeCount = 0;
  bool disposed = false;

  // ---- scripting seams -----------------------------------------------------

  /// Push a token onto [tokenStream] and update [currentToken].
  void emitToken(AppBoxKitPushToken token) {
    _currentToken = token;
    _tokenController.add(token);
  }

  /// Push a foreground message onto [foregroundMessages].
  void emitMessage(AppBoxKitRemoteMessage message) => _messageController.add(message);

  // ---- AppBoxKitNotificationsService --------------------------------------------

  @override
  Future<void> initialize() async => initializeCount++;

  @override
  Future<AppBoxKitNotificationPermissionResult> requestPermission([
    AppBoxKitNotificationPermissionRequest request =
        const AppBoxKitNotificationPermissionRequest(),
  ]) async {
    permissionRequests.add(request);
    return permissionResult;
  }

  @override
  Future<AppBoxKitNotificationPermissionResult> permissionStatus() async =>
      permissionResult;

  @override
  Stream<AppBoxKitPushToken> get tokenStream => _tokenController.stream;

  @override
  Future<AppBoxKitPushToken?> currentToken() async => _currentToken;

  @override
  Stream<AppBoxKitRemoteMessage> get foregroundMessages => _messageController.stream;

  @override
  Future<void> showLocalNotification(AppBoxKitLocalNotification notification) async =>
      shown.add(notification);

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelAllCount++;

  @override
  Future<void> setBadgeCount(int count) async => badgeCounts.add(count);

  @override
  Future<void> clearBadge() async => badgeCounts.add(0);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _tokenController.close();
    await _messageController.close();
  }
}

/// A scriptable [AppBoxKitOutboundMessageSink] that records sent messages and can be
/// told to fail.
class FakeAppBoxKitOutboundMessageSink implements AppBoxKitOutboundMessageSink {
  FakeAppBoxKitOutboundMessageSink({this.channel = 'fake', this.failWith});

  @override
  final String channel;

  /// When non-null, [send] throws this instead of recording.
  Object? failWith;

  /// Messages passed to [send], in call order.
  final List<AppBoxKitOutboundMessage> sent = [];

  @override
  Future<void> send(AppBoxKitOutboundMessage message) async {
    final failure = failWith;
    if (failure != null) throw failure;
    sent.add(message);
  }
}
