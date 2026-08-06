import 'dart:async';

import 'package:rxdart/rxdart.dart' show ValueStream;

import 'kit_action/kit_action.dart';

/// Mixin that makes any object a KitAction owner — viewmodels (via
/// [KitViewModel]), facades, adapters, and services get the same ergonomic
/// API without ever writing `owner: this`.
///
/// ```dart
/// class NotesFacade with KitActionOwner {
///   Future<void> save(Note note) => action('save', () => _repo.put(note))
///       .completeOnError('Save failed');
/// }
/// ```
///
/// Owners registered in get_it must call [disposeKitActions] from their own
/// dispose; [KitViewModel.dispose] already does.
mixin KitActionOwner {
  /// Run an operation owned by this object. The [name] label combines with
  /// the owner's identity into the registry key (`RuntimeType#hash.name`), so
  /// state subjects, in-flight guards, and subscriptions are scoped to this
  /// instance and die with [disposeKitActions].
  KitActionBuilder<T> action<T>(
    String name,
    FutureOr<T> Function() operation,
  ) =>
      KitAction.run<T>(operation, owner: this, name: name);

  /// Watch streams owned by this object — for VM/service-internal side
  /// effects, never view data (views bind streams directly).
  void watch(
    String name, {
    required List<Stream<dynamic>> streams,
    required void Function(dynamic value) callback,
    String? errorMessage,
    void Function(Object error)? onError,
  }) =>
      KitAction.watch(
        owner: this,
        name: name,
        streams: streams,
        callback: callback,
        errorMessage: errorMessage,
        onError: onError,
      );

  /// Live busy/error state of one of this owner's ops, addressed by the same
  /// [name] the `action` chain used — views bind it with `KitStreamBuilder`.
  ValueStream<KitActionState> actionState$(String name) =>
      KitAction.state$(owner: this, name: name);

  /// Dispose EVERYTHING this owner created — every op's subscriptions, state
  /// subjects, and tracked streams.
  void disposeKitActions() => KitAction.disposeOwner(this);
}
