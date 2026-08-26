/// Test doubles for arxa_kit_support.
///
/// ```dart
/// final sink = RecordingArxaKitSubmissionSink();
/// final talker = Talker();               // real, injected
/// final support = ArxaKitSupportService(talker: talker, sink: sink);
/// final result = await support.submit(arxaKitFakeFeedbackSubmission(
///   diagnostics: arxaKitCannedDiagnosticsBundle(),
/// ));
/// expect(result.ok, isTrue);
/// expect(sink.last!.diagnostics, isNotNull);
/// ```
library;

import 'dart:typed_data' show Uint8List;

import 'src/arxa_kit_support_types.dart';
import 'src/sinks/arxa_kit_submission_sink.dart';

export 'src/arxa_kit_support_types.dart';
export 'src/arxa_kit_support_service.dart';
export 'src/sinks/arxa_kit_submission_sink.dart';

/// A [ArxaKitSubmissionSink] that records every submission and returns a scripted
/// [result] (default: success). Reassign [result] to script a failure.
class RecordingArxaKitSubmissionSink implements ArxaKitSubmissionSink {
  RecordingArxaKitSubmissionSink({
    this.id = 'recording',
    this.result = const ArxaKitSubmissionResult.success(location: 'memory'),
  });

  @override
  final String id;

  /// Returned by [submit].
  ArxaKitSubmissionResult result;

  /// Submissions passed to [submit], in call order.
  final List<ArxaKitFeedbackSubmission> submissions = [];

  @override
  Future<ArxaKitSubmissionResult> submit(ArxaKitFeedbackSubmission submission) async {
    submissions.add(submission);
    return result;
  }

  /// The most recent submission, or null if none.
  ArxaKitFeedbackSubmission? get last =>
      submissions.isEmpty ? null : submissions.last;
}

/// A ready-made [ArxaKitFeedbackSubmission] for tests (a tiny PNG-signature screenshot).
ArxaKitFeedbackSubmission arxaKitFakeFeedbackSubmission({
  String text = 'test feedback',
  Uint8List? screenshot,
  ArxaKitDiagnosticsBundle? diagnostics,
  Map<String, dynamic> extra = const <String, dynamic>{},
  DateTime? submittedAt,
}) =>
    ArxaKitFeedbackSubmission(
      text: text,
      screenshot:
          screenshot ?? Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
      extra: extra,
      diagnostics: diagnostics,
      submittedAt: submittedAt ?? DateTime(2026),
    );

/// A canned [ArxaKitDiagnosticsBundle] for tests — no Talker required.
ArxaKitDiagnosticsBundle arxaKitCannedDiagnosticsBundle({int entryCount = 3}) =>
    ArxaKitDiagnosticsBundle(
      talkerLog: 'INFO  app started\n'
          'DEBUG route -> /home\n'
          'ERROR boom: something went wrong',
      entryCount: entryCount,
      extra: const {'appVersion': '1.0.0-test'},
      capturedAt: DateTime(2026),
    );
