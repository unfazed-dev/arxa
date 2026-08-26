import '../arxa_kit_notifications_types.dart';
import '../arxa_kit_outbound_message_sink.dart';

/// STUB — outbound email sink.
///
/// TODO(arxa_kit_notifications): outbound email is provider-side. Implement
/// one of:
///   - Transactional API over HTTPS (SendGrid / Postmark / Resend), mediated by
///     your own backend so the API key never ships in the app.
///   - `mailer: ^6.x` for direct SMTP (server/desktop contexts only — do not
///     embed SMTP credentials in a mobile build).
///   - `flutter_email_sender: ^7.x` to open the native compose sheet (user-sent,
///     not silent — different UX contract; not a true outbound sink).
/// Map ArxaKitOutboundMessage.to -> recipient, .subject -> subject, .body -> body,
/// .metadata -> { from, replyTo, templateId, ... }.
///
/// This stub imports no mail client, so no SMTP/HTTP dependency is pulled until
/// a host opts in.
class ArxaKitEmailBackend implements ArxaKitOutboundMessageSink {
  ArxaKitEmailBackend();

  @override
  String get channel => 'email';

  @override
  Future<void> send(ArxaKitOutboundMessage message) async =>
      throw UnimplementedError('ArxaKitEmailBackend.send is a stub');
}
