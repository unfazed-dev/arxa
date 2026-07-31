/// appbox_kit_notifications — the device-notifications port for stacked_kit
/// apps: permission, push token / foreground-message seams, local
/// notifications, and badge.
///
/// [KitNotificationsService] is the port; [LocalKitNotificationsService] is the
/// native-first working default (flutter_local_notifications). Push (FCM/APNs)
/// and outbound (SMS/email) backends are file stubs.
///
/// NAMING: this is *KitNotificationsService* (plural — device notifications /
/// push). It is a different concern from the kit core's *KitNotificationService*
/// (singular — in-app transient toast/snackbar), which stays in `stacked_kit`.
///
/// Test doubles live in `appbox_kit_notifications/testing.dart`.
library;

export 'src/kit_notifications_types.dart';
export 'src/kit_notifications_service.dart';
export 'src/kit_outbound_message_sink.dart';

// Working default
export 'src/local/local_notifications_service.dart';

// Backends (stubs)
export 'src/backends/fcm_push_backend.dart';
export 'src/backends/sms_backend.dart';
export 'src/backends/email_backend.dart';
