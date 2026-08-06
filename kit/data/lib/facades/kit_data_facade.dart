import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:ui_library/ui_library.dart';
// KitActionBuilder is not re-exported by the appbox_kit barrel.
import 'package:ui_library/utils/kit_action/kit_action_builder.dart';

import '../auth/kit_auth_service.dart';
import '../repositories/kit_repository.dart';

/// Base class for the host's facade services — the only layer ViewModels
/// talk to.
///
/// A facade composes repositories into UI-facing state: derived streams via
/// rxdart (`Rx.combineLatest`, `.map`, `.debounceTime`), and UI-state
/// subjects registered through [registerSubject] so [dispose] closes them.
/// Aggregations belong here, never in repositories (swap rule 2).
///
/// Mutations go through [mutate], which routes into `KitAction` so data
/// writes inherit the kit's loading/error/snackbar/retry automation.
abstract class KitDataFacade {
  final List<Subject<dynamic>> _subjects$ = [];

  /// The active backend's repository for [T], as registered by
  /// `KitData.initialize`.
  KitRepository<T> repository<T>() => locator<KitRepository<T>>();

  /// The active backend's auth seam. Only available when
  /// `KitDataConfig.auth` was provided.
  KitAuthService get auth => locator<KitAuthService>();

  /// Tracks a UI-state subject for disposal. Subjects live only in facades —
  /// never in repositories.
  S registerSubject<S extends Subject<dynamic>>(S subject) {
    _subjects$.add(subject);
    return subject;
  }

  /// Starts a KitAction chain for a data mutation, owned by this facade —
  /// the registry key is derived (`RuntimeType.op.entity`), never hand-written.
  ///
  /// Notification policy as parameters (the common case is a one-liner):
  /// - [error]: error snackbar message — set it on EVERY mutation (errors
  ///   always surface).
  /// - [success]: success snackbar message — only for destructive /
  ///   confirm-worthy ops.
  ///
  /// The builder is still returned, so advanced chains keep chaining
  /// (`.withRetry(...)`, `.withDebounce(...)`, `.onSuccess(...)`) and finish
  /// with `.execute()`.
  ///
  /// ```dart
  /// Future<ShowcaseNoteModel> togglePin(ShowcaseNoteModel note) => mutate(
  ///       operation: () => _repo.upsertNote(note.copyWith(isPinned: !note.isPinned)),
  ///       op: 'pin',
  ///       entity: note.id,
  ///       error: 'Could not update the note',
  ///     ).execute();
  /// ```
  KitActionBuilder<T> mutate<T>({
    required FutureOr<T> Function() operation,
    String? op,
    String? entity,
    String? error,
    String? success,
  }) {
    final label = [if (op != null) op, if (entity != null) entity].join('.');
    var builder = KitAction.run<T>(
      operation: operation,
      owner: this,
      op: label.isEmpty ? null : label,
    );
    if (error != null) builder = builder.withErrorSnackbar(error);
    if (success != null) builder = builder.withSuccessSnackbar(success);
    return builder;
  }

  Future<void> dispose() async {
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
