/// The CRDT capability seam for arxa_kit repositories.
///
/// cairn tables declared as counter / or-set tiers MERGE instead of
/// last-writer-wins (concurrent increments and set additions both survive).
/// Facade services feature-detect rather than hard-cast:
///
/// ```dart
/// final repo = repository<Post>();
/// if (repo is ArxaKitCrdtCapable) {
///   await repo.adjustCounter(post.id, 1); // a "like"
/// }
/// ```
///
/// The table must be declared in `ArxaKitCairnConfig.counterTables` /
/// `.orSetTables` AND match the server's `CAIRN_COUNTER_COLUMNS` /
/// `CAIRN_OR_SET_COLUMNS` (the kit's emitter generates that snippet) —
/// otherwise the verb throws, because undeclared writes clobber instead of
/// merge.
library;

abstract interface class ArxaKitCrdtCapable {
  /// Adjust the row's PN-Counter by [delta]: positive increments, negative
  /// decrements, zero writes nothing. [id] accepts a seed key or a canonical
  /// UUID interchangeably.
  Future<void> adjustCounter(String id, int delta);

  /// Add [element] to the row's add-wins OR-set (concurrent adds merge; a
  /// remove is a tombstone a later re-add revives).
  Future<void> orSetAdd(String id, String element);

  /// Remove [element] from the row's OR-set (add-wins tombstone).
  Future<void> orSetRemove(String id, String element);
}
