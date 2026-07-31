import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../kit_support_types.dart';

/// Where a completed [FeedbackSubmission] goes: a callback/HTTP/file seam.
/// [KitSupportService] never assumes a destination — it routes to whatever
/// sink you inject.
abstract class KitSubmissionSink {
  /// Stable identifier for logging/selection.
  String get id;

  /// Deliver [submission]. Returns a [SubmissionResult] rather than throwing so
  /// the UI can show success/failure without a try/catch at the call site.
  Future<SubmissionResult> submit(FeedbackSubmission submission);
}

/// A [KitSubmissionSink] backed by an arbitrary callback — the simplest seam
/// when the app already has a place to send feedback (a Supabase insert, an
/// existing HTTP client, an in-memory queue).
class CallbackSubmissionSink implements KitSubmissionSink {
  CallbackSubmissionSink(this._onSubmit, {this.id = 'callback'});

  final Future<SubmissionResult> Function(FeedbackSubmission) _onSubmit;

  @override
  final String id;

  @override
  Future<SubmissionResult> submit(FeedbackSubmission submission) =>
      _onSubmit(submission);
}

/// The working default sink: writes the submission to a timestamped folder
/// under the app-documents directory — `feedback.json` (metadata), a
/// `screenshot.png`, and `diagnostics.log` when diagnostics are attached.
///
/// Uses `dart:io`, so it targets mobile/desktop; on web, inject a
/// [CallbackSubmissionSink] instead.
class LocalFileSubmissionSink implements KitSubmissionSink {
  LocalFileSubmissionSink({
    this.id = 'local-file',
    this.subdirectory = 'feedback',
    Future<Directory> Function()? directoryResolver,
  }) : _resolveBaseDir = directoryResolver ?? getApplicationDocumentsDirectory;

  @override
  final String id;

  /// Folder (under the base dir) that submissions are written into.
  final String subdirectory;

  final Future<Directory> Function() _resolveBaseDir;

  @override
  Future<SubmissionResult> submit(FeedbackSubmission submission) async {
    try {
      final base = await _resolveBaseDir();
      final stamp =
          submission.submittedAt.toIso8601String().replaceAll(':', '-');
      final dir = Directory('${base.path}/$subdirectory/$stamp')
        ..createSync(recursive: true);

      File('${dir.path}/screenshot.png').writeAsBytesSync(submission.screenshot);

      final diagnostics = submission.diagnostics;
      final metaFile = File('${dir.path}/feedback.json')
        ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
          'text': submission.text,
          'submittedAt': submission.submittedAt.toIso8601String(),
          'extra': submission.extra,
          'diagnostics': diagnostics == null
              ? null
              : {
                  'entryCount': diagnostics.entryCount,
                  'capturedAt': diagnostics.capturedAt.toIso8601String(),
                  'extra': diagnostics.extra,
                },
        }));

      if (diagnostics != null) {
        File('${dir.path}/diagnostics.log')
            .writeAsStringSync(diagnostics.talkerLog);
      }

      return SubmissionResult.success(
        location: dir.path,
        reference: metaFile.path,
      );
    } catch (error) {
      return SubmissionResult.failure(error);
    }
  }
}
