import 'dart:async';

import 'package:rxdart/rxdart.dart' show ValueStream;

import 'kit_action/appbox_kit_action.dart';
import 'kit_action/appbox_kit_action_hub.dart';

/// Mixin that makes any object a AppBoxKitAction owner — viewmodels (via
/// [AppBoxKitViewModel]), facades, adapters, and services get the same ergonomic
/// API without ever writing `owner: this`.
///
/// ```dart
/// class NotesFacade with AppBoxKitActionOwner {
///   Future<void> save(Note note) => hub
///       .define<Note, void>('save', (n) => _repo.put(n))
///       .send(note);
/// }
/// ```
///
/// Owners registered in get_it must call [disposeAppBoxKitActions] from their own
/// dispose; [AppBoxKitViewModel.dispose] already does.
mixin AppBoxKitActionOwner {
  AppBoxKitActionHub? _hub;

  /// The owner's hot-send hub — the app-level KitAction API.
  /// Lazily created on first use (override [createHub] to set
  /// hub-level defaults) and disposed by [disposeAppBoxKitActions],
  /// which `AppBoxKitViewModel.dispose` calls — no manual wiring.
  AppBoxKitActionHub get abxActionHub => _hub ??= createHub();

  /// Factory for [abxActionHub] — override to configure hub-level defaults
  /// (`errorMessage`, `onSend`, `onError`) shared by every command.
  AppBoxKitActionHub createHub() =>
      AppBoxKitActionHub(owner: this);

  /// Run an operation owned by this object. The [name] label combines with
  /// the owner's identity into the registry key (`RuntimeType#hash.name`), so
  /// state subjects, in-flight guards, and subscriptions are scoped to this
  /// instance and die with [disposeAppBoxKitActions].
  ///
  /// Low-level API — prefer [hub] commands in app code; `action` remains
  /// for the builder-only forms (`toStream`, `toCancellable`, …).
  AppBoxKitActionBuilder<T> action<T>(
    String name,
    FutureOr<T> Function() operation,
  ) =>
      AppBoxKitAction.run<T>(operation, owner: this, name: name);

  /// Listen to streams owned by this object — for VM/service-internal side
  /// effects, never view data (views bind streams directly).
  void listen(
    String name, {
    required List<Stream<dynamic>> to,
    required void Function(dynamic value) onData,
    String? errorMessage,
    void Function(Object error)? onError,
  }) =>
      AppBoxKitAction.listen(
        owner: this,
        name: name,
        to: to,
        onData: onData,
        errorMessage: errorMessage,
        onError: onError,
      );

  /// Live busy/error state of one of this owner's ops, addressed by the same
  /// [name] the command/`action` chain used — views bind it with `AppBoxKitStreamBuilder`.
  ValueStream<AppBoxKitActionState> actionState$(String name) =>
      AppBoxKitAction.state$(owner: this, name: name);

  /// Dispose EVERYTHING this owner created — the hub (command
  /// subscriptions, subjects, state subjects), every builder op's
  /// subscriptions, and tracked streams.
  void disposeAppBoxKitActions() {
    _hub?.dispose();
    AppBoxKitAction.disposeOwner(this);
  }
}
