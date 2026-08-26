import 'package:flutter/foundation.dart' show immutable;

/// OS-level authorization state for device notifications. Union of the iOS
/// `UNAuthorizationStatus` and Android's runtime-permission model.
enum ArxaKitNotificationAuthorization {
  /// Never asked (iOS `notDetermined`; Android before the first request).
  notDetermined,

  /// The user declined.
  denied,

  /// Full authorization to alert/badge/sound.
  authorized,

  /// iOS provisional (quiet) authorization — delivered silently to the
  /// notification center without an explicit prompt.
  provisional,
}

/// Result of a permission query/request. [isGranted] treats provisional as
/// granted since messages still deliver.
@immutable
class ArxaKitNotificationPermissionResult {
  const ArxaKitNotificationPermissionResult(this.status);

  final ArxaKitNotificationAuthorization status;

  bool get isGranted =>
      status == ArxaKitNotificationAuthorization.authorized ||
      status == ArxaKitNotificationAuthorization.provisional;

  @override
  String toString() => 'ArxaKitNotificationPermissionResult($status)';
}

/// Which capabilities to request when prompting. Honored on iOS/macOS (Darwin);
/// Android's single runtime permission ignores the individual flags.
@immutable
class ArxaKitNotificationPermissionRequest {
  const ArxaKitNotificationPermissionRequest({
    this.alert = true,
    this.badge = true,
    this.sound = true,
  });

  final bool alert;
  final bool badge;
  final bool sound;
}

/// The push provider that issued a [ArxaKitPushToken].
enum ArxaKitPushProvider { apns, fcm, unknown }

/// A push registration token (APNs device token or FCM token).
@immutable
class ArxaKitPushToken {
  const ArxaKitPushToken({
    required this.value,
    required this.issuedAt,
    this.provider = ArxaKitPushProvider.unknown,
  });

  final String value;
  final ArxaKitPushProvider provider;
  final DateTime issuedAt;

  @override
  String toString() => 'ArxaKitPushToken(${provider.name}, '
      '${value.length > 12 ? '${value.substring(0, 12)}…' : value})';
}

/// A remote message delivered while the app is in the foreground.
@immutable
class ArxaKitRemoteMessage {
  const ArxaKitRemoteMessage({
    required this.receivedAt,
    this.messageId,
    this.title,
    this.body,
    this.data = const <String, dynamic>{},
  });

  final String? messageId;
  final String? title;
  final String? body;

  /// Provider-specific data payload (FCM `data` map / APNs custom keys).
  final Map<String, dynamic> data;
  final DateTime receivedAt;

  @override
  String toString() => 'ArxaKitRemoteMessage($messageId, $title)';
}

/// A local notification to display now.
@immutable
class ArxaKitLocalNotification {
  const ArxaKitLocalNotification({
    required this.id,
    this.title,
    this.body,
    this.payload,
    this.badgeCount,
    this.androidChannelId,
    this.androidChannelName,
  });

  /// Stable id; reusing an id replaces the earlier notification.
  final int id;
  final String? title;
  final String? body;

  /// Opaque string delivered back to the tap handler.
  final String? payload;

  /// iOS/macOS app-icon badge set as a side effect of delivery. Null leaves the
  /// badge unchanged.
  final int? badgeCount;

  /// Android channel; null falls back to the service's default channel.
  final String? androidChannelId;
  final String? androidChannelName;
}

/// An outbound one-to-one message (SMS, email) the app sends — distinct from
/// inbound device push. Consumed by [ArxaKitOutboundMessageSink] implementations.
@immutable
class ArxaKitOutboundMessage {
  const ArxaKitOutboundMessage({
    required this.to,
    required this.body,
    this.subject,
    this.metadata = const <String, String>{},
  });

  /// Recipient — phone number (SMS) or email address (email).
  final String to;

  /// Optional subject line (email; ignored by SMS).
  final String? subject;
  final String body;

  /// Provider-specific extras (template id, from-address, tags, …).
  final Map<String, String> metadata;

  @override
  String toString() => 'ArxaKitOutboundMessage(to: $to)';
}
