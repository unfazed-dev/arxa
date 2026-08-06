import 'appbox_kit_notifications_types.dart';

/// Port for outbound one-to-one messaging (SMS, email) the app triggers —
/// distinct from inbound device push. It lives in this package because
/// "notifications" spans both directions; the concrete sinks are stubs today.
///
/// Implementations are typically provider-backed (Twilio, SendGrid) over HTTPS
/// or native compose/send seams — see [AppBoxKitSmsBackend] and [AppBoxKitEmailBackend].
abstract class AppBoxKitOutboundMessageSink {
  /// Channel identifier, e.g. `sms` or `email`.
  String get channel;

  /// Send [message]. Throws on delivery failure so callers can react.
  Future<void> send(AppBoxKitOutboundMessage message);
}
