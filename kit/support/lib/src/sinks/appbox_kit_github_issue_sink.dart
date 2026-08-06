import '../appbox_kit_support_types.dart';
import 'appbox_kit_submission_sink.dart';

/// STUB — GitHub-issue submission sink.
///
/// TODO(appbox_kit_support): open an issue from the submission. Implement via
/// GitHub REST `POST /repos/{owner}/{repo}/issues` over HTTPS — but proxy it
/// through YOUR backend so the PAT never ships in the app. Map:
///   - title       -> derived from AppBoxKitFeedbackSubmission.text (first line, capped)
///   - body        -> full text + a ```` ```log ```` block of
///                    diagnostics?.talkerLog + selected `extra` context
///   - screenshot  -> upload as an attachment / gist, embed the URL in the body
///                    (the Issues API has no direct binary attachment endpoint)
///   - AppBoxKitSubmissionResult.reference -> the created issue number; .location -> its
///     html_url.
///
/// This stub imports no HTTP client, so no networking dependency is pulled until
/// a host opts in.
class AppBoxKitGithubIssueSink implements AppBoxKitSubmissionSink {
  AppBoxKitGithubIssueSink({this.id = 'github-issue', this.owner, this.repo});

  @override
  final String id;

  /// Target repository owner once implemented.
  final String? owner;

  /// Target repository name once implemented.
  final String? repo;

  @override
  Future<AppBoxKitSubmissionResult> submit(AppBoxKitFeedbackSubmission submission) async =>
      throw UnimplementedError('AppBoxKitGithubIssueSink.submit is a stub');
}
