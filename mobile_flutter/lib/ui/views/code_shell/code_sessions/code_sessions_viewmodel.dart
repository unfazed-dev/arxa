// Code sessions viewmodel — the code_shell goes live: list the engine's
// code sessions from the local projection, refresh on model-ready,
// pull-to-refresh, and whenever the tunnel (re)announces connected; a pull
// that finds the link down re-kicks the dial (the approvals pattern).
import 'dart:async';

import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app.router.dart';
import 'package:arxa_studio_mobile/app/app_data.dart';

import '../../../../data/conversation/conversation.dart';
import '../../../../data/conversation/conversation_api_client.dart';
import '../../../../data/conversation/conversation_repository.dart';
import '../../../../services/transport_service.dart';

/// Why the last refresh failed — the view maps these to l10n copy.
enum CodeSessionsError { offline, remote }

/// The filter chips over the session list.
enum CodeSessionsFilter { all, blocked, inProgress, done }

class CodeSessionsViewModel extends BaseViewModel {
  CodeSessionsViewModel([
    ConversationRepository? repository,
    Future<void> Function()? dataReady,
  ]) : _repository = repository ?? locator<ConversationRepository>(),
       _dataReady = dataReady ?? (() => AppData.ready.future);

  final ConversationRepository _repository;

  /// The data boot runs in the BACKGROUND; every repository touch gates on
  /// it so a late boot never crashes a locator lookup.
  final Future<void> Function() _dataReady;

  List<CodeSession> get sessions => _sessions;
  List<CodeSession> _sessions = const [];

  CodeSessionsFilter get filter => _filter;
  CodeSessionsFilter _filter = CodeSessionsFilter.all;

  /// The list after the active filter (sorted newest-first by the repo).
  List<CodeSession> get filteredSessions {
    switch (_filter) {
      case CodeSessionsFilter.all:
        return _sessions;
      case CodeSessionsFilter.blocked:
        return [
          for (final session in _sessions)
            if (session.parkedReason != null) session,
        ];
      case CodeSessionsFilter.inProgress:
        return [
          for (final session in _sessions)
            if (session.parkedReason == null && !_isDone(session)) session,
        ];
      case CodeSessionsFilter.done:
        return [
          for (final session in _sessions)
            if (_isDone(session)) session,
        ];
    }
  }

  static bool _isDone(CodeSession session) {
    final state = session.state?.toLowerCase();
    return state == 'done' || state == 'completed' || state == 'complete';
  }

  /// The last refresh failure (loud, never a queue). Null after a
  /// successful refresh — the cached list still renders while set.
  CodeSessionsError? get loadError => _error;
  CodeSessionsError? _error;

  /// The last refresh found the link down with NOTHING stored to resume —
  /// the view offers the QR-scan route instead of a doomed dial.
  bool get needsPairing => _needsPairing;
  bool _needsPairing = false;

  StreamSubscription<ArxaConnectionStatus>? _statusSub;

  /// The engine's live rail (SSE): 'sessions' pings re-pull the list
  /// (debounced — a turn can fire several frames). A staleness guard
  /// re-pulls on a slow timer when the rail is quiet or the SSE carrier
  /// (the tunnel proxy) ever buffers — the view never goes blind.
  StreamSubscription<ConversationLiveEvent>? _liveSub;
  Timer? _liveRefreshTimer;
  Timer? _stalenessTimer;

  /// Lazy: unit tests construct the model without the app locator.
  RouterService get _router => locator<RouterService>();

  /// Auto-refresh: re-pull whenever the tunnel (re)announces connected.
  /// Subscribes once.
  void listenTransport() {
    if (_statusSub != null) return;
    _statusSub = _repository.transport.status.listen((s) {
      if (s.state == ArxaConnectionState.connected) refresh();
    });
  }

  /// Subscribe to the engine's live pings (once). Call together with
  /// [listenTransport] from the view's onModelReady. BOTH pings re-pull:
  /// 'sessions' (the projection moved) and 'session' (one conversation's
  /// surface moved — its updatedAt reorder AND the running flag on the row
  /// turn over exactly at those pings; the debounce folds the bursts).
  void listenLive() {
    if (_liveSub != null) return;
    _liveSub = _repository.liveEvents.listen((event) {
      if (event.type == 'sessions' || event.type == 'session') _queueRefresh();
    });
    _repository.startLive();
    _stalenessTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final last = _repository.lastLiveAt;
      final stale =
          last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 25);
      if (stale) _queueRefresh();
    });
  }

  /// True when the engine reported this session RUNNING A TURN on the last
  /// pull — the row's active (green) dot. Keyed by the dsh id (the flag's
  /// namespace), falling back to the row id.
  bool isRunning(CodeSession session) {
    final id = session.dshSessionId;
    return _repository.runningIds.contains(id ?? session.id);
  }

  /// Fold bursts of pings into one refresh.
  void _queueRefresh() {
    _liveRefreshTimer ??= Timer(const Duration(milliseconds: 400), () {
      _liveRefreshTimer = null;
      refresh();
    });
  }

  void setFilter(CodeSessionsFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  /// CONTRACT PIN: the transcript/send routes are keyed by the dsh
  /// session id (the "arxa-"-prefixed form), NOT the sidebar row id — the
  /// engine 404s (session-not-found) on the bare id. Fall back to the row
  /// id only when the engine shipped no dshSessionId.
  void openSession(CodeSession session) {
    final target = session.dshSessionId;
    if (target == null || target.isEmpty) {
      _router.navigateTo(CodeConversationViewRoute(sessionId: session.id));
      return;
    }
    _router.navigateTo(CodeConversationViewRoute(sessionId: target));
  }

  /// Straight to the QR scanner (nothing stored to resume — the desktop
  /// mints the ticket; the app never generates codes).
  void goToPairing() => _router.replaceWith(PairingScanViewRoute());

  /// The studio session is the paired home; this is the way back.
  void goToStudio() => _router.navigateTo(StudioSessionViewRoute());

  Future<void> refresh() async {
    await _dataReady();
    try {
      await _repository.refreshSessions();
      _error = null;
      _needsPairing = false;
    } on ConversationOfflineException {
      _error = CodeSessionsError.offline;
      await _kickRedial();
    } on Exception {
      _error = CodeSessionsError.remote;
    }
    _sessions = await _repository.listSessions();
    notifyListeners();
  }

  /// A failed pull means the link is down: re-kick the dial so a desktop
  /// that came back late gets found — the connected announcement then
  /// triggers the auto-refresh. Nothing stored: surface the scanner instead.
  Future<void> _kickRedial() async {
    final transport = _repository.transport;
    if (!await transport.hasStoredPairing()) {
      _needsPairing = true;
      notifyListeners();
      return;
    }
    await transport.resume();
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    unawaited(_liveSub?.cancel());
    _liveRefreshTimer?.cancel();
    _stalenessTimer?.cancel();
    super.dispose();
  }
}
