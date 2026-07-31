import '../kit_notifications_types.dart';
import '../kit_outbound_message_sink.dart';

/// STUB — outbound SMS sink.
///
/// TODO(appbox_kit_notifications): outbound SMS is provider-side, not a device
/// capability. Implement one of:
///   - Twilio / Vonage / MessageBird REST over HTTPS (server-mediated; keep the
///     auth token off-device — call your own backend, not the provider direct).
///   - `another_telephony: ^0.4.x` to send from the device's own SIM (Android
///     only; requires SEND_SMS permission and is Play-policy sensitive).
/// Map KitOutboundMessage.to -> recipient number, .body -> text, .metadata ->
/// { from, messagingServiceSid, ... }.
///
/// This stub imports no SMS client, so no networking/telephony dependency is
/// pulled until a host opts in.
class SmsBackend implements KitOutboundMessageSink {
  SmsBackend();

  @override
  String get channel => 'sms';

  @override
  Future<void> send(KitOutboundMessage message) async =>
      throw UnimplementedError('SmsBackend.send is a stub');
}
