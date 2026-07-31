import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show immutable;

/// Diagnostics captured alongside a feedback submission — primarily an export
/// of the app's Talker log history.
@immutable
class DiagnosticsBundle {
  const DiagnosticsBundle({
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
  String toString() => 'DiagnosticsBundle($entryCount entries)';
}

/// A completed feedback submission: the user's annotated screenshot + text,
/// optional diagnostics, and host context.
@immutable
class FeedbackSubmission {
  const FeedbackSubmission({
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

  /// Attached diagnostics, if [KitSupportService] bundled them.
  final DiagnosticsBundle? diagnostics;

  final DateTime submittedAt;

  /// Copy with [diagnostics] attached.
  FeedbackSubmission withDiagnostics(DiagnosticsBundle bundle) =>
      FeedbackSubmission(
        text: text,
        screenshot: screenshot,
        submittedAt: submittedAt,
        extra: extra,
        diagnostics: bundle,
      );

  @override
  String toString() =>
      'FeedbackSubmission(${text.length} chars, ${screenshot.length} bytes'
      '${diagnostics == null ? '' : ', +diagnostics'})';
}

/// Outcome of routing a [FeedbackSubmission] to a sink.
@immutable
class SubmissionResult {
  const SubmissionResult.success({this.reference, this.location})
      : ok = true,
        error = null;

  const SubmissionResult.failure(this.error)
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
      ok ? 'SubmissionResult.success($location)' : 'SubmissionResult.failure($error)';
}
