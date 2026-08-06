/// appbox_kit_support — in-app support (feedback + diagnostics) for appbox_kit
/// apps.
///
/// [AppBoxKitSupportService] runs the `feedback` package's screenshot+annotation flow,
/// bundles an export of the app's INJECTED Talker log history, and routes the
/// typed [AppBoxKitFeedbackSubmission] to a swappable [AppBoxKitSubmissionSink].
/// [AppBoxKitLocalFileSubmissionSink] (write to app-documents) is the working default;
/// email and github-issue sinks are file stubs.
///
/// Test doubles live in `appbox_kit_support/appbox_kit_testing.dart`.
library;

export 'src/appbox_kit_support_types.dart';
export 'src/appbox_kit_support_service.dart';

// Sinks
export 'src/sinks/appbox_kit_submission_sink.dart';
export 'src/sinks/appbox_kit_email_submission_sink.dart';
export 'src/sinks/appbox_kit_github_issue_sink.dart';
