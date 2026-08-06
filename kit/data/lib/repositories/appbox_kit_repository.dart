import 'dart:convert';

import '../query/appbox_kit_query.dart';

/// The typed, single-table gateway to the active backend — the swap seam.
///
/// Contract (see docs/plans/appbox-kit-data-layer.md, "swap rules"):
/// - Implementations are stream-backed from their source; they never buffer
///   rows in their own subjects (the seed store's subjects ARE the source).
/// - Every method is single-table and [AppBoxKitQuery]-satisfiable. No joins.
/// - Write methods canonicalize the entity's `id` (and reference columns)
///   through AppBoxKitIdService before touching storage, so any key the caller
///   throws at the layer lands as the same UUID on every backend.
abstract interface class AppBoxKitRepository<T> {
  Future<T?> getById(String id);

  Future<List<T>> getAll([AppBoxKitQuery query = const AppBoxKitQuery()]);

  /// Emits the current row immediately, then on every change. `null` when the
  /// row does not exist (swap rule 3: singletons are `Stream<T?>`).
  Stream<T?> watchById(String id);

  /// Emits the current result set immediately, then on every change.
  Stream<List<T>> watchAll([AppBoxKitQuery query = const AppBoxKitQuery()]);

  /// Insert-or-update by canonical id. Returns the entity as stored (with
  /// canonicalized ids).
  Future<T> upsert(T entity);

  Future<List<T>> upsertMany(List<T> entities);

  /// Partial update: writes ONLY the columns that differ between [original]
  /// and [patched] (compared as wire-shape JSON — see [appBoxKitJsonPatch]),
  /// leaving every other stored column untouched, so two surfaces patching
  /// different columns of the same row never clobber each other. The row
  /// must exist — backends throw their natural not-found error. A no-op
  /// diff writes nothing and returns [patched]. Returns the entity as
  /// stored after the patch.
  Future<T> patch(T original, T patched);

  Future<void> delete(String id);
}

/// The wire-shape diff behind every [AppBoxKitRepository.patch]: the entries
/// of [patched] whose JSON encoding differs from [original]'s. Values are
/// codec output, so `jsonEncode` equality is exact — including nested
/// list/map columns and explicit nulls (a cleared column diffs, an unchanged
/// null does not).
Map<String, dynamic> appBoxKitJsonPatch(
  Map<String, dynamic> original,
  Map<String, dynamic> patched,
) {
  final diff = <String, dynamic>{};
  for (final entry in patched.entries) {
    if (jsonEncode(original[entry.key]) != jsonEncode(entry.value)) {
      diff[entry.key] = entry.value;
    }
  }
  return diff;
}
