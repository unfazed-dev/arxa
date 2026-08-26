/// Test doubles for arxa_kit_notifications.
///
/// [FakeArxaKitNotificationsService] scripts permission outcomes and injects token
/// and foreground-message streams:
///
/// ```dart
/// final notifications = FakeArxaKitNotificationsService()
///   ..permissionResult = const ArxaKitNotificationPermissionResult(
///       ArxaKitNotificationAuthorization.authorized);
/// await notifications.requestPermission();
/// notifications.emitToken(ArxaKitPushToken(value: 't', issuedAt: DateTime.now()));
/// await notifications.showLocalNotification(
///     const ArxaKitLocalNotification(id: 1, title: 'Hi'));
/// expect(notifications.shown, hasLength(1));
/// ```
library;

import 'dart:async';

import 'src/arxa_kit_notifications_service.dart';
import 'src/arxa_kit_notifications_types.dart';
import 'src/arxa_kit_outbound_message_sink.dart';

export 'src/arxa_kit_notifications_service.dart';
export 'src/arxa_kit_notifications_types.dart';
export 'src/arxa_kit_outbound_message_sink.dart';

/// A scriptable in-memory [ArxaKitNotificationsService] for tests. Records shown
/// notifications and cancels, returns a scripted [permissionResult], and lets
/// the test drive the token and foreground-message streams by hand.
class FakeArxaKitNotificationsService implements ArxaKitNotificationsService {
  FakeArxaKitNotificationsService({
    this.permissionResult = const ArxaKitNotificationPermissionResult(
        ArxaKitNotificationAuthorization.authorized),
  });

  /// Returned by [requestPermission] and [permissionStatus]. Reassign to script
  /// a denial / provisional / not-determined outcome.
  ArxaKitNotificationPermissionResult permissionResult;

  final _tokenController = StreamController<ArxaKitPushToken>.broadcast();
  final _messageController = StreamController<ArxaKitRemoteMessage>.broadcast();

  ArxaKitPushToken? _currentToken;

  /// Notifications passed to [showLocalNotification], in call order.
  final List<ArxaKitLocalNotification> shown = [];

  /// Ids passed to [cancel], in call order.
  final List<int> cancelled = [];

  /// Permission requests received, in call order.
  final List<ArxaKitNotificationPermissionRequest> permissionRequests = [];

  /// Values passed to [setBadgeCount] (a [clearBadge] appends 0).
  final List<int> badgeCounts = [];

  int cancelAllCount = 0;
  int initializeCount = 0;
  bool disposed = false;

  // ---- scripting seams -----------------------------------------------------

  /// Push a token onto [tokenStream] and update [currentToken].
  void emitToken(ArxaKitPushToken token) {
    _currentToken = token;
    _tokenController.add(token);
  }

  /// Push a foreground message onto [foregroundMessages].
  void emitMessage(ArxaKitRemoteMessage message) => _messageController.add(message);

  // ---- ArxaKitNotificationsService --------------------------------------------

  @override
  Future<void> initialize() async => initializeCount++;

  @override
  Future<ArxaKitNotificationPermissionResult> requestPermission([
    ArxaKitNotificationPermissionRequest request =
        const ArxaKitNotificationPermissionRequest(),
  ]) async {
    permissionRequests.add(request);
    return permissionResult;
  }

  @override
  Future<ArxaKitNotificationPermissionResult> permissionStatus() async =>
      permissionResult;

  @override
  Stream<ArxaKitPushToken> get tokenStream => _tokenController.stream;

  @override
  Future<ArxaKitPushToken?> currentToken() async => _currentToken;

  @override
  Stream<ArxaKitRemoteMessage> get foregroundMessages => _messageController.stream;

  @override
  Future<void> showLocalNotification(ArxaKitLocalNotification notification) async =>
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

/// A scriptable [ArxaKitOutboundMessageSink] that records sent messages and can be
/// told to fail.
class FakeArxaKitOutboundMessageSink implements ArxaKitOutboundMessageSink {
  FakeArxaKitOutboundMessageSink({this.channel = 'fake', this.failWith});

  @override
  final String channel;

  /// When non-null, [send] throws this instead of recording.
  Object? failWith;

  /// Messages passed to [send], in call order.
  final List<ArxaKitOutboundMessage> sent = [];

  @override
  Future<void> send(ArxaKitOutboundMessage message) async {
    final failure = failWith;
    if (failure != null) throw failure;
    sent.add(message);
  }
}
