import 'dart:async';

import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import 'package:rxdart/rxdart.dart';

import '../../../services/notifications/appbox_kit_notification_service.dart';
import 'appbox_kit_action.dart';
import 'appbox_kit_notification_type.dart';
import 'managers/appbox_kit_action_state_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AppBoxKitActionHub — hot-Subject send, the app-level KitAction API.
// ═══════════════════════════════════════════════════════════════════════════════
//
// Commands replace per-call builder chains in app code (viewmodels, facades):
// VM methods become sync-shaped commands whose work ALWAYS runs — the lazy
// builder's "dropped chain never runs" footgun is structurally impossible.
//
// Observation-handle contract (async_redux dispatch/dispatchAndWait model):
// - `send(payload)` executes the op HOT and returns `Future<R>` — a handle
//   OBSERVING the already-running op. Awaiting it is optional; dropping it is
//   harmless (its errors are pre-observed, never unhandled).
// - Re-entry guard: a send while the same op key is in flight does NOT
//   re-run the op; its handle completes with the IN-FLIGHT run's result
//   (success or routed error), never with a guard error. Opt out per command
//   with `parallelExecution: true` (flatMap — every send runs).
// - Debounce: superseded sends' handles complete with the eventual run's
//   result — debounce drops events, never callers.
// - Throttle: leading edge, window anchored at the last run's START (builder
//   parity); throttled-away handles complete with the in-flight run's result,
//   else the previous run's.
// - `flushOnDispose`: a pending debounced send runs immediately on
//   dispose (attaching to an in-flight run per guard semantics) instead of
//   being dropped — autosave-style "the last write must land".
// - Cancellation is cooperative-only: Dart futures cannot be aborted. A
//   disposed hub stops accepting sends and tears down subjects, but
//   an in-flight op runs to completion. Need real mid-flight cancel? That is
//   the builder's `toCancellable` (low-level API), not commands.
//
// Subject discipline: PublishSubject for the per-command channel,
// BehaviorSubject (via AppBoxKitActionStateManager) for busy/error state.
// ═══════════════════════════════════════════════════════════════════════════════

/// Retry policy for a command — parity with the builder's `withRetry`.
///
/// The operation re-runs until it succeeds or [maxAttempts] total attempts
/// failed, waiting [delay] between attempts; [shouldRetry] (when set) vetoes
/// a retry. The last failure routes into the command's normal error path.
typedef AppBoxKitRetryPolicy = ({
  int maxAttempts,
  Duration? delay,
  bool Function(Exception error)? shouldRetry,
});

/// One named op on an [AppBoxKitActionHub]: a hot [PublishSubject]
/// command channel whose single subscription owns execution, busy state, and
/// error routing for the owner's lifetime.
class AppBoxKitActionCommand<P, R> {
  final String name;
  final AppBoxKitActionHub _hub;
  final _AppBoxKitCommandConfig _config;
  // sync: send delivers the command to the subscription IN the send
  // call, so the run starts (and lands in the guard's in-flight registry)
  // synchronously — a same-frame double send always sees the in-flight
  // run, no matter how fast the op completes. With async delivery a fast op
  // could finish before the second command was even processed, and the guard
  // would miss the classic double-tap.
  final PublishSubject<_AppBoxKitCommand<P>> _commands =
      PublishSubject(sync: true);
  late final StreamSubscription<void> _subscription;
  bool _closed = false;

  AppBoxKitActionCommand._(this._hub, this.name, this._config) {
    // The single subscription owns execution for the command's lifetime — made
    // here, once, at registration (a late-final field would never initialize:
    // nothing reads it until close()).
    _subscription = _commands.stream.listen(_onCommand);
  }

  /// Send the op HOT with [payload] and return an observation handle for
  /// the run's result. See the file header for the full handle contract —
  /// awaiting is optional, dropping is harmless, guarded/debounced sends
  /// share the run they resolve to.
  Future<R> send(P payload) {
    final completer = Completer<R>();
    // Pre-observe the handle: a dropped handle must never surface an
    // unhandled async error; an awaited one still delivers result/error.
    completer.future.ignore();
    if (_closed || _hub._disposed) {
      completer.completeError(StateError(
          'AppBoxKitActionCommand "$name" is disposed — send dropped'));
      return completer.future;
    }
    _config.onSend?.call();
    _commands.add(_AppBoxKitCommand<P>(payload, completer));
    return completer.future;
  }

  /// Live busy/error state, identical to `AppBoxKitViewModel.actionState$`
  /// for the same owner+name (same derived key, same state manager).
  ValueStream<AppBoxKitActionState> get state$ =>
      AppBoxKitActionStateManager.state$(_config.key);

  void _onCommand(_AppBoxKitCommand<P> command) =>
      _hub._accept(_config, command.payload, command.completer);

  /// Cancel the subscription first, then close the subject (research-backed
  /// ordering: a closed subject with a live subscription can still be
  /// delivered events; a cancelled subscription cannot). A pending debounced
  /// send flushes first when the command opted into `flushOnDispose`.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _hub._flushForDispatcher(_config);
    await _subscription.cancel();
    await _commands.close();
  }
}

/// Hot-send hub for an owner's ops — the app-level KitAction API.
///
/// ```dart
/// class NotesViewModel extends AppBoxKitViewModel {
///   late final _save = abxActionHub.on<Note, void>(
///     'save',
///     (note) => _repo.put(note),
///     errorMessage: 'Could not save',       // swallow + fallback identity
///     errorNotification: 'Could not save',  // error snackbar
///   );
///
///   Future<void> save(Note note) => _save.send(note);
/// }
/// ```
///
/// Created lazily by `AppBoxKitActionOwner.hub` and disposed by
/// `disposeAppBoxKitActions` — no manual wiring in owners.
class AppBoxKitActionHub {
  final Object _owner;
  final void Function()? _onDispatch;
  final String? _errorMessage;
  final void Function(Object error)? _onError;

  final List<AppBoxKitActionCommand<dynamic, dynamic>> _dispatchers = [];

  /// Guard state, keyed by the derived op key and shared by every command of
  /// this owner (including one-shot [send]s) — parity with the executor's
  /// static `_inFlight` set keyed by widgetId.
  final Map<String, Future<dynamic>> _inFlight = {};

  final Map<String, _AppBoxKitDebounceSlot> _debounceSlots = {};

  /// Throttle state: last run START per key (builder parity — the window
  /// anchors at execution start, leading edge).
  final Map<String, DateTime> _throttleWindowStart = {};

  /// Last started run per key (in-flight or settled) — throttled-away
  /// handles observe it when nothing is in flight.
  final Map<String, Future<dynamic>> _lastRun = {};

  bool _disposed = false;

  AppBoxKitActionHub({
    required Object owner,

    /// Runs synchronously on every send of every command (e.g. clearing an
    /// inline error before the retry). Commands override with their own.
    void Function()? onSend,

    /// Default error identity (log, state$ stream, fallback marker) — the
    /// builder's `completeOnError(message)`. Commands override with their own.
    String? errorMessage,

    /// Default error tap — the builder's `handleError`. Commands override.
    void Function(Object error)? onError,
  })  : _owner = owner,
        _onDispatch = onSend,
        _errorMessage = errorMessage,
        _onError = onError;

  /// Register a named op and return its command. The command-channel
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
  /// - [onSuccess]: side-effect tap with the result — awaited AFTER the op
  ///   succeeds and BEFORE the success notification and handle completion
  ///   (the builder's `onSuccess` ordering); tap errors log a warning, they
  ///   never fail the run.
  /// - [debounce]: delay execution until no new dispatches for this long;
  ///   superseded handles complete with the eventual run's result.
  /// - [throttle]: leading edge — the first send runs, later dispatches
  ///   inside the window (anchored at the last run's START, builder parity)
  ///   don't; their handles complete with the in-flight/previous run's
  ///   result. When both are set, debounce wins (builder precedence).
  /// - [parallelExecution]: opt OUT of the re-entry guard (the builder's
  ///   `withParallelExecution`) — every send runs concurrently and each
  ///   handle gets its own run's result.
  /// - [flushOnDispose]: a pending debounced send executes immediately
  ///   when the hub/command disposes (attaching to an in-flight run per
  ///   guard semantics) instead of being dropped; `dispose()` awaits it.
  /// - [retry]: re-run policy, parity with the builder's `withRetry`.
  /// - [timeout]: per-attempt timeout, parity with the builder's `withTimeout`
  ///   (a timeout raises [TimeoutException] into the error path).
  /// - [loadingNotification]: shown at run start (the builder's
  ///   `withLoadingSnackbar`); error/success fire at their transitions.
  /// - [confirmTitle] (+ [confirmMessage] / [confirmActionLabel] /
  ///   [confirmDestructive]): confirmation gate — the run first awaits
  ///   `AppBoxKitNotificationService.confirm`; a decline never executes the op
  ///   (no busy state, no notifications) and the handle completes with
  ///   [withValue] (`null` for void/nullable `R`).
  ///   kimitail: static strings only — a payload-derived message (e.g.
  ///   interpolating the entity name) stays a hand-written VM confirm until
  ///   a second case justifies a function-valued variant.
  AppBoxKitActionCommand<P, R> on<P, R>(
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
    String? loadingNotification,
    AppBoxKitNotificationType loadingNotificationType =
        AppBoxKitNotificationType.snackbar,
    void Function(Object error)? onError,
    FutureOr<void> Function(R result)? onSuccess,
    void Function()? onSend,
    Duration? debounce,
    Duration? throttle,
    bool parallelExecution = false,
    bool flushOnDispose = false,
    AppBoxKitRetryPolicy? retry,
    Duration? timeout,
    String? confirmTitle,
    String? confirmMessage,
    String confirmActionLabel = 'OK',
    bool confirmDestructive = false,
  }) {
    final command = AppBoxKitActionCommand<P, R>._(
      this,
      name,
      // Function-typed config is wrapped into its dynamic erasure HERE, at
      // creation: internally everything is dynamic, and a reified
      // `(String) → Future<String>` read through a `(dynamic) → dynamic`
      // field type would throw on the implicit downcast. Value types flow
      // through as dynamic and land on the reified Completer<R>, whose
      // complete() performs the checked cast.
      _AppBoxKitCommandConfig(
        key: AppBoxKitAction.deriveKey(_owner, name),
        operation: (payload) => operation(payload as P),
        errorMessage: errorMessage ?? _errorMessage,
        withValue: withValue,
        errorNotification: errorNotification,
        errorNotificationType: errorNotificationType,
        successNotification: successNotification,
        successNotificationType: successNotificationType,
        loadingNotification: loadingNotification,
        loadingNotificationType: loadingNotificationType,
        onError: onError ?? _onError,
        onSuccess: onSuccess == null
            ? null
            : (result) => onSuccess(result as R),
        onSend: onSend ?? _onDispatch,
        debounce: debounce,
        throttle: throttle,
        parallelExecution: parallelExecution,
        flushOnDispose: flushOnDispose,
        retry: retry,
        timeout: timeout,
        confirmTitle: confirmTitle,
        confirmMessage: confirmMessage,
        confirmActionLabel: confirmActionLabel,
        confirmDestructive: confirmDestructive,
      ),
    );
    _dispatchers.add(command);
    return command;
  }

  /// One-shot send without a long-lived command — for facade-style
  /// `mutate(name: 'pin', entity: id)` calls whose config varies per call.
  /// The ephemeral command's channel closes when the run settles; the guard,
  /// debounce, busy state, and error routing are identical to [define].
  Future<R> send<R>(
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
    String? loadingNotification,
    AppBoxKitNotificationType loadingNotificationType =
        AppBoxKitNotificationType.snackbar,
    void Function(Object error)? onError,
    FutureOr<void> Function(R result)? onSuccess,
    void Function()? onSend,
    Duration? debounce,
    Duration? throttle,
    bool parallelExecution = false,
    AppBoxKitRetryPolicy? retry,
    Duration? timeout,
  }) {
    final command = this.on<Null, R>(
      name,
      (_) => operation(),
      errorMessage: errorMessage,
      withValue: withValue,
      errorNotification: errorNotification,
      errorNotificationType: errorNotificationType,
      successNotification: successNotification,
      successNotificationType: successNotificationType,
      loadingNotification: loadingNotification,
      loadingNotificationType: loadingNotificationType,
      onError: onError,
      onSuccess: onSuccess,
      onSend: onSend,
      debounce: debounce,
      throttle: throttle,
      parallelExecution: parallelExecution,
      retry: retry,
      timeout: timeout,
    );
    final handle = command.send(null);
    handle.whenComplete(() => _closeDispatcher(command)).ignore();
    return handle;
  }

  // ── Dispatch machinery (all dynamic internally; types live on the command) ──

  void _accept(_AppBoxKitCommandConfig config, Object? payload,
      Completer<dynamic> completer) {
    if (config.debounce != null) {
      return _acceptDebounced(config, payload, completer);
    }
    final throttle = config.throttle;
    if (throttle != null) {
      final windowStart = _throttleWindowStart[config.key];
      if (windowStart != null &&
          DateTime.now().difference(windowStart) < throttle) {
        // Throttled away (leading edge): the handle observes the in-flight
        // run, else the previous run — never an error, never a new run.
        final previous = _inFlight[config.key] ?? _lastRun[config.key];
        if (previous != null) return _attach(completer, previous);
      }
    }
    if (!config.parallelExecution) {
      final inFlight = _inFlight[config.key];
      if (inFlight != null) {
        // Guarded send: never re-runs, never errors — the handle observes
        // the in-flight run's result.
        return _attach(completer, inFlight);
      }
    }
    _start(config, payload, [completer]);
  }

  void _acceptDebounced(_AppBoxKitCommandConfig config, Object? payload,
      Completer<dynamic> completer) {
    final slot =
        _debounceSlots.putIfAbsent(config.key, () => _AppBoxKitDebounceSlot());
    slot.timer?.cancel();
    slot.observers.add(completer);
    slot.payload = payload;
    slot.config = config;
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

  Future<dynamic> _start(_AppBoxKitCommandConfig config, Object? payload,
      List<Completer<dynamic>> observers) {
    if (config.throttle != null) {
      _throttleWindowStart[config.key] = DateTime.now();
    }
    final Future<dynamic> run = _run(config, payload);
    run.ignore();
    _lastRun[config.key] = run;
    if (!config.parallelExecution) {
      // Parallel commands (the builder's withParallelExecution) never enter the
      // guard registry — matching the builder, whose parallel chains skip
      // the static _inFlight set, so guarded ops on the same key don't see
      // them either.
      _inFlight[config.key] = run;
      run.whenComplete(() {
        if (identical(_inFlight[config.key], run)) {
          _inFlight.remove(config.key);
        }
      }).ignore();
    }
    for (final observer in observers) {
      _attach(observer, run);
    }
    return run;
  }

  void _attach(Completer<dynamic> completer, Future<dynamic> run) {
    run.then((result) {
      if (!completer.isCompleted) completer.complete(result);
    }, onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    });
  }

  /// Executor-parity run: markBusy + loading notification → op (with
  /// retry/timeout) → onSuccess tap + success notification | error routing →
  /// markDone. Built on rxdart operators: the attempt factory re-runs the
  /// operation per (re)subscription, `Stream.timeout` applies per attempt,
  /// `Rx.retryWhen` re-subscribes with backoff.
  Future<dynamic> _run(_AppBoxKitCommandConfig config, Object? payload) async {
    // Confirmation gate FIRST: a decline never reaches markBusy, so state$
    // never flickers and no notification fires for an op that never ran.
    if (config.confirmTitle != null) {
      final confirmed =
          await appBoxKitLocator<AppBoxKitNotificationService>().confirm(
        title: config.confirmTitle!,
        message: config.confirmMessage,
        actionLabel: config.confirmActionLabel,
        destructive: config.confirmDestructive,
      );
      if (!confirmed) return config.withValue;
    }
    AppBoxKitActionStateManager.markBusy(config.key);
    if (config.loadingNotification != null) {
      _showNotification(
        config.key,
        message: config.loadingNotification!,
        type: config.loadingNotificationType,
        kind: AppBoxKitNotificationKind.info,
        title: 'Loading',
      );
    }
    var failures = 0;
    Stream<dynamic> attempt() {
      Stream<dynamic> stream = Stream<dynamic>.fromFuture(
          Future<dynamic>.sync(() => config.operation(payload)));
      if (config.timeout != null) {
        stream = stream.timeout(config.timeout!);
      }
      return stream;
    }

    final retry = config.retry;
    final stream = retry != null && retry.maxAttempts > 1
        ? Rx.retryWhen<dynamic>(attempt, (error, stackTrace) {
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
      // Builder ordering: the onSuccess tap is awaited first, then the
      // success notification, then the handle completes. Tap errors log a
      // warning and never fail the run (AppBoxKitSuccessManager parity).
      final onSuccess = config.onSuccess;
      if (onSuccess != null) {
        try {
          await onSuccess(result);
        } catch (e, s) {
          appBoxKitLocator<AppBoxKitErrorService>().warning(
            error: e,
            stackTrace: s,
            message: 'Error in onSuccess callback',
            widgetId: config.key,
          );
        }
      }
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
  Future<dynamic> _handleError(
      _AppBoxKitCommandConfig config, Object error, StackTrace stackTrace) async {
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
      // completeOnError parity: swallow, complete with the fallback (the
      // checked cast to R happens at the reified Completer, not here).
      return config.withValue;
    }
    return Future<dynamic>.error(error, stackTrace);
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
          appBoxKitLocator<AppBoxKitNotificationService>().alert(
            title: title,
            message: message,
          );
        case AppBoxKitNotificationType.bottomSheet:
          appBoxKitLocator<AppBoxKitNotificationService>().notice(
            title: title,
            message: message,
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

  void _closeDispatcher(AppBoxKitActionCommand<dynamic, dynamic> command) {
    _dispatchers.remove(command);
    command.close();
  }

  /// Flush one pending debounce slot: execute the send NOW. Guard
  /// semantics apply — when an op is in flight on the key, the flush attaches
  /// to that run (the pending payload is dropped, exactly like a debounced
  /// send landing while in flight).
  Future<dynamic> _flushSlot(String key, _AppBoxKitDebounceSlot slot) {
    slot.timer?.cancel();
    final observers = List<Completer<dynamic>>.of(slot.observers);
    slot.observers.clear();
    final inFlight = _inFlight[key];
    if (inFlight != null) {
      for (final observer in observers) {
        _attach(observer, inFlight);
      }
      return inFlight;
    }
    return _start(slot.config!, slot.payload, observers);
  }

  /// Command-level dispose hook: a closing command flushes its own pending
  /// debounce slot when it opted into `flushOnDispose`.
  void _flushForDispatcher(_AppBoxKitCommandConfig config) {
    final slot = _debounceSlots[config.key];
    if (slot != null &&
        identical(slot.config, config) &&
        config.flushOnDispose &&
        slot.observers.isNotEmpty) {
      _debounceSlots.remove(config.key);
      _flushSlot(config.key, slot);
    }
  }

  /// Cancel every command's subscription, close its subject, settle pending
  /// debounce slots — `flushOnDispose` slots EXECUTE immediately (awaited
  /// before dispose returns), the rest complete with a disposed error (safe
  /// to drop, informative to await) — and release state$ subjects. In-flight
  /// ops run to completion (cooperative-only — see the file header).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final flushes = <Future<dynamic>>[];
    for (final entry in _debounceSlots.entries) {
      final slot = entry.value;
      if (slot.config?.flushOnDispose == true && slot.observers.isNotEmpty) {
        flushes.add(_flushSlot(entry.key, slot));
      } else {
        slot.timer?.cancel();
        for (final observer in slot.observers) {
          if (!observer.isCompleted) {
            observer.completeError(
                StateError('AppBoxKitActionHub disposed before the run'));
          }
        }
      }
    }
    _debounceSlots.clear();
    for (final command in List.of(_dispatchers)) {
      command.close();
      AppBoxKitActionStateManager.disposeWidget(command._config.key);
    }
    _dispatchers.clear();
    if (flushes.isNotEmpty) await Future.wait(flushes);
  }
}

// ── Internals ────────────────────────────────────────────────────────────────

class _AppBoxKitCommand<P> {
  final P payload;
  final Completer<dynamic> completer;
  _AppBoxKitCommand(this.payload, this.completer);
}

class _AppBoxKitCommandConfig {
  final String key;
  final FutureOr<dynamic> Function(Object? payload) operation;
  final String? errorMessage;
  final dynamic withValue;
  final String? errorNotification;
  final AppBoxKitNotificationType errorNotificationType;
  final String? successNotification;
  final AppBoxKitNotificationType successNotificationType;
  final String? loadingNotification;
  final AppBoxKitNotificationType loadingNotificationType;
  final void Function(Object error)? onError;
  final FutureOr<void> Function(dynamic result)? onSuccess;
  final void Function()? onSend;
  final Duration? debounce;
  final Duration? throttle;
  final bool parallelExecution;
  final bool flushOnDispose;
  final AppBoxKitRetryPolicy? retry;
  final Duration? timeout;
  final String? confirmTitle;
  final String? confirmMessage;
  final String confirmActionLabel;
  final bool confirmDestructive;

  _AppBoxKitCommandConfig({
    required this.key,
    required this.operation,
    this.errorMessage,
    this.withValue,
    this.errorNotification,
    this.errorNotificationType = AppBoxKitNotificationType.snackbar,
    this.successNotification,
    this.successNotificationType = AppBoxKitNotificationType.snackbar,
    this.loadingNotification,
    this.loadingNotificationType = AppBoxKitNotificationType.snackbar,
    this.onError,
    this.onSuccess,
    this.onSend,
    this.debounce,
    this.throttle,
    this.parallelExecution = false,
    this.flushOnDispose = false,
    this.retry,
    this.timeout,
    this.confirmTitle,
    this.confirmMessage,
    this.confirmActionLabel = 'OK',
    this.confirmDestructive = false,
  });
}

class _AppBoxKitDebounceSlot {
  Timer? timer;
  Object? payload;
  _AppBoxKitCommandConfig? config;
  final List<Completer<dynamic>> observers = [];
}
