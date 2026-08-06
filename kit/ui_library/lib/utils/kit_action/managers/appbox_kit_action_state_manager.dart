import 'package:rxdart/rxdart.dart';

/// Observable per-widgetId state of a [AppBoxKitAction] operation — the stream form
/// of what `withLoading(setBusy)` / `handleError` deliver as callbacks, so
/// views bind `AppBoxKitStreamBuilder(stream: vm.actionState$('save'), …)` instead
/// of plumbing busy flags through the viewmodel.
///
/// [errorMessage] holds the last failure's message (the configured
/// `completeOnError` message, else the exception's `toString()`); it is
/// cleared when the next run of the same widgetId starts, not on success —
/// an error stays visible until the user retries.
class AppBoxKitActionState {
  final bool busy;
  final String? errorMessage;

  const AppBoxKitActionState({this.busy = false, this.errorMessage});
}

/// Static registry of per-widgetId [AppBoxKitActionState] subjects.
///
/// kimitail: subjects are created on READ (`state$`) only, never on write —
/// executor writes target existing subjects. An op started before any view
/// binds reports its transitions to no one (the view sees idle until the next
/// transition); the alternative (create-on-write) leaks one subject per
/// entity-keyed widgetId (`notes.pin.<uuid>`) with no owner to dispose it.
class AppBoxKitActionStateManager {
  AppBoxKitActionStateManager._(); // coverage:ignore-line

  static final Map<String, BehaviorSubject<AppBoxKitActionState>> _subjects = {};

  /// The live state stream for [widgetId] — a seeded [ValueStream], so late
  /// subscribers get the current state immediately (no loading flash).
  static ValueStream<AppBoxKitActionState> state$(String widgetId) =>
      _subjects.putIfAbsent(
        widgetId,
        () => BehaviorSubject<AppBoxKitActionState>.seeded(const AppBoxKitActionState()),
      );

  /// Operation started: busy, stale error cleared.
  static void markBusy(String widgetId) =>
      _write(widgetId, const AppBoxKitActionState(busy: true));

  /// Operation finished (success or after error handling): not busy, the
  /// error (if any) survives until the next [markBusy].
  static void markDone(String widgetId) => _write(
        widgetId,
        AppBoxKitActionState(errorMessage: _current(widgetId).errorMessage),
      );

  /// Operation failed: record the message; busy clears in [markDone].
  static void markError(String widgetId, String message) =>
      _write(widgetId, AppBoxKitActionState(busy: true, errorMessage: message));

  static AppBoxKitActionState _current(String widgetId) =>
      _subjects[widgetId]?.valueOrNull ?? const AppBoxKitActionState();

  static void _write(String widgetId, AppBoxKitActionState state) {
    final subject = _subjects[widgetId];
    if (subject != null && !subject.isClosed) subject.add(state);
  }

  /// Close and drop the subject for [widgetId] (called from
  /// `AppBoxKitAction.dispose`).
  static void disposeWidget(String widgetId) {
    _subjects.remove(widgetId)?.close();
  }
}
