import 'dart:async';

import 'package:rxdart/rxdart.dart' show ValueStream;

import 'kit_action/appbox_kit_action.dart';
import 'kit_action/appbox_kit_action_pipeline.dart';

/// Mixin that makes any object a AppBoxKitAction owner — viewmodels (via
/// [AppBoxKitViewModel]), facades, adapters, and services get the same ergonomic
/// API without ever writing `owner: this`.
///
/// ```dart
/// class NotesFacade with AppBoxKitActionOwner {
///   Future<void> save(Note note) => pipeline
///       .pipe<Note, void>('save', (n) => _repo.put(n))
///       .dispatch(note);
/// }
/// ```
///
/// Owners registered in get_it must call [disposeAppBoxKitActions] from their own
/// dispose; [AppBoxKitViewModel.dispose] already does.
mixin AppBoxKitActionOwner {
  AppBoxKitActionPipeline? _pipeline;

  /// The owner's hot-dispatch pipeline — the app-level KitAction API.
  /// Lazily created on first use (override [createPipeline] to set
  /// pipeline-level defaults) and disposed by [disposeAppBoxKitActions],
  /// which `AppBoxKitViewModel.dispose` calls — no manual wiring.
  AppBoxKitActionPipeline get pipeline => _pipeline ??= createPipeline();

  /// Factory for [pipeline] — override to configure pipeline-level defaults
  /// (`errorMessage`, `onDispatch`, `onError`) shared by every pipe.
  AppBoxKitActionPipeline createPipeline() =>
      AppBoxKitActionPipeline(owner: this);

  /// Run an operation owned by this object. The [name] label combines with
  /// the owner's identity into the registry key (`RuntimeType#hash.name`), so
  /// state subjects, in-flight guards, and subscriptions are scoped to this
  /// instance and die with [disposeAppBoxKitActions].
  ///
  /// Low-level API — prefer [pipeline] pipes in app code; `action` remains
  /// for the builder-only forms (`toStream`, `toCancellable`, …).
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
  /// [name] the pipe/`action` chain used — views bind it with `AppBoxKitStreamBuilder`.
  ValueStream<AppBoxKitActionState> actionState$(String name) =>
      AppBoxKitAction.state$(owner: this, name: name);

  /// Dispose EVERYTHING this owner created — the pipeline (pipe
  /// subscriptions, subjects, state subjects), every builder op's
  /// subscriptions, and tracked streams.
  void disposeAppBoxKitActions() {
    _pipeline?.dispose();
    AppBoxKitAction.disposeOwner(this);
  }
}
