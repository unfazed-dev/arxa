// The conversation repository — facade over the kit caches + the tunnel
// client, cloned from the approvals repository: the cairn-backed entities
// are the phone's local projection; the engine over the tunnel is the
// source. refreshSessions()/refreshSession() reconcile the caches
// (upsert present, delete stale); send() POSTs then re-pulls the
// transcript. Failures are LOUD: offline/conflict exceptions propagate to
// the viewmodel for inline surfacing — never queued, never swallowed. One
// bounded exception: a transport-level refresh failure while PAIRED heals
// once (resume + bounded wait + a single retry) before surfacing — the
// zombie link (memo 3b), copied verbatim from the approvals slice.

import 'dart:async';

import 'package:arxa_kit_data/arxa_kit_data.dart';

import '../../services/transport_service.dart';
import 'conversation.dart';
import 'conversation_api_client.dart';

export 'conversation.dart' show ModelOption;

class ConversationRepository {
  ConversationRepository({
    required ArxaKitRepository<CodeSession> sessionCache,
    required ArxaKitRepository<ConversationMessage> messageCache,
    required ConversationApiClient api,
    this.healWait = const Duration(seconds: 20),
  })  : _sessionCache = sessionCache,
        _messageCache = messageCache,
        _api = api;

  final ArxaKitRepository<CodeSession> _sessionCache;
  final ArxaKitRepository<ConversationMessage> _messageCache;
  final ConversationApiClient _api;

  /// How long a heal waits for the transport to re-establish before giving
  /// up and rethrowing the original failure. Covers the kit's reconnect
  /// dial budget (5 attempts x 3s backoff) with margin.
  final Duration healWait;

  /// Cached sessions, NEWEST first by updatedAt (the projection — safe to
  /// read offline; the live conversation is what the owner needs first).
  Future<List<CodeSession>> listSessions() async {
    final all = await _sessionCache.getAll();
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return all;
  }

  /// The sessions the engine reported RUNNING A TURN on the last
  /// [refreshSessions] pull (dsh ids) — the list's active indicator. The
  /// flag is transient (not a cache column): it lives only on the fresh
  /// rows, so this set is the query surface.
  Set<String> get runningIds => _runningIds;
  Set<String> _runningIds = const {};

  /// One session's cached transcript, ascending by seq. CONTRACT PIN:
  /// [sessionId] must be the dshSessionId ("arxa-"-prefixed) form — that is
  /// what the engine echoes as each message's sessionId and what the
  /// message cache is keyed by.
  /// The session's effective sandbox mode from the last transcript pull
  /// (null when never pulled). Read AFTER [transcript]/[refreshSession].
  String? get lastMode => _lastMode;
  String? _lastMode;

  /// The session's model directory (advisory; fetched on menu open).
  Future<Map<String, dynamic>> models(String sessionId) =>
      _api.models(sessionId);

  /// Select the model the session's next step uses.
  Future<void> selectModel(String sessionId, String provider, String model) =>
      _api.selectModel(sessionId, provider, model);

  /// Switch the session's sandbox mode.
  Future<void> setMode(String sessionId, String mode) =>
      _api.setMode(sessionId, mode);

  /// The engine's human-command palette (the studio `+` list).
  Future<List<EngineCommand>> commands(String sessionId) =>
      _api.commands(sessionId);

  /// Execute one slash-command line; the command's own kind/text comes
  /// back (the engine registry answers — the line never reaches the model).
  Future<({String kind, String text})> runCommand(
          String sessionId, String line) =>
      _api.runCommand(sessionId, line);

  /// Download the transcript markdown to [savePath]; returns the path.
  Future<String> exportTranscript(String sessionId, String savePath) =>
      _api.exportTranscript(sessionId, savePath);

  /// The engine's live pings (SSE over the tunnel) + the explicit
  /// start/health surface for screens that own a staleness guard.
  Stream<ConversationLiveEvent> get liveEvents => _api.events();
  void startLive() => _api.startLive();
  DateTime? get lastLiveAt => _api.lastLiveAt;

  Future<List<ConversationMessage>> transcript(String sessionId) async {
    final (mode, messages) = await _api.messages(sessionId);
    _lastMode = mode;
    return messages;
  }

  /// Live views of the caches for reactive wiring (same sorts as above).
  Stream<List<CodeSession>> watchSessions() => _sessionCache
      .watchAll()
      .map((rows) => rows..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));

  Stream<List<ConversationMessage>> watchTranscript(String sessionId) =>
      _messageCache.watchAll().map((rows) {
        final mine = [
          for (final message in rows)
            if (message.sessionId == sessionId) message,
        ];
        // Ascending by seq; Dart's sort is NOT stable and the fold now
        // emits several rows per seq — index breaks the ties.
        final order = List<int>.generate(mine.length, (i) => i);
        order.sort((a, b) {
          final bySeq = mine[a].seq.compareTo(mine[b].seq);
          return bySeq != 0 ? bySeq : a.compareTo(b);
        });
        return [for (final i in order) mine[i]];
      });

  /// Pull the engine's session list and reconcile the cache. Throws
  /// [ConversationOfflineException] when the tunnel is unusable (after one
  /// heal attempt while paired; the cached list stays as-is for reading).
  Future<void> refreshSessions() async {
    final remote = await _healed(() => _api.listSessions());
    _runningIds = {
      for (final session in remote)
        if (session.running) session.dshSessionId ?? session.id,
    };
    final remoteById = {for (final session in remote) session.id: session};
    final cached = await _sessionCache.getAll();
    for (final stale in cached) {
      if (!remoteById.containsKey(stale.id)) await _sessionCache.delete(stale.id);
    }
    if (remote.isNotEmpty) await _sessionCache.upsertMany(remote);
  }

  /// Pull one session's transcript and reconcile the message cache for it.
  /// [sessionId] is the dshSessionId form (the routes' key).
  Future<void> refreshSession(String sessionId) async {
    final (mode, remote) = await _healed(() => _api.messages(sessionId));
    _lastMode = mode;
    final remoteIds = {for (final message in remote) message.id};
    final cached = await _messageCache.getAll();
    for (final stale in cached) {
      if (stale.sessionId == sessionId && !remoteIds.contains(stale.id)) {
        await _messageCache.delete(stale.id);
      }
    }
    if (remote.isNotEmpty) await _messageCache.upsertMany(remote);
  }

  /// The transport seam for reactive screens (auto-refresh on the
  /// connected announcement, redial kicks on a failed pull).
  TransportService get transport => _api.transport;

  /// One tunnel pull with the zombie-link heal (memo 3b): a transport-level
  /// failure while PAIRED resumes the transport, waits bounded for it to
  /// re-announce connected, and retries exactly once. Rethrows the original
  /// failure when unpaired (nothing to heal) or when the tunnel does not
  /// return inside [healWait]; a retry that still fails propagates its own
  /// error.
  Future<T> _healed<T>(Future<T> Function() pull) async {
    try {
      return await pull();
    } on ConversationOfflineException {
      final transport = _api.transport;
      if (transport.current.studioUrl != null && await _resumeAndWait()) {
        return pull();
      }
      rethrow;
    }
  }

  /// Resume the transport and wait bounded for it to re-announce connected.
  /// Subscribes BEFORE resuming so a fast re-announce is not missed. A
  /// stream that closes without reconnecting (disposed transport) simply
  /// never completes the wait — the timeout reports false.
  Future<bool> _resumeAndWait() async {
    final transport = _api.transport;
    final reconnected = Completer<void>();
    final sub = transport.status.listen((s) {
      if (s.state == ArxaConnectionState.connected && !reconnected.isCompleted) {
        reconnected.complete();
      }
    });
    try {
      await transport.resume();
      await reconnected.future.timeout(healWait);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      await sub.cancel();
    }
  }

  /// Send a prompt into a session (queued by default), then re-pull the
  /// transcript so the user bubble lands locally. A 409 propagates as
  /// [ConversationConflictException] — the session has no live agent.
  Future<void> send(String sessionId, String text,
      {String mode = 'queue',
      List<({String mediaType, String data})> images = const []}) async {
    await _api.send(sessionId, text, mode: mode, images: images);
    await refreshSession(sessionId);
  }

  /// One stored image attachment ({ attachment, data: base64 }) — the raw
  /// engine answer; the UI decodes. Not cached: thumbnails are pull-per-view.
  Future<Map<String, dynamic>> attachment(
          String sessionId, String attachmentId) =>
      _healed(() => _api.attachment(sessionId, attachmentId));
}
