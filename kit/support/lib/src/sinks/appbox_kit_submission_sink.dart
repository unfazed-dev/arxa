import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../appbox_kit_support_types.dart';

/// Where a completed [AppBoxKitFeedbackSubmission] goes: a callback/HTTP/file seam.
/// [AppBoxKitSupportService] never assumes a destination — it routes to whatever
/// sink you inject.
abstract class AppBoxKitSubmissionSink {
  /// Stable identifier for logging/selection.
  String get id;

  /// Deliver [submission]. Returns a [AppBoxKitSubmissionResult] rather than throwing so
  /// the UI can show success/failure without a try/catch at the call site.
  Future<AppBoxKitSubmissionResult> submit(AppBoxKitFeedbackSubmission submission);
}

/// A [AppBoxKitSubmissionSink] backed by an arbitrary callback — the simplest seam
/// when the app already has a place to send feedback (a Supabase insert, an
/// existing HTTP client, an in-memory queue).
class AppBoxKitCallbackSubmissionSink implements AppBoxKitSubmissionSink {
  AppBoxKitCallbackSubmissionSink(this._onSubmit, {this.id = 'callback'});

  final Future<AppBoxKitSubmissionResult> Function(AppBoxKitFeedbackSubmission) _onSubmit;

  @override
  final String id;

  @override
  Future<AppBoxKitSubmissionResult> submit(AppBoxKitFeedbackSubmission submission) =>
      _onSubmit(submission);
}

/// The working default sink: writes the submission to a timestamped folder
/// under the app-documents directory — `feedback.json` (metadata), a
/// `screenshot.png`, and `diagnostics.log` when diagnostics are attached.
///
/// Uses `dart:io`, so it targets mobile/desktop; on web, inject a
/// [AppBoxKitCallbackSubmissionSink] instead.
class AppBoxKitLocalFileSubmissionSink implements AppBoxKitSubmissionSink {
  AppBoxKitLocalFileSubmissionSink({
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
  Future<AppBoxKitSubmissionResult> submit(AppBoxKitFeedbackSubmission submission) async {
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

      return AppBoxKitSubmissionResult.success(
        location: dir.path,
        reference: metaFile.path,
      );
    } catch (error) {
      return AppBoxKitSubmissionResult.failure(error);
    }
  }
}
