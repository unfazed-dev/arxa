import 'dart:async';

import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stacked_services/stacked_services.dart';

import '../../../services/notifications/appbox_kit_notification_service.dart';
import 'appbox_kit_action.dart';
import 'appbox_kit_notification_type.dart';
import 'managers/appbox_kit_action_state_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AppBoxKitActionPipeline — hot-Subject dispatch, the app-level KitAction API.
// ═══════════════════════════════════════════════════════════════════════════════
//
// Pipes replace per-call builder chains in app code (viewmodels, facades):
// VM methods become sync-shaped dispatchers whose work ALWAYS runs — the lazy
// builder's "dropped chain never runs" footgun is structurally impossible.
//
// Observation-handle contract (async_redux dispatch/dispatchAndWait model):
// - `dispatch(payload)` executes the op HOT and returns `Future<R>` — a handle
//   OBSERVING the already-running op. Awaiting it is optional; dropping it is
//   harmless (its errors are pre-observed, never unhandled).
// - Re-entry guard: a dispatch while the same op key is in flight does NOT
//   re-run the op; its handle completes with the IN-FLIGHT run's result
//   (success or routed error), never with a guard error.
// - Debounce: superseded dispatches' handles complete with the eventual run's
//   result — debounce drops events, never callers.
// - Cancellation is cooperative-only: Dart futures cannot be aborted. A
//   disposed pipeline stops accepting dispatches and tears down subjects, but
//   an in-flight op runs to completion. Need real mid-flight cancel? That is
//   the builder's `toCancellable` (low-level API), not pipes.
//
// Subject discipline: PublishSubject for the per-pipe command channel,
// BehaviorSubject (via AppBoxKitActionStateManager) for busy/error state.
// ═══════════════════════════════════════════════════════════════════════════════

/// Retry policy for a pipe — parity with the builder's `withRetry`.
///
/// The operation re-runs until it succeeds or [maxAttempts] total attempts
/// failed, waiting [delay] between attempts; [shouldRetry] (when set) vetoes
/// a retry. The last failure routes into the pipe's normal error path.
typedef AppBoxKitRetryPolicy = ({
  int maxAttempts,
  Duration? delay,
  bool Function(Exception error)? shouldRetry,
});

/// One named op on an [AppBoxKitActionPipeline]: a hot [PublishSubject]
/// command channel whose single subscription owns execution, busy state, and
/// error routing for the owner's lifetime.
class AppBoxKitActionPipe<P, R> {
  final String name;
  final AppBoxKitActionPipeline _pipeline;
  final _AppBoxKitPipeConfig<P, R> _config;
  // sync: dispatch delivers the command to the subscription IN the dispatch
  // call, so the run starts (and lands in the guard's in-flight registry)
  // synchronously — a same-frame double dispatch always sees the in-flight
  // run, no matter how fast the op completes. With async delivery a fast op
  // could finish before the second command was even processed, and the guard
  // would miss the classic double-tap.
  final PublishSubject<_AppBoxKitCommand<P>> _commands =
      PublishSubject(sync: true);
  late final StreamSubscription<void> _subscription;
  bool _closed = false;

  AppBoxKitActionPipe._(this._pipeline, this.name, this._config) {
    // The single subscription owns execution for the pipe's lifetime — made
    // here, once, at registration (a late-final field would never initialize:
    // nothing reads it until close()).
    _subscription = _commands.stream.listen(_onCommand);
  }

  /// Dispatch the op HOT with [payload] and return an observation handle for
  /// the run's result. See the file header for the full handle contract —
  /// awaiting is optional, dropping is harmless, guarded/debounced dispatches
  /// share the run they resolve to.
  Future<R> dispatch(P payload) {
    final completer = Completer<R>();
    // Pre-observe the handle: a dropped handle must never surface an
    // unhandled async error; an awaited one still delivers result/error.
    completer.future.ignore();
    if (_closed || _pipeline._disposed) {
      completer.completeError(StateError(
          'AppBoxKitActionPipe "$name" is disposed — dispatch dropped'));
      return completer.future;
    }
    _config.onDispatch?.call();
    _commands.add(_AppBoxKitCommand<P>(payload, completer));
    return completer.future;
  }

  /// Live busy/error state, identical to `AppBoxKitViewModel.actionState$`
  /// for the same owner+name (same derived key, same state manager).
  ValueStream<AppBoxKitActionState> get state$ =>
      AppBoxKitActionStateManager.state$(_config.key);

  void _onCommand(_AppBoxKitCommand<P> command) =>
      _pipeline._accept(_config, command.payload, command.completer);

  /// Cancel the subscription first, then close the subject (research-backed
  /// ordering: a closed subject with a live subscription can still be
  /// delivered events; a cancelled subscription cannot).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _commands.close();
  }
}

/// Hot-dispatch pipeline for an owner's ops — the app-level KitAction API.
///
/// ```dart
/// class NotesViewModel extends AppBoxKitViewModel {
///   late final _save = pipeline.pipe<Note, void>(
///     'save',
///     (note) => _repo.put(note),
///     errorMessage: 'Could not save',       // swallow + fallback identity
///     errorNotification: 'Could not save',  // error snackbar
///   );
///
///   Future<void> save(Note note) => _save.dispatch(note);
/// }
/// ```
///
/// Created lazily by `AppBoxKitActionOwner.pipeline` and disposed by
/// `disposeAppBoxKitActions` — no manual wiring in owners.
class AppBoxKitActionPipeline {
  final Object _owner;
  final void Function()? _onDispatch;
  final String? _errorMessage;
  final void Function(Object error)? _onError;

  final List<AppBoxKitActionPipe<dynamic, dynamic>> _pipes = [];

  /// Guard state, keyed by the derived op key and shared by every pipe of
  /// this owner (including one-shot [run]s) — parity with the executor's
  /// static `_inFlight` set keyed by widgetId.
  final Map<String, Future<dynamic>> _inFlight = {};

  final Map<String, _AppBoxKitDebounceSlot> _debounceSlots = {};

  bool _disposed = false;

  AppBoxKitActionPipeline({
    required Object owner,

    /// Runs synchronously on every dispatch of every pipe (e.g. clearing an
    /// inline error before the retry). Pipes override with their own.
    void Function()? onDispatch,

    /// Default error identity (log, state$ stream, fallback marker) — the
    /// builder's `completeOnError(message)`. Pipes override with their own.
    String? errorMessage,

    /// Default error tap — the builder's `handleError`. Pipes override.
    void Function(Object error)? onError,
  })  : _owner = owner,
        _onDispatch = onDispatch,
        _errorMessage = errorMessage,
        _onError = onError;

  /// Register a named op and return its dispatcher. The command-channel
  /// subscription is made ONCE here; execution, busy state, and error routing
  /// live on it.
  ///
  /// - [errorMessage]: error identity for the log / state$ / snackbar — when
  ///   set, failures are swallowed and the handle completes with [withValue]
  ///   (`null` for void/nullable `R`); when null, the handle completes with
  ///   the original error (the builder's no-fallback rethrow).
  /// - [errorNotification] / [successNotification]: user-facing messages
  ///   routed through the same services as the builder's notification
  ///   manager — snackbar (default), dialog, or bottomSheet via
  ///   [errorNotificationType] / [successNotificationType].
  /// - [onError]: side-effect tap with the thrown error (handleError).
  /// - [debounce]: delay execution until no new dispatches for this long;
  ///   superseded handles complete with the eventual run's result.
  /// - [retry]: re-run policy, parity with the builder's `withRetry`.
  /// - [timeout]: per-attempt timeout, parity with the builder's `withTimeout`
  ///   (a timeout raises [TimeoutException] into the error path).
  AppBoxKitActionPipe<P, R> pipe<P, R>(
    String name,
    FutureOr<R> Function(P payload) operation, {
    String? errorMessage,
    R? withValue,
    String? errorNotification,
    AppBoxKitNotificationType errorNotificationType =
        AppBoxKitNotificationType.snackbar,
    String? successNotification,
    AppBoxKitNotificationType successNotificationType =
        AppBoxKitNotificationType.snackbar,
    void Function(Object error)? onError,
    void Function()? onDispatch,
    Duration? debounce,
    AppBoxKitRetryPolicy? retry,
    Duration? timeout,
  }) {
    final pipe = AppBoxKitActionPipe<P, R>._(
      this,
      name,
      _AppBoxKitPipeConfig<P, R>(
        key: AppBoxKitAction.deriveKey(_owner, name),
        operation: operation,
        errorMessage: errorMessage ?? _errorMessage,
        withValue: withValue,
        errorNotification: errorNotification,
        errorNotificationType: errorNotificationType,
        successNotification: successNotification,
        successNotificationType: successNotificationType,
        onError: onError ?? _onError,
        onDispatch: onDispatch ?? _onDispatch,
        debounce: debounce,
        retry: retry,
        timeout: timeout,
      ),
    );
    _pipes.add(pipe);
    return pipe;
  }

  /// One-shot dispatch without a long-lived pipe — for facade-style
  /// `mutate(name: 'pin', entity: id)` calls whose config varies per call.
  /// The ephemeral pipe's channel closes when the run settles; the guard,
  /// debounce, busy state, and error routing are identical to [pipe].
  Future<R> run<R>(
    String name,
    FutureOr<R> Function() operation, {
    String? errorMessage,
    R? withValue,
    String? errorNotification,
    AppBoxKitNotificationType errorNotificationType =
        AppBoxKitNotificationType.snackbar,
    String? successNotification,
    AppBoxKitNotificationType successNotificationType =
        AppBoxKitNotificationType.snackbar,
    void Function(Object error)? onError,
    void Function()? onDispatch,
    Duration? debounce,
    AppBoxKitRetryPolicy? retry,
    Duration? timeout,
  }) {
    final pipe = this.pipe<Null, R>(
      name,
      (_) => operation(),
      errorMessage: errorMessage,
      withValue: withValue,
      errorNotification: errorNotification,
      errorNotificationType: errorNotificationType,
      successNotification: successNotification,
      successNotificationType: successNotificationType,
      onError: onError,
      onDispatch: onDispatch,
      debounce: debounce,
      retry: retry,
      timeout: timeout,
    );
    final handle = pipe.dispatch(null);
    handle.whenComplete(() => _closePipe(pipe)).ignore();
    return handle;
  }

  // ── Dispatch machinery (all dynamic internally; types live on the pipe) ──

  void _accept<P, R>(_AppBoxKitPipeConfig<P, R> config, P payload,
      Completer<R> completer) {
    if (config.debounce != null) {
      return _acceptDebounced(config, payload, completer);
    }
    final inFlight = _inFlight[config.key];
    if (inFlight != null) {
      // Guarded dispatch: never re-runs, never errors — the handle observes
      // the in-flight run's result.
      return _attach(completer, inFlight);
    }
    _start(config, payload, [completer]);
  }

  void _acceptDebounced<P, R>(_AppBoxKitPipeConfig<P, R> config, P payload,
      Completer<R> completer) {
    final slot =
        _debounceSlots.putIfAbsent(config.key, () => _AppBoxKitDebounceSlot());
    slot.timer?.cancel();
    slot.observers.add(completer);
    slot.payload = payload;
    slot.timer = Timer(config.debounce!, () {
      _debounceSlots.remove(config.key);
      final observers = List<Completer<dynamic>>.of(slot.observers);
      final inFlight = _inFlight[config.key];
      if (inFlight != null) {
        for (final observer in observers) {
          _attach(observer, inFlight);
        }
      } else {
        _start(config, slot.payload, observers);
      }
    });
  }

  void _start<P, R>(_AppBoxKitPipeConfig<P, R> config, Object? payload,
      List<Completer<dynamic>> observers) {
    final Future<dynamic> run = _run(config, payload as P);
    run.ignore();
    _inFlight[config.key] = run;
    for (final observer in observers) {
      _attach(observer, run);
    }
    run.whenComplete(() {
      if (identical(_inFlight[config.key], run)) _inFlight.remove(config.key);
    }).ignore();
  }

  void _attach(Completer<dynamic> completer, Future<dynamic> run) {
    run.then((result) {
      if (!completer.isCompleted) completer.complete(result);
    }, onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    });
  }

  /// Executor-parity run: markBusy → op (with retry/timeout) → success
  /// notification | error routing → markDone. Built on rxdart operators:
  /// the attempt factory re-runs the operation per (re)subscription,
  /// `Stream.timeout` applies per attempt, `Rx.retryWhen` re-subscribes
  /// with backoff.
  Future<R> _run<P, R>(_AppBoxKitPipeConfig<P, R> config, P payload) async {
    AppBoxKitActionStateManager.markBusy(config.key);
    var failures = 0;
    Stream<R> attempt() {
      Stream<R> stream =
          Stream<R>.fromFuture(Future<R>.sync(() => config.operation(payload)));
      if (config.timeout != null) {
        stream = stream.timeout(config.timeout!);
      }
      return stream;
    }

    final retry = config.retry;
    final stream = retry != null && retry.maxAttempts > 1
        ? Rx.retryWhen<R>(attempt, (error, stackTrace) {
            failures++;
            if (failures >= retry.maxAttempts) {
              return Stream<void>.error(error, stackTrace);
            }
            final shouldRetry = retry.shouldRetry;
            if (shouldRetry != null) {
              final exception =
                  error is Exception ? error : Exception(error.toString());
              if (!shouldRetry(exception)) {
                return Stream<void>.error(error, stackTrace);
              }
            }
            return Stream<void>.fromFuture(
                Future<void>.delayed(retry.delay ?? Duration.zero));
          })
        : attempt();
    try {
      final result = await stream.first;
      if (config.successNotification != null) {
        _showNotification(
          config.key,
          message: config.successNotification!,
          type: config.successNotificationType,
          kind: AppBoxKitNotificationKind.success,
          title: 'Success',
        );
      }
      return result;
    } catch (error, stackTrace) {
      return _handleError(config, error, stackTrace);
    } finally {
      AppBoxKitActionStateManager.markDone(config.key);
    }
  }

  /// AppBoxKitErrorManager + notification parity: log via the error service,
  /// tap the custom handler, record the message on state$, optional error
  /// notification; then fallback (errorMessage set) or rethrow.
  Future<R> _handleError<P, R>(_AppBoxKitPipeConfig<P, R> config, Object error,
      StackTrace stackTrace) async {
    final errorService = appBoxKitLocator<AppBoxKitErrorService>();
    errorService.handle(
      exception: error,
      stackTrace: stackTrace,
      message: config.errorMessage ?? 'Operation failed',
      widgetId: config.key,
    );

    final onError = config.onError;
    if (onError != null) {
      try {
        onError(error);
      } catch (handlerError, handlerStackTrace) {
        errorService.warning(
          error: handlerError,
          stackTrace: handlerStackTrace,
          message: 'Error in custom error handler',
          widgetId: config.key,
        );
      }
    }

    AppBoxKitActionStateManager.markError(
      config.key,
      config.errorMessage ?? config.errorNotification ?? error.toString(),
    );

    if (config.errorNotification != null) {
      _showNotification(
        config.key,
        message: config.errorNotification!,
        type: config.errorNotificationType,
        kind: AppBoxKitNotificationKind.error,
        title: 'Error',
      );
    }

    if (config.errorMessage != null) {
      // completeOnError parity: swallow, complete with the fallback.
      return config.withValue as R;
    }
    return Future<R>.error(error, stackTrace);
  }

  /// All three notification kinds, same services as the builder's
  /// AppBoxKitNotificationManager (snackbar / dialog / bottomSheet).
  void _showNotification(
    String key, {
    required String message,
    required AppBoxKitNotificationType type,
    required AppBoxKitNotificationKind kind,
    required String title,
  }) {
    try {
      switch (type) {
        case AppBoxKitNotificationType.snackbar:
          appBoxKitLocator<AppBoxKitNotificationService>().show(
            message,
            kind: kind,
            duration: const Duration(seconds: 3),
          );
        case AppBoxKitNotificationType.dialog:
          appBoxKitLocator<DialogService>().showDialog(
            title: title,
            description: message,
            buttonTitle: 'OK',
          );
        case AppBoxKitNotificationType.bottomSheet:
          appBoxKitLocator<BottomSheetService>().showBottomSheet(
            title: title,
            description: message,
          );
        case AppBoxKitNotificationType.none:
          break;
      }
    } catch (e, s) {
      appBoxKitLocator<AppBoxKitErrorService>().warning(
        error: e,
        stackTrace: s,
        message: 'Failed to show notification',
        widgetId: key,
      );
    }
  }

  void _closePipe(AppBoxKitActionPipe<dynamic, dynamic> pipe) {
    _pipes.remove(pipe);
    pipe.close();
  }

  /// Cancel every pipe's subscription, close its subject, cancel pending
  /// debounce timers (their handles complete with a disposed error — safe to
  /// drop, informative to await), and release state$ subjects. In-flight ops
  /// run to completion (cooperative-only — see the file header).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final slot in _debounceSlots.values) {
      slot.timer?.cancel();
      for (final observer in slot.observers) {
        if (!observer.isCompleted) {
          observer.completeError(
              StateError('AppBoxKitActionPipeline disposed before the run'));
        }
      }
    }
    _debounceSlots.clear();
    for (final pipe in List.of(_pipes)) {
      pipe.close();
      AppBoxKitActionStateManager.disposeWidget(pipe._config.key);
    }
    _pipes.clear();
  }
}

// ── Internals ────────────────────────────────────────────────────────────────

class _AppBoxKitCommand<P> {
  final P payload;
  final Completer<dynamic> completer;
  _AppBoxKitCommand(this.payload, this.completer);
}

class _AppBoxKitPipeConfig<P, R> {
  final String key;
  final FutureOr<R> Function(P payload) operation;
  final String? errorMessage;
  final R? withValue;
  final String? errorNotification;
  final AppBoxKitNotificationType errorNotificationType;
  final String? successNotification;
  final AppBoxKitNotificationType successNotificationType;
  final void Function(Object error)? onError;
  final void Function()? onDispatch;
  final Duration? debounce;
  final AppBoxKitRetryPolicy? retry;
  final Duration? timeout;

  _AppBoxKitPipeConfig({
    required this.key,
    required this.operation,
    this.errorMessage,
    this.withValue,
    this.errorNotification,
    this.errorNotificationType = AppBoxKitNotificationType.snackbar,
    this.successNotification,
    this.successNotificationType = AppBoxKitNotificationType.snackbar,
    this.onError,
    this.onDispatch,
    this.debounce,
    this.retry,
    this.timeout,
  });
}

class _AppBoxKitDebounceSlot {
  Timer? timer;
  Object? payload;
  final List<Completer<dynamic>> observers = [];
}
