import 'dart:async';
import 'arxa_kit_action_builder.dart';
import 'managers/arxa_kit_stream_manager.dart';
import 'managers/arxa_kit_action_state_manager.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_core/services/error/arxa_kit_error_service.dart';
import 'package:rxdart/rxdart.dart' show ValueStream;

export 'managers/arxa_kit_action_state_manager.dart'
    show ArxaKitActionState;
export 'arxa_kit_action_builder.dart' show ArxaKitActionBuilder;

// ═══════════════════════════════════════════════════════════════════════════════
// ArxaKitAction v2.0 - Main Facade
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities (Facade)
//    - Section 5.1: Main API Surface
//
// This class provides the main entry point for ArxaKitAction operations.
// See specification for complete API documentation and design principles.
// ═══════════════════════════════════════════════════════════════════════════════

/// Main entry point for ArxaKitAction - a fluent API for executing operations
///
/// **Low-level API.** App code (viewmodels, facades) should prefer
/// [ArxaKitActionHub] commands via `ArxaKitActionOwner.hub` — hot
/// send with observation handles. This builder remains for the advanced
/// forms commands don't cover: `toStream`, `toCancellable`, per-call
/// throttle/debounce timers, and parallel execution.
///
/// ArxaKitAction provides automatic error handling, loading state management,
/// user notifications, and reactive stream support with a clean, chainable API.
/// The builder runs when awaited — no terminal `.execute()` needed in app code.
///
/// **Basic Usage:**
/// ```dart
/// await ArxaKitAction.run<User>(
///   () => fetchUser(id),
///   owner: this,
///   name: 'fetchUser',
/// )
///   .withLoading(setBusy)
///   .completeOnError('Failed to load user', withValue: User.empty())
///   .withSnackbars(success: 'User loaded', error: 'Load failed');
/// ```
///
/// **With Retry:**
/// ```dart
/// await ArxaKitAction.run<String>(
///   () => apiCall(),
///   owner: this,
///   name: 'apiCall',
/// )
///   .withRetry(maxAttempts: 3, delay: Duration(seconds: 1))
///   .withTimeout(Duration(seconds: 30));
/// ```
///
/// **Reactive Streams:**
/// ```dart
/// final stream = ArxaKitAction.run<User>(
///   () => fetchUser(id),
///   owner: this,
///   name: 'fetchUser',
/// ).toStream(initialValue: User.empty());
///
/// stream.listen((user) => print('User: ${user.name}'));
/// ```
///
/// **Cancellable Operations:**
/// ```dart
/// final cancellable = ArxaKitAction.run<String>(
///   () async {
///     await Future.delayed(Duration(seconds: 5));
///     return 'result';
///   },
///   owner: this,
///   name: 'longOperation',
/// ).toCancellable();
///
/// // Later...
/// cancellable.cancel();
/// ```
class ArxaKitAction {
  // Private constructor to prevent instantiation
  ArxaKitAction._(); // coverage:ignore-line

  // Track stream subscriptions by widgetId for cleanup
  static final Map<String, List<StreamSubscription>> _subscriptions = {};

  // Owner → derived registry keys. Expando keys by identity and never retains
  // the owner: a dead viewmodel's entry is collectable even if disposeOwner
  // was somehow skipped (belt; the mixin/base-class dispose is the braces).
  static final Expando<List<String>> _ownerKeys =
      Expando<List<String>>('ArxaKitAction.ownerKeys');

  /// Derives the registry key for an owner + name pair —
  /// `RuntimeType#identityHash.name` (`ShowcaseNotesViewModel#4123.save`). The
  /// identity hash discriminates two live instances of the same class (the
  /// note editor pushed twice), so their ops never share a re-entry guard or
  /// state subject; `run`/`listen`/`state$` all derive from the same owner
  /// object, so the pair always resolves to the same key. The string is a
  /// diagnostic label and registry key, never hand-written at call sites.
  ///
  /// Public so [ArxaKitActionHub] derives byte-identical keys — command
  /// and builder ops with the same owner+name share one state subject.
  static String deriveKey(Object owner, String? name) {
    final base = '${owner.runtimeType}#${identityHashCode(owner)}';
    return name == null ? base : '$base.$name';
  }

  static String _track(Object owner, String? name) {
    final key = deriveKey(owner, name);
    final keys = _ownerKeys[owner] ??= [];
    if (!keys.contains(key)) keys.add(key);
    return key;
  }

  /// Execute an operation with automatic handling
  ///
  /// Returns a [ArxaKitActionBuilder] that can be configured with chainable methods
  /// and runs when awaited (or via `execute()` for fire-and-forget).
  ///
  /// 📖 **Specification Reference:**
  ///    - Section 5.1: Main API Surface (lines 606-622)
  ///    - Section 6.1: Basic Patterns (PATTERN 1-9)
  ///
  /// **Ownership:** pass [owner] (`this` from a viewmodel/facade) + a short
  /// [name] label (`'save'`; entity ops append the entity id: `'pin.${note.id}'`).
  /// The registry key is derived (`RuntimeType.name`) and everything the op
  /// creates — subscriptions, state subjects, in-flight guards — dies with
  /// [disposeOwner], which `ArxaKitViewModel.dispose` calls for you. The bare
  /// [widgetId] form remains for ownerless contexts (e.g. `main()` boot).
  /// Inside a `ArxaKitViewModel`/`ArxaKitActionOwner` use the `action(name, operation)`
  /// helper instead — it passes `owner: this` for you.
  ///
  /// **Parameters:**
  /// - [operation]: The operation to execute (sync or async)
  /// - [owner]: Object whose lifecycle owns this op (viewmodel/facade/service)
  /// - [name]: Short operation label — combined into the derived key
  /// - [widgetId]: Explicit key (ownerless ops only)
  ///
  /// **Example:**
  /// ```dart
  /// await ArxaKitAction.run<String>(
  ///   () async => 'result',
  ///   owner: this,
  ///   name: 'save',
  /// )
  ///   .withErrorSnackbar('Could not save');
  /// ```
  static ArxaKitActionBuilder<T> run<T>(
    FutureOr<T> Function() operation, {
    Object? owner,
    String? name,
    String? widgetId,
  }) {
    assert(
      owner != null || widgetId != null,
      'ArxaKitAction.run needs an owner (+name) or an explicit widgetId',
    );
    return ArxaKitActionBuilder<T>(
      operation: operation,
      widgetId: owner != null ? _track(owner, name) : widgetId!,
    );
  }

  /// Listen to streams with automatic subscription management
  ///
  /// Sets up reactive listeners that trigger [callback] when any stream emits.
  /// Accepts any [Stream] — BehaviorSubjects, single-subscription streams, or
  /// composed pipelines. For dependent re-subscription (e.g. re-watching user
  /// data when the session changes), compose with rxdart first
  /// (`session$.switchMap((s) => ...)`) and listen the single resulting stream
  /// instead of nesting listeners.
  ///
  /// The [callback] receives the emitted value; use `(_) => ...` when the
  /// value isn't needed (a bare `rebuildUi` tear-off does not type-check).
  ///
  /// **Parameters:**
  /// - [owner]: Object whose lifecycle owns this listener (viewmodel/service)
  /// - [name]: Short listener label — combined into the derived key
  /// - [widgetId]: Explicit key (ownerless listeners only)
  /// - [streams]: Streams to listen (any mix of types)
  /// - [callback]: Callback executed with the emitted value when any stream emits
  /// - [errorMessage]: Optional error message for logging
  /// - [onError]: Optional error handler (receives the error object)
  ///
  /// **Example:**
  /// ```dart
  /// ArxaKitAction.listen(
  ///   owner: this,
  ///   name: 'profile',
  ///   to: [userSubject$, settingsSubject$],
  ///   onData: (_) => rebuildUi(),
  ///   errorMessage: 'Failed to listen user changes',
  /// );
  /// ```
  ///
  /// **Important:** Owners registered in get_it must call [disposeOwner] from
  /// their own dispose; `ArxaKitViewModel.dispose` already does.
  static void listen({
    Object? owner,
    String? name,
    String? widgetId,
    required List<Stream<dynamic>> to,
    required void Function(dynamic value) onData,
    String? errorMessage,
    void Function(Object error)? onError,
  }) {
    assert(
      owner != null || widgetId != null,
      'ArxaKitAction.listen needs an owner (+name) or an explicit widgetId',
    );
    final key = owner != null ? _track(owner, name) : widgetId!;
    final errorService = arxaKitLocator<ArxaKitErrorService>();

    // Subscribe to all streams and call onData on emissions
    for (final stream in to) {
      final subscription = stream.listen(
        (value) {
          try {
            onData(value);
          } catch (error, stackTrace) {
            if (onError != null) {
              onError(error);
            } else {
              errorService.handle(
                exception: error,
                stackTrace: stackTrace,
                message: errorMessage ?? 'Error in stream listener onData',
                widgetId: widgetId,
              );
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (onError != null) {
            onError(error);
          } else {
            errorService.handle(
              exception: error,
              stackTrace: stackTrace,
              message: errorMessage ?? 'Error in stream',
              widgetId: key,
            );
          }
        },
      );

      // Track subscription for later disposal
      _subscriptions.putIfAbsent(key, () => []).add(subscription);
    }
  }

  /// Live [ArxaKitActionState] stream (busy + last error) for an operation — the
  /// stream form of `withLoading(setBusy)`, so views bind it with
  /// `ArxaKitStreamBuilder` instead of plumbing busy flags through the viewmodel.
  /// Seeded [ValueStream]: late subscribers see the current state
  /// immediately. Address it by [owner]+[name] (same pair the `run` used); the
  /// bare [widgetId] form is for ownerless ops. `ArxaKitViewModel.actionState$`
  /// is the usual call path.
  static ValueStream<ArxaKitActionState> state$({
    Object? owner,
    String? name,
    String? widgetId,
  }) {
    assert(
      owner != null || widgetId != null,
      'ArxaKitAction.state\$ needs an owner (+name) or an explicit widgetId',
    );
    return ArxaKitActionStateManager.state$(
      owner != null ? deriveKey(owner, name) : widgetId!,
    );
  }

  /// Dispose EVERYTHING an owner created — every op's subscriptions, state
  /// subjects, and tracked streams. `ArxaKitViewModel.dispose` calls this;
  /// facades/services registered in get_it call it from their own dispose.
  static void disposeOwner(Object owner) {
    final keys = _ownerKeys[owner];
    if (keys == null) return;
    for (final key in List.of(keys)) {
      dispose(widgetId: key);
    }
    _ownerKeys[owner] = null;
  }

  /// Dispose subscriptions for a specific widget
  ///
  /// This is a compatibility method for migrating from ArxaKitAutoProcess.
  /// It cleans up all reactive subscriptions associated with the given widgetId.
  ///
  /// 📖 **Specification Reference:**
  ///    - Section 5.1: Main API Surface (lines 647-659)
  ///    - Section 9.1: Memory Management
  ///
  /// **Parameters:**
  /// - [widgetId]: The widget ID to dispose subscriptions for
  ///
  /// **Example:**
  /// ```dart
  /// @override
  /// void dispose() {
  ///   ArxaKitAction.dispose(widgetId: 'profile_view');
  ///   super.dispose();
  /// }
  /// ```
  static void dispose({required String widgetId}) {
    // Cancel all stream subscriptions for this widget
    final subscriptions = _subscriptions[widgetId];
    if (subscriptions != null) {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      _subscriptions.remove(widgetId);
    }

    // Also dispose any tracked subjects in ArxaKitStreamManager
    ArxaKitStreamManager.disposeWidget(widgetId);
    // And the observable action-state subject, if any view bound state$()
    ArxaKitActionStateManager.disposeWidget(widgetId);
  }
}
