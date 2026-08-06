/// Test doubles for appbox_kit_support.
///
/// ```dart
/// final sink = RecordingAppBoxKitSubmissionSink();
/// final talker = Talker();               // real, injected
/// final support = AppBoxKitSupportService(talker: talker, sink: sink);
/// final result = await support.submit(appBoxKitFakeFeedbackSubmission(
///   diagnostics: appBoxKitCannedDiagnosticsBundle(),
/// ));
/// expect(result.ok, isTrue);
/// expect(sink.last!.diagnostics, isNotNull);
/// ```
library;

import 'dart:typed_data' show Uint8List;

import 'src/appbox_kit_support_types.dart';
import 'src/sinks/appbox_kit_submission_sink.dart';

export 'src/appbox_kit_support_types.dart';
export 'src/appbox_kit_support_service.dart';
export 'src/sinks/appbox_kit_submission_sink.dart';

/// A [AppBoxKitSubmissionSink] that records every submission and returns a scripted
/// [result] (default: success). Reassign [result] to script a failure.
class RecordingAppBoxKitSubmissionSink implements AppBoxKitSubmissionSink {
  RecordingAppBoxKitSubmissionSink({
    this.id = 'recording',
    this.result = const AppBoxKitSubmissionResult.success(location: 'memory'),
  });

  @override
  final String id;

  /// Returned by [submit].
  AppBoxKitSubmissionResult result;

  /// Submissions passed to [submit], in call order.
  final List<AppBoxKitFeedbackSubmission> submissions = [];

  @override
  Future<AppBoxKitSubmissionResult> submit(AppBoxKitFeedbackSubmission submission) async {
    submissions.add(submission);
    return result;
  }

  /// The most recent submission, or null if none.
  AppBoxKitFeedbackSubmission? get last =>
      submissions.isEmpty ? null : submissions.last;
}

/// A ready-made [AppBoxKitFeedbackSubmission] for tests (a tiny PNG-signature screenshot).
AppBoxKitFeedbackSubmission appBoxKitFakeFeedbackSubmission({
  String text = 'test feedback',
  Uint8List? screenshot,
  AppBoxKitDiagnosticsBundle? diagnostics,
  Map<String, dynamic> extra = const <String, dynamic>{},
  DateTime? submittedAt,
}) =>
    AppBoxKitFeedbackSubmission(
      text: text,
      screenshot:
          screenshot ?? Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]),
      extra: extra,
      diagnostics: diagnostics,
      submittedAt: submittedAt ?? DateTime(2026),
    );

/// A canned [AppBoxKitDiagnosticsBundle] for tests — no Talker required.
AppBoxKitDiagnosticsBundle appBoxKitCannedDiagnosticsBundle({int entryCount = 3}) =>
    AppBoxKitDiagnosticsBundle(
      talkerLog: 'INFO  app started\n'
          'DEBUG route -> /home\n'
          'ERROR boom: something went wrong',
      entryCount: entryCount,
      extra: const {'appVersion': '1.0.0-test'},
      capturedAt: DateTime(2026),
    );
