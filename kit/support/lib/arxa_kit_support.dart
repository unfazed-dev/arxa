/// arxa_kit_support — in-app support (feedback + diagnostics) for arxa_kit
/// apps.
///
/// [ArxaKitSupportService] runs the `feedback` package's screenshot+annotation flow,
/// bundles an export of the app's INJECTED Talker log history, and routes the
/// typed [ArxaKitFeedbackSubmission] to a swappable [ArxaKitSubmissionSink].
/// [ArxaKitLocalFileSubmissionSink] (write to app-documents) is the working default;
/// email and github-issue sinks are file stubs.
///
/// Test doubles live in `arxa_kit_support/arxa_kit_testing.dart`.
library;

export 'src/arxa_kit_support_types.dart';
export 'src/arxa_kit_support_service.dart';

// Sinks
export 'src/sinks/arxa_kit_submission_sink.dart';
export 'src/sinks/arxa_kit_email_submission_sink.dart';
export 'src/sinks/arxa_kit_github_issue_sink.dart';
