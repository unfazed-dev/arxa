import 'dart:async';

import 'package:rxdart/rxdart.dart' show ValueStream;

import 'kit_action/appbox_kit_action.dart';

/// Mixin that makes any object a AppBoxKitAction owner — viewmodels (via
/// [AppBoxKitViewModel]), facades, adapters, and services get the same ergonomic
/// API without ever writing `owner: this`.
///
/// ```dart
/// class NotesFacade with AppBoxKitActionOwner {
///   Future<void> save(Note note) => action('save', () => _repo.put(note))
///       .completeOnError('Save failed');
/// }
/// ```
///
/// Owners registered in get_it must call [disposeAppBoxKitActions] from their own
/// dispose; [AppBoxKitViewModel.dispose] already does.
mixin AppBoxKitActionOwner {
  /// Run an operation owned by this object. The [name] label combines with
  /// the owner's identity into the registry key (`RuntimeType#hash.name`), so
  /// state subjects, in-flight guards, and subscriptions are scoped to this
  /// instance and die with [disposeAppBoxKitActions].
  AppBoxKitActionBuilder<T> action<T>(
    String name,
    FutureOr<T> Function() operation,
  ) =>
      AppBoxKitAction.run<T>(operation, owner: this, name: name);

  /// Watch streams owned by this object — for VM/service-internal side
  /// effects, never view data (views bind streams directly).
  void watch(
    String name, {
    required List<Stream<dynamic>> streams,
    required void Function(dynamic value) callback,
    String? errorMessage,
    void Function(Object error)? onError,
  }) =>
      AppBoxKitAction.watch(
        owner: this,
        name: name,
        streams: streams,
        callback: callback,
        errorMessage: errorMessage,
        onError: onError,
      );

  /// Live busy/error state of one of this owner's ops, addressed by the same
  /// [name] the `action` chain used — views bind it with `AppBoxKitStreamBuilder`.
  ValueStream<AppBoxKitActionState> actionState$(String name) =>
      AppBoxKitAction.state$(owner: this, name: name);

  /// Dispose EVERYTHING this owner created — every op's subscriptions, state
  /// subjects, and tracked streams.
  void disposeAppBoxKitActions() => AppBoxKitAction.disposeOwner(this);
}
