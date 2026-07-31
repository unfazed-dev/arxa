/// appbox_kit_support — in-app support (feedback + diagnostics) for stacked_kit
/// apps.
///
/// [KitSupportService] runs the `feedback` package's screenshot+annotation flow,
/// bundles an export of the app's INJECTED Talker log history, and routes the
/// typed [FeedbackSubmission] to a swappable [KitSubmissionSink].
/// [LocalFileSubmissionSink] (write to app-documents) is the working default;
/// email and github-issue sinks are file stubs.
///
/// Test doubles live in `appbox_kit_support/testing.dart`.
library;

export 'src/kit_support_types.dart';
export 'src/kit_support_service.dart';

// Sinks
export 'src/sinks/kit_submission_sink.dart';
export 'src/sinks/email_submission_sink.dart';
export 'src/sinks/github_issue_sink.dart';
