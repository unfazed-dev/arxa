import '../kit_support_types.dart';
import 'kit_submission_sink.dart';

/// STUB — GitHub-issue submission sink.
///
/// TODO(appbox_kit_support): open an issue from the submission. Implement via
/// GitHub REST `POST /repos/{owner}/{repo}/issues` over HTTPS — but proxy it
/// through YOUR backend so the PAT never ships in the app. Map:
///   - title       -> derived from FeedbackSubmission.text (first line, capped)
///   - body        -> full text + a ```` ```log ```` block of
///                    diagnostics?.talkerLog + selected `extra` context
///   - screenshot  -> upload as an attachment / gist, embed the URL in the body
///                    (the Issues API has no direct binary attachment endpoint)
///   - SubmissionResult.reference -> the created issue number; .location -> its
///     html_url.
///
/// This stub imports no HTTP client, so no networking dependency is pulled until
/// a host opts in.
class GithubIssueSink implements KitSubmissionSink {
  GithubIssueSink({this.id = 'github-issue', this.owner, this.repo});

  @override
  final String id;

  /// Target repository owner once implemented.
  final String? owner;

  /// Target repository name once implemented.
  final String? repo;

  @override
  Future<SubmissionResult> submit(FeedbackSubmission submission) async =>
      throw UnimplementedError('GithubIssueSink.submit is a stub');
}
