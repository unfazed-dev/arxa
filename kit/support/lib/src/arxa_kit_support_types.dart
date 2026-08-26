import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show immutable;

/// Diagnostics captured alongside a feedback submission — primarily an export
/// of the app's Talker log history.
@immutable
class ArxaKitDiagnosticsBundle {
  const ArxaKitDiagnosticsBundle({
    required this.talkerLog,
    required this.capturedAt,
    this.entryCount = 0,
    this.extra = const <String, Object?>{},
  });

  /// Newline-joined Talker log history (most recent last).
  final String talkerLog;

  /// Number of Talker entries included in [talkerLog].
  final int entryCount;

  /// Extra host-supplied context (app version, route, user id, …).
  final Map<String, Object?> extra;

  final DateTime capturedAt;

  @override
  String toString() => 'ArxaKitDiagnosticsBundle($entryCount entries)';
}

/// A completed feedback submission: the user's annotated screenshot + text,
/// optional diagnostics, and host context.
@immutable
class ArxaKitFeedbackSubmission {
  const ArxaKitFeedbackSubmission({
    required this.text,
    required this.screenshot,
    required this.submittedAt,
    this.extra = const <String, dynamic>{},
    this.diagnostics,
  });

  /// Free-text the user typed.
  final String text;

  /// PNG bytes of the annotated screenshot (from the feedback package).
  final Uint8List screenshot;

  /// Host-supplied context merged with the feedback package's `extra`.
  final Map<String, dynamic> extra;

  /// Attached diagnostics, if [ArxaKitSupportService] bundled them.
  final ArxaKitDiagnosticsBundle? diagnostics;

  final DateTime submittedAt;

  /// Copy with [diagnostics] attached.
  ArxaKitFeedbackSubmission withDiagnostics(ArxaKitDiagnosticsBundle bundle) =>
      ArxaKitFeedbackSubmission(
        text: text,
        screenshot: screenshot,
        submittedAt: submittedAt,
        extra: extra,
        diagnostics: bundle,
      );

  @override
  String toString() =>
      'ArxaKitFeedbackSubmission(${text.length} chars, ${screenshot.length} bytes'
      '${diagnostics == null ? '' : ', +diagnostics'})';
}

/// Outcome of routing a [ArxaKitFeedbackSubmission] to a sink.
@immutable
class ArxaKitSubmissionResult {
  const ArxaKitSubmissionResult.success({this.reference, this.location})
      : ok = true,
        error = null;

  const ArxaKitSubmissionResult.failure(this.error)
      : ok = false,
        reference = null,
        location = null;

  final bool ok;

  /// Opaque handle from the sink (issue number, ticket id, file name).
  final String? reference;

  /// Where the submission landed (file path, URL).
  final String? location;

  /// Failure cause when [ok] is false.
  final Object? error;

  @override
  String toString() =>
      ok ? 'ArxaKitSubmissionResult.success($location)' : 'ArxaKitSubmissionResult.failure($error)';
}
