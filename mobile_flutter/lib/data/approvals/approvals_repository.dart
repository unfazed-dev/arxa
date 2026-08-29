// The approvals repository — facade over the kit cache + the tunnel client
// (grill D61/D66: the cairn-backed entity is the phone's local projection;
// the engine over the tunnel is the source).
//
// refresh() reconciles the cache to the engine's list (upsert present,
// delete stale). decide() POSTs and, on acceptance, deletes the cache row.
// Failures are LOUD (D62): offline/conflict exceptions propagate to the
// viewmodel for inline surfacing — never queued, never swallowed.

import 'package:arxa_kit_data/arxa_kit_data.dart';

import 'approval.dart';
import 'approvals_api_client.dart';

class ApprovalsRepository {
  ApprovalsRepository({required ArxaKitRepository<Approval> cache, required ApprovalsApiClient api})
      : _cache = cache,
        _api = api;

  final ArxaKitRepository<Approval> _cache;
  final ApprovalsApiClient _api;

  /// Cached approvals, oldest first (the projection — safe to read offline).
  Future<List<Approval>> list() async {
    final all = await _cache.getAll();
    all.sort((a, b) => a.raisedAt.compareTo(b.raisedAt));
    return all;
  }

  /// Live view of the cache for later reactive wiring.
  Stream<List<Approval>> watch() => _cache
      .watchAll()
      .map((rows) => rows..sort((a, b) => a.raisedAt.compareTo(b.raisedAt)));

  /// Pull the engine's list and reconcile the cache. Throws
  /// [ApprovalsOfflineException] when the tunnel is down (the cached list
  /// stays as-is for reading).
  Future<void> refresh() async {
    final remote = await _api.list();
    final remoteById = {for (final approval in remote) approval.id: approval};
    final cached = await _cache.getAll();
    for (final stale in cached) {
      if (!remoteById.containsKey(stale.id)) await _cache.delete(stale.id);
    }
    if (remote.isNotEmpty) await _cache.upsertMany(remote);
  }

  /// Answer a pending approval on the engine; on acceptance the cached row
  /// deletes. A 409 propagates as [ApprovalsConflictException] — refresh()
  /// after it to resync (someone answered first).
  Future<void> decide(String id, List<ApprovalAnswer> answers) async {
    await _api.decide(id, answers);
    await _cache.delete(id);
  }
}
