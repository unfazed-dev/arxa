// The approvals repository — facade over the kit cache + the tunnel client
// (grill D61/D66: the cairn-backed entity is the phone's local projection;
// the engine over the tunnel is the source).
//
// refresh() reconciles the cache to the engine's list (upsert present,
// delete stale). decide() POSTs and, on acceptance, deletes the cache row.
// Failures are LOUD (D62): offline/conflict exceptions propagate to the
// viewmodel for inline surfacing — never queued, never swallowed. One
// bounded exception: a transport-level refresh failure while PAIRED heals
// once (resume + bounded wait + a single retry) before surfacing — the
// zombie link (memo 3b): after a mid-session network handoff the session
// can look connected while every tunnel request fails fast, and nothing
// else re-establishes it while the app stays foreground.

import 'dart:async';

import 'package:arxa_kit_data/arxa_kit_data.dart';

import '../../services/transport_service.dart';
import 'approval.dart';
import 'approvals_api_client.dart';

class ApprovalsRepository {
  ApprovalsRepository({
    required ArxaKitRepository<Approval> cache,
    required ApprovalsApiClient api,
    this.healWait = const Duration(seconds: 20),
  })  : _cache = cache,
        _api = api;

  final ArxaKitRepository<Approval> _cache;
  final ApprovalsApiClient _api;

  /// How long a heal waits for the transport to re-establish before giving
  /// up and rethrowing the original failure. Covers the kit's reconnect
  /// dial budget (5 attempts x 3s backoff) with margin.
  final Duration healWait;

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
  /// [ApprovalsOfflineException] when the tunnel is unusable (after one
  /// heal attempt while paired; the cached list stays as-is for reading).
  Future<void> refresh() async {
    List<Approval> remote;
    try {
      remote = await _api.list();
    } on ApprovalsOfflineException catch (failure) {
      remote = await _healedList(failure);
    }
    final remoteById = {for (final approval in remote) approval.id: approval};
    final cached = await _cache.getAll();
    for (final stale in cached) {
      if (!remoteById.containsKey(stale.id)) await _cache.delete(stale.id);
    }
    if (remote.isNotEmpty) await _cache.upsertMany(remote);
  }

  /// Zombie-link heal (memo 3b): the session can look connected while the
  /// loopback proxy fails fast on every request. Resume the transport, wait
  /// bounded for it to re-announce connected, and retry the pull exactly
  /// once. Rethrows the original [failure] when unpaired (nothing to heal)
  /// or when the tunnel does not return inside [healWait]; a retry that
  /// still fails propagates its own error.
  Future<List<Approval>> _healedList(ApprovalsOfflineException failure) async {
    final transport = _api.transport;
    if (transport.current.studioUrl == null) throw failure;
    // Subscribe BEFORE resuming so a fast re-announce is not missed. A
    // stream that closes without reconnecting (disposed transport) simply
    // never completes the wait — the timeout then rethrows the original.
    final reconnected = Completer<void>();
    final sub = transport.status.listen((s) {
      if (s.state == ArxaConnectionState.connected && !reconnected.isCompleted) {
        reconnected.complete();
      }
    });
    try {
      await transport.resume();
      await reconnected.future.timeout(healWait);
    } on TimeoutException {
      throw failure;
    } finally {
      await sub.cancel();
    }
    return _api.list();
  }

  /// Answer a pending approval on the engine; on acceptance the cached row
  /// deletes. A 409 propagates as [ApprovalsConflictException] — refresh()
  /// after it to resync (someone answered first).
  Future<void> decide(String id, List<ApprovalAnswer> answers) async {
    await _api.decide(id, answers);
    await _cache.delete(id);
  }
}
