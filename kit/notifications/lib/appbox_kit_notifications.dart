/// appbox_kit_notifications — the device-notifications port for appbox_kit
/// apps: permission, push token / foreground-message seams, local
/// notifications, and badge.
///
/// [AppBoxKitNotificationsService] is the port; [LocalAppBoxKitNotificationsService] is the
/// native-first working default (flutter_local_notifications). Push (FCM/APNs)
/// and outbound (SMS/email) backends are file stubs.
///
/// NAMING: this is *AppBoxKitNotificationsService* (plural — device notifications /
/// push). It is a different concern from the kit core's *AppBoxKitNotificationService*
/// (singular — in-app transient toast/snackbar), which stays in `appbox_kit`.
///
/// Test doubles live in `appbox_kit_notifications/appbox_kit_testing.dart`.
library;

export 'src/appbox_kit_notifications_types.dart';
export 'src/appbox_kit_notifications_service.dart';
export 'src/appbox_kit_outbound_message_sink.dart';

// Working default
export 'src/local/appbox_kit_local_notifications_service.dart';

// Backends (stubs)
export 'src/backends/appbox_kit_fcm_push_backend.dart';
export 'src/backends/appbox_kit_sms_backend.dart';
export 'src/backends/appbox_kit_email_backend.dart';
