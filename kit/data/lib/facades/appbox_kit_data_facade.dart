import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import '../auth/appbox_kit_auth_service.dart';
import '../repositories/appbox_kit_repository.dart';

/// Base class for the host's facade services — the only layer ViewModels
/// talk to.
///
/// A facade composes repositories into UI-facing state: derived streams via
/// rxdart (`Rx.combineLatest`, `.map`, `.debounceTime`), and UI-state
/// subjects registered through [registerSubject] so [dispose] closes them.
/// Aggregations belong here, never in repositories (swap rule 2).
///
/// Mutations go through [mutate], which routes into `AppBoxKitAction` so data
/// writes inherit the kit's loading/error/snackbar/retry automation. As a
/// [AppBoxKitActionOwner] the facade can also run ad-hoc ops via `action(name, …)`
/// and everything it creates dies with [dispose].
abstract class AppBoxKitDataFacade with AppBoxKitActionOwner {
  final List<Subject<dynamic>> _subjects$ = [];

  /// The active backend's repository for [T], as registered by
  /// `AppBoxKitData.initialize`.
  AppBoxKitRepository<T> repository<T>() => appBoxKitLocator<AppBoxKitRepository<T>>();

  /// The active backend's auth seam. Only available when
  /// `AppBoxKitDataConfig.auth` was provided.
  AppBoxKitAuthService get auth => appBoxKitLocator<AppBoxKitAuthService>();

  /// Tracks a UI-state subject for disposal. Subjects live only in facades —
  /// never in repositories.
  S registerSubject<S extends Subject<dynamic>>(S subject) {
    _subjects$.add(subject);
    return subject;
  }

  /// Starts a AppBoxKitAction chain for a data mutation, owned by this facade —
  /// the registry key is derived (`RuntimeType.name.entity`), never
  /// hand-written.
  ///
  /// Notification policy as parameters (the common case is a one-liner):
  /// - [error]: error snackbar message — set it on EVERY mutation (errors
  ///   always surface).
  /// - [success]: success snackbar message — only for destructive /
  ///   confirm-worthy ops.
  ///
  /// The builder is still returned, so advanced chains keep chaining
  /// (`.withRetry(...)`, `.withDebounce(...)`, `.onSuccess(...)`) and run when
  /// awaited.
  ///
  /// ```dart
  /// Future<ShowcaseNoteModel> togglePin(ShowcaseNoteModel note) => mutate(
  ///       () => _repo.upsertNote(note.copyWith(isPinned: !note.isPinned)),
  ///       name: 'pin',
  ///       entity: note.id,
  ///       error: 'Could not update the note',
  ///     );
  /// ```
  AppBoxKitActionBuilder<T> mutate<T>(
    FutureOr<T> Function() operation, {
    String? name,
    String? entity,
    String? error,
    String? success,
  }) {
    final label =
        [if (name != null) name, if (entity != null) entity].join('.');
    var builder = AppBoxKitAction.run<T>(
      operation,
      owner: this,
      name: label.isEmpty ? null : label,
    );
    if (error != null) builder = builder.withErrorSnackbar(error);
    if (success != null) builder = builder.withSuccessSnackbar(success);
    return builder;
  }

  Future<void> dispose() async {
    disposeAppBoxKitActions();
    for (final subject in _subjects$) {
      // Fire-and-forget: awaiting close() deadlocks a testWidgets FakeAsync
      // zone (rxdart's close waits for in-flight dispatch that never drains
      // under the fake clock). The subject is closed regardless.
      // ignore: unawaited_futures
      subject.close();
    }
    _subjects$.clear();
  }
}
