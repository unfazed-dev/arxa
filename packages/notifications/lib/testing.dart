/// Test doubles for appbox_kit_notifications.
///
/// [FakeKitNotificationsService] scripts permission outcomes and injects token
/// and foreground-message streams:
///
/// ```dart
/// final notifications = FakeKitNotificationsService()
///   ..permissionResult = const KitNotificationPermissionResult(
///       KitNotificationAuthorization.authorized);
/// await notifications.requestPermission();
/// notifications.emitToken(KitPushToken(value: 't', issuedAt: DateTime.now()));
/// await notifications.showLocalNotification(
///     const KitLocalNotification(id: 1, title: 'Hi'));
/// expect(notifications.shown, hasLength(1));
/// ```
library;

import 'dart:async';

import 'src/kit_notifications_service.dart';
import 'src/kit_notifications_types.dart';
import 'src/kit_outbound_message_sink.dart';

export 'src/kit_notifications_service.dart';
export 'src/kit_notifications_types.dart';
export 'src/kit_outbound_message_sink.dart';

/// A scriptable in-memory [KitNotificationsService] for tests. Records shown
/// notifications and cancels, returns a scripted [permissionResult], and lets
/// the test drive the token and foreground-message streams by hand.
class FakeKitNotificationsService implements KitNotificationsService {
  FakeKitNotificationsService({
    this.permissionResult = const KitNotificationPermissionResult(
        KitNotificationAuthorization.authorized),
  });

  /// Returned by [requestPermission] and [permissionStatus]. Reassign to script
  /// a denial / provisional / not-determined outcome.
  KitNotificationPermissionResult permissionResult;

  final _tokenController = StreamController<KitPushToken>.broadcast();
  final _messageController = StreamController<KitRemoteMessage>.broadcast();

  KitPushToken? _currentToken;

  /// Notifications passed to [showLocalNotification], in call order.
  final List<KitLocalNotification> shown = [];

  /// Ids passed to [cancel], in call order.
  final List<int> cancelled = [];

  /// Permission requests received, in call order.
  final List<KitNotificationPermissionRequest> permissionRequests = [];

  /// Values passed to [setBadgeCount] (a [clearBadge] appends 0).
  final List<int> badgeCounts = [];

  int cancelAllCount = 0;
  int initializeCount = 0;
  bool disposed = false;

  // ---- scripting seams -----------------------------------------------------

  /// Push a token onto [tokenStream] and update [currentToken].
  void emitToken(KitPushToken token) {
    _currentToken = token;
    _tokenController.add(token);
  }

  /// Push a foreground message onto [foregroundMessages].
  void emitMessage(KitRemoteMessage message) => _messageController.add(message);

  // ---- KitNotificationsService --------------------------------------------

  @override
  Future<void> initialize() async => initializeCount++;

  @override
  Future<KitNotificationPermissionResult> requestPermission([
    KitNotificationPermissionRequest request =
        const KitNotificationPermissionRequest(),
  ]) async {
    permissionRequests.add(request);
    return permissionResult;
  }

  @override
  Future<KitNotificationPermissionResult> permissionStatus() async =>
      permissionResult;

  @override
  Stream<KitPushToken> get tokenStream => _tokenController.stream;

  @override
  Future<KitPushToken?> currentToken() async => _currentToken;

  @override
  Stream<KitRemoteMessage> get foregroundMessages => _messageController.stream;

  @override
  Future<void> showLocalNotification(KitLocalNotification notification) async =>
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

/// A scriptable [KitOutboundMessageSink] that records sent messages and can be
/// told to fail.
class FakeOutboundMessageSink implements KitOutboundMessageSink {
  FakeOutboundMessageSink({this.channel = 'fake', this.failWith});

  @override
  final String channel;

  /// When non-null, [send] throws this instead of recording.
  Object? failWith;

  /// Messages passed to [send], in call order.
  final List<KitOutboundMessage> sent = [];

  @override
  Future<void> send(KitOutboundMessage message) async {
    final failure = failWith;
    if (failure != null) throw failure;
    sent.add(message);
  }
}
