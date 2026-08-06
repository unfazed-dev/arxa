import '../appbox_kit_support_types.dart';
import 'appbox_kit_submission_sink.dart';

/// STUB — email submission sink.
///
/// TODO(appbox_kit_support): route the submission to an inbox. Implement one:
///   - Transactional API over HTTPS (SendGrid / Postmark / Resend) via YOUR
///     backend so the API key never ships in the app; attach `screenshot.png`
///     and include `diagnostics.talkerLog` as a text part.
///   - `flutter_email_sender: ^7.x` to open the native compose sheet with the
///     screenshot attached (user-sent — a different UX contract).
/// Map AppBoxKitFeedbackSubmission.text -> body, .screenshot -> attachment,
/// .diagnostics?.talkerLog -> attached log, [recipient] -> To.
///
/// This stub imports no mail client, so no SMTP/HTTP dependency is pulled until
/// a host opts in.
class AppBoxKitEmailSubmissionSink implements AppBoxKitSubmissionSink {
  AppBoxKitEmailSubmissionSink({this.id = 'email', this.recipient});

  @override
  final String id;

  /// Destination inbox once implemented.
  final String? recipient;

  @override
  Future<AppBoxKitSubmissionResult> submit(AppBoxKitFeedbackSubmission submission) async =>
      throw UnimplementedError('AppBoxKitEmailSubmissionSink.submit is a stub');
}
