import 'package:rxdart/rxdart.dart';

/// Observable per-widgetId state of a [ArxaKitAction] operation — the stream form
/// of what `withLoading(setBusy)` / `handleError` deliver as callbacks, so
/// views bind `ArxaKitStreamBuilder(stream: vm.actionState$('save'), …)` instead
/// of plumbing busy flags through the viewmodel.
///
/// [errorMessage] holds the last failure's message (the configured
/// `completeOnError` message, else the exception's `toString()`); it is
/// cleared when the next run of the same widgetId starts, not on success —
/// an error stays visible until the user retries.
class ArxaKitActionState {
  final bool busy;
  final String? errorMessage;

  const ArxaKitActionState({this.busy = false, this.errorMessage});
}

/// Static registry of per-widgetId [ArxaKitActionState] subjects.
///
/// kimitail: subjects are created on READ (`state$`) only, never on write —
/// executor writes target existing subjects. An op started before any view
/// binds reports its transitions to no one (the view sees idle until the next
/// transition); the alternative (create-on-write) leaks one subject per
/// entity-keyed widgetId (`notes.pin.<uuid>`) with no owner to dispose it.
class ArxaKitActionStateManager {
  ArxaKitActionStateManager._(); // coverage:ignore-line

  static final Map<String, BehaviorSubject<ArxaKitActionState>> _subjects =
      {};

  /// The live state stream for [widgetId] — a seeded [ValueStream], so late
  /// subscribers get the current state immediately (no loading flash).
  static ValueStream<ArxaKitActionState> state$(String widgetId) =>
      _subjects.putIfAbsent(
        widgetId,
        () => BehaviorSubject<ArxaKitActionState>.seeded(
            const ArxaKitActionState()),
      );

  /// Operation started: busy, stale error cleared.
  static void markBusy(String widgetId) =>
      _write(widgetId, const ArxaKitActionState(busy: true));

  /// Operation finished (success or after error handling): not busy, the
  /// error (if any) survives until the next [markBusy].
  static void markDone(String widgetId) => _write(
        widgetId,
        ArxaKitActionState(errorMessage: _current(widgetId).errorMessage),
      );

  /// Operation failed: record the message; busy clears in [markDone].
  static void markError(String widgetId, String message) =>
      _write(widgetId, ArxaKitActionState(busy: true, errorMessage: message));

  static ArxaKitActionState _current(String widgetId) =>
      _subjects[widgetId]?.valueOrNull ?? const ArxaKitActionState();

  static void _write(String widgetId, ArxaKitActionState state) {
    final subject = _subjects[widgetId];
    if (subject != null && !subject.isClosed) subject.add(state);
  }

  /// Close and drop the subject for [widgetId] (called from
  /// `ArxaKitAction.dispose`).
  static void disposeWidget(String widgetId) {
    _subjects.remove(widgetId)?.close();
  }
}
