/// Test doubles for appbox_kit_support.
///
/// ```dart
/// final sink = RecordingSubmissionSink();
/// final talker = Talker();               // real, injected
/// final support = KitSupportService(talker: talker, sink: sink);
/// final result = await support.submit(fakeFeedbackSubmission(
///   diagnostics: cannedDiagnosticsBundle(),
/// ));
/// expect(result.ok, isTrue);
/// expect(sink.last!.diagnostics, isNotNull);
/// ```
library;

import 'dart:typed_data' show Uint8List;

import 'src/kit_support_types.dart';
import 'src/sinks/kit_submission_sink.dart';

export 'src/kit_support_types.dart';
export 'src/kit_support_service.dart';
export 'src/sinks/kit_submission_sink.dart';

/// A [KitSubmissionSink] that records every submission and returns a scripted
/// [result] (default: success). Reassign [result] to script a failure.
class RecordingSubmissionSink implements KitSubmissionSink {
  RecordingSubmissionSink({
    this.id = 'recording',
    this.result = const SubmissionResult.success(location: 'memory'),
  });

  @override
  final String id;

  /// Returned by [submit].
  SubmissionResult result;

  /// Submissions passed to [submit], in call order.
  final List<FeedbackSubmission> submissions = [];

  @override
  Future<SubmissionResult> submit(FeedbackSubmission submission) async {
    submissions.add(submission);
    return result;
  }

  /// The most recent submission, or null if none.
  FeedbackSubmission? get last =>
      submissions.isEmpty ? null : submissions.last;
}

/// A ready-made [FeedbackSubmission] for tests (a tiny PNG-signature screenshot).
FeedbackSubmission fakeFeedbackSubmission({
  String text = 'test feedback',
  Uint8List? screenshot,
  DiagnosticsBundle? diagnostics,
  Map<String, dynamic> extra = const <String, dynamic>{},
  DateTime? submittedAt,
}) =>
    FeedbackSubmission(
      text: text,
      screenshot:
          screenshot ?? Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
      extra: extra,
      diagnostics: diagnostics,
      submittedAt: submittedAt ?? DateTime(2026),
    );

/// A canned [DiagnosticsBundle] for tests — no Talker required.
DiagnosticsBundle cannedDiagnosticsBundle({int entryCount = 3}) =>
    DiagnosticsBundle(
      talkerLog: 'INFO  app started\n'
          'DEBUG route -> /home\n'
          'ERROR boom: something went wrong',
      entryCount: entryCount,
      extra: const {'appVersion': '1.0.0-test'},
      capturedAt: DateTime(2026),
    );
