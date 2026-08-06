import 'dart:async';
import 'kit_action_builder.dart';
import 'managers/stream_manager.dart';
import 'managers/action_state_manager.dart';
import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import 'package:rxdart/rxdart.dart' show ValueStream;

export 'managers/action_state_manager.dart' show KitActionState;

// ═══════════════════════════════════════════════════════════════════════════════
// KitAction v2.0 - Main Facade
// ═══════════════════════════════════════════════════════════════════════════════
//
// 📖 Technical Specification: docs/kit_action_technical_specification.md
//    - Section 4.2: Component Responsibilities (Facade)
//    - Section 5.1: Main API Surface
//
// This class provides the main entry point for KitAction operations.
// See specification for complete API documentation and design principles.
// ═══════════════════════════════════════════════════════════════════════════════

/// Main entry point for KitAction - a fluent API for executing operations
///
/// KitAction provides automatic error handling, loading state management,
/// user notifications, and reactive stream support with a clean, chainable API.
///
/// **Basic Usage:**
/// ```dart
/// await KitAction.run<User>(
///   operation: () => fetchUser(id),
///   widgetId: 'profile',
/// )
///   .withLoading(setBusy)
///   .withErrorFallback('Failed to load user', fallback: User.empty())
///   .withSnackbars(success: 'User loaded', error: 'Load failed')
///   .execute();
/// ```
///
/// **With Retry:**
/// ```dart
/// await KitAction.run<String>(
///   operation: () => apiCall(),
///   widgetId: 'api',
/// )
///   .withRetry(maxAttempts: 3, delay: Duration(seconds: 1))
///   .withTimeout(Duration(seconds: 30))
///   .execute();
/// ```
///
/// **Reactive Streams:**
/// ```dart
/// final stream = KitAction.run<User>(
///   operation: () => fetchUser(id),
///   widgetId: 'profile',
/// )
///   .asStream(initialValue: User.empty())
///   .executeAsStream();
///
/// stream.listen((user) => print('User: ${user.name}'));
/// ```
///
/// **Cancellable Operations:**
/// ```dart
/// final cancellable = KitAction.run<String>(
///   operation: () async {
///     await Future.delayed(Duration(seconds: 5));
///     return 'result';
///   },
///   widgetId: 'long_operation',
/// )
///   .asCancellable()
///   .executeAsCancellable();
///
/// // Later...
/// cancellable.cancel();
/// ```
class KitAction {
  // Private constructor to prevent instantiation
  KitAction._(); // coverage:ignore-line

  // Track stream subscriptions by widgetId for cleanup
  static final Map<String, List<StreamSubscription>> _subscriptions = {};

  // Owner → derived registry keys. Expando keys by identity and never retains
  // the owner: a dead viewmodel's entry is collectable even if disposeOwner
  // was somehow skipped (belt; the mixin/base-class dispose is the braces).
  static final Expando<List<String>> _ownerKeys =
      Expando<List<String>>('KitAction.ownerKeys');

  /// Derives the registry key for an owner + op pair —
  /// `RuntimeType#identityHash.op` (`ShowcaseNotesViewModel#4123.save`). The
  /// identity hash discriminates two live instances of the same class (the
  /// note editor pushed twice), so their ops never share a re-entry guard or
  /// state subject; `run`/`watch`/`state$` all derive from the same owner
  /// object, so the pair always resolves to the same key. The string is a
  /// diagnostic label and registry key, never hand-written at call sites.
  static String _deriveKey(Object owner, String? op) {
    final base = '${owner.runtimeType}#${identityHashCode(owner)}';
    return op == null ? base : '$base.$op';
  }

  static String _track(Object owner, String? op) {
    final key = _deriveKey(owner, op);
    final keys = _ownerKeys[owner] ??= [];
    if (!keys.contains(key)) keys.add(key);
    return key;
  }

  /// Execute an operation with automatic handling
  ///
  /// Returns a [KitActionBuilder] that can be configured with chainable methods.
  ///
  /// 📖 **Specification Reference:**
  ///    - Section 5.1: Main API Surface (lines 606-622)
  ///    - Section 6.1: Basic Patterns (PATTERN 1-9)
  ///
  /// **Ownership:** pass [owner] (`this` from a viewmodel/facade) + a short
  /// [op] label (`'save'`; entity ops append the entity id: `'pin.${note.id}'`).
  /// The registry key is derived (`RuntimeType.op`) and everything the op
  /// creates — subscriptions, state subjects, in-flight guards — dies with
  /// [disposeOwner], which `KitViewModel.dispose` calls for you. The bare
  /// [widgetId] form remains for ownerless contexts (e.g. `main()` boot).
  ///
  /// **Parameters:**
  /// - [operation]: The operation to execute (sync or async)
  /// - [owner]: Object whose lifecycle owns this op (viewmodel/facade/service)
  /// - [op]: Short operation label — combined into the derived key
  /// - [widgetId]: Explicit key (ownerless ops only)
  ///
  /// **Example:**
  /// ```dart
  /// await KitAction.run<String>(
  ///   operation: () async => 'result',
  ///   owner: this,
  ///   op: 'save',
  /// )
  ///   .withErrorSnackbar('Could not save')
  ///   .execute();
  /// ```
  static KitActionBuilder<T> run<T>({
    required FutureOr<T> Function() operation,
    Object? owner,
    String? op,
    String? widgetId,
  }) {
    assert(
      owner != null || widgetId != null,
      'KitAction.run needs an owner (+op) or an explicit widgetId',
    );
    return KitActionBuilder<T>(
      operation: operation,
      widgetId: owner != null ? _track(owner, op) : widgetId!,
    );
  }

  /// Watch streams with automatic subscription management
  ///
  /// Sets up reactive listeners that trigger [callback] when any stream emits.
  /// Accepts any [Stream] — BehaviorSubjects, single-subscription streams, or
  /// composed pipelines. For dependent re-subscription (e.g. re-watching user
  /// data when the session changes), compose with rxdart first
  /// (`session$.switchMap((s) => ...)`) and watch the single resulting stream
  /// instead of nesting listeners.
  ///
  /// The [callback] receives the emitted value; use `(_) => ...` when the
  /// value isn't needed (a bare `rebuildUi` tear-off does not type-check).
  ///
  /// **Parameters:**
  /// - [widgetId]: Unique identifier for tracking subscriptions
  /// - [streams]: Streams to watch (any mix of types)
  /// - [callback]: Callback executed with the emitted value when any stream emits
  /// - [errorMessage]: Optional error message for logging
  /// - [onError]: Optional error handler
  ///
  /// **Example:**
  /// ```dart
  /// KitAction.watch(
  ///   widgetId: 'profile_view',
  ///   streams: [userSubject$, settingsSubject$],
  ///   callback: (_) => rebuildUi(),
  ///   errorMessage: 'Failed to watch user changes',
  /// );
  /// ```
  ///
  /// **Important:** Call [dispose] in your widget/viewmodel dispose method:
  /// ```dart
  /// @override
  /// void dispose() {
  ///   KitAction.dispose(widgetId: 'profile_view');
  ///   super.dispose();
  /// }
  /// ```
  static void watch({
    Object? owner,
    String? op,
    String? widgetId,
    required List<Stream<dynamic>> streams,
    required void Function(dynamic value) callback,
    String? errorMessage,
    Function(Exception, StackTrace)? onError,
  }) {
    assert(
      owner != null || widgetId != null,
      'KitAction.watch needs an owner (+op) or an explicit widgetId',
    );
    final key = owner != null ? _track(owner, op) : widgetId!;
    final errorService = locator<KitErrorService>();

    // Subscribe to all streams and call callback on emissions
    for (final stream in streams) {
      final subscription = stream.listen(
        (value) {
          try {
            callback(value);
          } catch (e, stackTrace) {
            if (onError != null && e is Exception) {
              onError(e, stackTrace);
            } else {
              errorService.handle(
                exception: e,
                stackTrace: stackTrace,
                message: errorMessage ?? 'Error in stream watcher callback',
                widgetId: widgetId,
              );
            }
          }
        },
        onError: (error, stackTrace) {
          if (onError != null && error is Exception) {
            onError(error, stackTrace);
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

  /// Live [KitActionState] stream (busy + last error) for an operation — the
  /// stream form of `withLoading(setBusy)`, so views bind it with
  /// `KitStreamBuilder` instead of plumbing busy flags through the viewmodel.
  /// Seeded [ValueStream]: late subscribers see the current state
  /// immediately. Address it by [owner]+[op] (same pair the `run` used); the
  /// bare [widgetId] form is for ownerless ops. `KitViewModel.actionState$`
  /// is the usual call path.
  static ValueStream<KitActionState> state$({
    Object? owner,
    String? op,
    String? widgetId,
  }) {
    assert(
      owner != null || widgetId != null,
      'KitAction.state\$ needs an owner (+op) or an explicit widgetId',
    );
    return KitActionStateManager.state$(
      owner != null ? _deriveKey(owner, op) : widgetId!,
    );
  }

  /// Dispose EVERYTHING an owner created — every op's subscriptions, state
  /// subjects, and tracked streams. `KitViewModel.dispose` calls this;
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
  /// This is a compatibility method for migrating from KitAutoProcess.
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
  ///   KitAction.dispose(widgetId: 'profile_view');
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

    // Also dispose any tracked subjects in StreamManager
    StreamManager.disposeWidget(widgetId);
    // And the observable action-state subject, if any view bound state$()
    KitActionStateManager.disposeWidget(widgetId);
  }
}
