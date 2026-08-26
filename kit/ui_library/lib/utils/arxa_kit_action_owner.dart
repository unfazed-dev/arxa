import 'dart:async';

import 'package:rxdart/rxdart.dart' show ValueStream;

import 'kit_action/arxa_kit_action.dart';
import 'kit_action/arxa_kit_action_hub.dart';

/// Mixin that makes any object a ArxaKitAction owner — viewmodels (via
/// [ArxaKitViewModel]), facades, adapters, and services get the same ergonomic
/// API without ever writing `owner: this`.
///
/// ```dart
/// class NotesFacade with ArxaKitActionOwner {
///   Future<void> save(Note note) => hub
///       .define<Note, void>('save', (n) => _repo.put(n))
///       .send(note);
/// }
/// ```
///
/// Owners registered in get_it must call [disposeArxaKitActions] from their own
/// dispose; [ArxaKitViewModel.dispose] already does.
mixin ArxaKitActionOwner {
  ArxaKitActionHub? _hub;

  /// The owner's hot-send hub — the app-level KitAction API.
  /// Lazily created on first use (override [createHub] to set
  /// hub-level defaults) and disposed by [disposeArxaKitActions],
  /// which `ArxaKitViewModel.dispose` calls — no manual wiring.
  ArxaKitActionHub get abxActionHub => _hub ??= createHub();

  /// Factory for [abxActionHub] — override to configure hub-level defaults
  /// (`errorMessage`, `onSend`, `onError`) shared by every command.
  ArxaKitActionHub createHub() => ArxaKitActionHub(owner: this);

  /// Run an operation owned by this object. The [name] label combines with
  /// the owner's identity into the registry key (`RuntimeType#hash.name`), so
  /// state subjects, in-flight guards, and subscriptions are scoped to this
  /// instance and die with [disposeArxaKitActions].
  ///
  /// Low-level API — prefer [hub] commands in app code; `action` remains
  /// for the builder-only forms (`toStream`, `toCancellable`, …).
  ArxaKitActionBuilder<T> action<T>(
    String name,
    FutureOr<T> Function() operation,
  ) =>
      ArxaKitAction.run<T>(operation, owner: this, name: name);

  /// Listen to streams owned by this object — for VM/service-internal side
  /// effects, never view data (views bind streams directly).
  void listen(
    String name, {
    required List<Stream<dynamic>> to,
    required void Function(dynamic value) onData,
    String? errorMessage,
    void Function(Object error)? onError,
  }) =>
      ArxaKitAction.listen(
        owner: this,
        name: name,
        to: to,
        onData: onData,
        errorMessage: errorMessage,
        onError: onError,
      );

  /// Live busy/error state of one of this owner's ops, addressed by the same
  /// [name] the command/`action` chain used — views bind it with `ArxaKitStreamBuilder`.
  ValueStream<ArxaKitActionState> actionState$(String name) =>
      ArxaKitAction.state$(owner: this, name: name);

  /// Dispose EVERYTHING this owner created — the hub (command
  /// subscriptions, subjects, state subjects), every builder op's
  /// subscriptions, and tracked streams.
  void disposeArxaKitActions() {
    _hub?.dispose();
    ArxaKitAction.disposeOwner(this);
  }
}
