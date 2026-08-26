/// arxa_kit_notifications — the device-notifications port for arxa_kit
/// apps: permission, push token / foreground-message seams, local
/// notifications, and badge.
///
/// [ArxaKitNotificationsService] is the port; [LocalArxaKitNotificationsService] is the
/// native-first working default (flutter_local_notifications). Push (FCM/APNs)
/// and outbound (SMS/email) backends are file stubs.
///
/// NAMING: this is *ArxaKitNotificationsService* (plural — device notifications /
/// push). It is a different concern from the kit core's *ArxaKitNotificationService*
/// (singular — in-app transient toast/snackbar), which stays in `arxa_kit`.
///
/// Test doubles live in `arxa_kit_notifications/arxa_kit_testing.dart`.
library;

export 'src/arxa_kit_notifications_types.dart';
export 'src/arxa_kit_notifications_service.dart';
export 'src/arxa_kit_outbound_message_sink.dart';

// Working default
export 'src/local/arxa_kit_local_notifications_service.dart';

// Backends (stubs)
export 'src/backends/arxa_kit_fcm_push_backend.dart';
export 'src/backends/arxa_kit_sms_backend.dart';
export 'src/backends/arxa_kit_email_backend.dart';
