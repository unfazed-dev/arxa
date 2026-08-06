import 'dart:async';

import 'package:feedback/feedback.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:talker_flutter/talker_flutter.dart' show Talker;

import 'appbox_kit_support_types.dart';
import 'sinks/appbox_kit_submission_sink.dart';

/// Builds extra context attached to every submission (app version, current
/// route, user id, feature flags, …). May be async.
typedef AppBoxKitSupportContextBuilder = FutureOr<Map<String, dynamic>> Function();

/// The kit's in-app support service: runs the screenshot+annotation feedback
/// flow, bundles the injected Talker's log export, and routes the result to a
/// swappable [AppBoxKitSubmissionSink].
///
/// The [talker] is INJECTED — apps already register a `Talker` as a lazy
/// singleton, so this service reads from that instance rather than creating a
/// competing logger. Standalone: no dependency on `appbox_kit` core.
class AppBoxKitSupportService {
  AppBoxKitSupportService({
    required this.talker,
    required this.sink,
    this.contextBuilder,
    this.attachDiagnosticsByDefault = true,
    this.maxDiagnosticEntries = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The app's already-registered Talker. Never constructed here.
  final Talker talker;

  /// Destination for completed submissions.
  final AppBoxKitSubmissionSink sink;

  /// Optional host-context provider merged into each submission's `extra`.
  final AppBoxKitSupportContextBuilder? contextBuilder;

  /// Whether [startFeedbackFlow] attaches diagnostics unless told otherwise.
  final bool attachDiagnosticsByDefault;

  /// Cap on Talker entries exported into a [AppBoxKitDiagnosticsBundle] (most recent
  /// kept). Guards against unbounded log histories bloating a submission.
  final int maxDiagnosticEntries;

  final DateTime Function() _clock;

  /// Open the feedback flow (screenshot + annotation + text). Completes with the
  /// typed [AppBoxKitFeedbackSubmission] once the user submits, or null if they dismiss.
  ///
  /// Requires a `BetterFeedback` ancestor at the app root (host wiring).
  Future<AppBoxKitFeedbackSubmission?> startFeedbackFlow(
    BuildContext context, {
    bool? attachDiagnostics,
  }) {
    final completer = Completer<AppBoxKitFeedbackSubmission?>();
    // Resolve the controller synchronously — no BuildContext use after an await.
    final controller = BetterFeedback.of(context);
    controller.show((UserFeedback feedback) async {
      final hostContext = await _buildContext();
      var submission = AppBoxKitFeedbackSubmission(
        text: feedback.text,
        screenshot: feedback.screenshot,
        extra: <String, dynamic>{
          if (hostContext != null) ...hostContext,
          if (feedback.extra != null) ...feedback.extra!,
        },
        submittedAt: _clock(),
      );
      if (attachDiagnostics ?? attachDiagnosticsByDefault) {
        submission = withDiagnostics(submission);
      }
      if (!completer.isCompleted) completer.complete(submission);
    });
    return completer.future;
  }

  /// Attach a fresh [AppBoxKitDiagnosticsBundle] (Talker export) to [submission].
  AppBoxKitFeedbackSubmission withDiagnostics(AppBoxKitFeedbackSubmission submission) =>
      submission.withDiagnostics(captureDiagnostics());

  /// Snapshot the injected Talker's current log history as a [AppBoxKitDiagnosticsBundle],
  /// capped at [maxDiagnosticEntries] (most recent kept).
  AppBoxKitDiagnosticsBundle captureDiagnostics({
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final history = talker.history;
    final kept = history.length > maxDiagnosticEntries
        ? history.sublist(history.length - maxDiagnosticEntries)
        : history;
    final text = kept.map((entry) => entry.generateTextMessage()).join('\n');
    return AppBoxKitDiagnosticsBundle(
      talkerLog: text,
      entryCount: kept.length,
      extra: extra,
      capturedAt: _clock(),
    );
  }

  /// Route a completed [submission] to the configured [sink].
  Future<AppBoxKitSubmissionResult> submit(AppBoxKitFeedbackSubmission submission) =>
      sink.submit(submission);

  /// Convenience: run the flow and, if the user submitted, route to the sink.
  /// Returns null if the user dismissed without submitting.
  Future<AppBoxKitSubmissionResult?> collectAndSubmit(
    BuildContext context, {
    bool? attachDiagnostics,
  }) async {
    final submission = await startFeedbackFlow(
      context,
      attachDiagnostics: attachDiagnostics,
    );
    if (submission == null) return null;
    return submit(submission);
  }

  Future<Map<String, dynamic>?> _buildContext() async {
    final builder = contextBuilder;
    if (builder == null) return null;
    return builder();
  }
}
