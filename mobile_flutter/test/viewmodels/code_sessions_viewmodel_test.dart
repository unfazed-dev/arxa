// CodeSessionsViewModel: loads the repository list, filters it
// (all / blocked = parkedReason!=null / in progress / done), surfaces
// offline/remote refresh failures inline, re-kicks the dial on a failed
// pull, re-pulls on a connected announcement, and opens the conversation
// route with the session id.
import 'dart:async';

import 'package:arxa_studio_mobile/data/conversation/conversation.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation_api_client.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation_repository.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_sessions/code_sessions_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements ConversationRepository {
  List<CodeSession> sessionRows = const [];
  Object? refreshError;
  Set<String> runningRows = const {};

  final _liveController = StreamController<ConversationLiveEvent>.broadcast();
  void emitLive(ConversationLiveEvent event) => _liveController.add(event);

  TransportService transportField = FakeTransportService();
  @override
  String? get lastMode => null;

  @override
  Future<List<EngineCommand>> commands(String sessionId) async => const [];

  @override
  Future<({String kind, String text})> runCommand(
          String sessionId, String line) async =>
      (kind: 'success', text: '');

  @override
  Future<String> exportTranscript(String sessionId, String savePath) async =>
      savePath;

  @override
  Stream<ConversationLiveEvent> get liveEvents => _liveController.stream;

  @override
  void startLive() {}

  @override
  DateTime? get lastLiveAt => null;
  @override
  Set<String> get runningIds => runningRows;

  @override
  Future<Map<String, dynamic>> models(String sessionId) async => const {};

  @override
  Future<void> selectModel(String sessionId, String provider, String model) async {}

  @override
  Future<void> setMode(String sessionId, String mode) async {}

  @override
  Future<Map<String, dynamic>> attachment(
          String sessionId, String attachmentId) async =>
      const {};

  @override
  Future<void> send(String sessionId, String text,
      {String mode = 'queue',
      List<({String mediaType, String data})> images = const []}) async {}

  @override
  TransportService get transport => transportField;

  @override
  Duration get healWait => const Duration(seconds: 20);

  @override
  Future<List<CodeSession>> listSessions() async {
    // Mirror the real repository contract: newest-first by updatedAt.
    final rows = [...sessionRows]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return rows;
  }

  @override
  Stream<List<CodeSession>> watchSessions() => const Stream.empty();

  @override
  Future<void> refreshSessions() async {
    final error = refreshError;
    if (error != null) throw error;
  }

  @override
  Future<List<ConversationMessage>> transcript(String sessionId) async =>
      const [];

  @override
  Stream<List<ConversationMessage>> watchTranscript(String sessionId) =>
      const Stream.empty();

  @override
  Future<void> refreshSession(String sessionId) async {}
}

/// A transport whose status the test pokes directly and whose resume
/// calls are counted — the reactive-refresh seams, no timers.
class _PokeTransport implements TransportService {
  final _controller = StreamController<ArxaConnectionStatus>.broadcast();

  ArxaConnectionStatus currentStatus =
      const ArxaConnectionStatus(ArxaConnectionState.notPaired);
  bool stored = true;
  int resumeCount = 0;

  void emit(ArxaConnectionStatus s) {
    currentStatus = s;
    _controller.add(s);
  }

  @override
  ArxaConnectionStatus get current => currentStatus;

  @override
  Stream<ArxaConnectionStatus> get status => _controller.stream;

  @override
  Future<bool> hasStoredPairing() async => stored;

  @override
  Future<void> beginPairing(String ticket) async {}

  @override
  Future<void> setPushToken(String platform, String token) async {}

  @override
  Future<void> unpair() async {}

  @override
  Future<void> resume() async => resumeCount += 1;

  @override
  Future<void> dispose() async => _controller.close();
}

CodeSession _session(String id,
        {String? parkedReason,
        String? state,
        int updatedAt = 0,
        String? dshSessionId}) =>
    CodeSession(
        id: id,
        title: id,
        state: state,
        parkedReason: parkedReason,
        updatedAt: updatedAt,
        dshSessionId: dshSessionId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CodeSession json round-trips the dshSessionId (the transcript key)', () {
    const dsh = 'arxa-s-mtgtrrx8-8mrlsd';
    final session = CodeSession.fromJson({
      'id': 's-mtgtrrx8-8mrlsd',
      'title': 'fix the bug',
      'state': 'running',
      'dshSessionId': dsh,
      'updatedAt': 5,
    });

    expect(session.dshSessionId, dsh);
    expect(session.toJson()['dshSessionId'], dsh,
        reason: 'the conversation routes key on this form, not the row id');
  });

  test('CodeSession running flag parses from the wire, never persists', () {
    final session = CodeSession.fromJson(
        {'id': 's-1', 'dshSessionId': 'arxa-s-1', 'running': true});
    final idle = CodeSession.fromJson({'id': 's-2'});

    expect(session.running, isTrue, reason: 'the live-turn flag rides fresh rows');
    expect(idle.running, isFalse);
    expect(session.toJson().containsKey('running'), isFalse,
        reason: 'transient — the cache keeps no running column');
  });

  test('starts with no sessions', () {
    expect(
        CodeSessionsViewModel(_FakeRepository(), () => Future.value())
            .sessions,
        isEmpty);
  });

  test('refresh loads the repository list', () async {
    final repo = _FakeRepository()
      ..sessionRows = [_session('s1', updatedAt: 2), _session('s2', updatedAt: 5)];
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());

    await viewModel.refresh();

    expect(viewModel.sessions.map((s) => s.id), ['s2', 's1'],
        reason: 'the repository sorts newest-first by updatedAt');
    expect(viewModel.loadError, isNull);
  });

  test('blocked filter keeps only sessions with a parkedReason', () async {
    final repo = _FakeRepository()
      ..sessionRows = [
        _session('free', state: 'running'),
        _session('parked', parkedReason: 'waiting-approval'),
      ];
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());
    await viewModel.refresh();

    viewModel.setFilter(CodeSessionsFilter.blocked);

    expect(viewModel.filteredSessions.single.id, 'parked');
  });

  test('in-progress filter excludes parked and done sessions', () async {
    final repo = _FakeRepository()
      ..sessionRows = [
        _session('free', state: 'running'),
        _session('parked', parkedReason: 'waiting-approval'),
        _session('done', state: 'done'),
      ];
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());
    await viewModel.refresh();

    viewModel.setFilter(CodeSessionsFilter.inProgress);

    expect(viewModel.filteredSessions.single.id, 'free');
  });

  test('done filter keeps only completed sessions', () async {
    final repo = _FakeRepository()
      ..sessionRows = [
        _session('free', state: 'running'),
        _session('done', state: 'completed'),
      ];
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());
    await viewModel.refresh();

    viewModel.setFilter(CodeSessionsFilter.done);

    expect(viewModel.filteredSessions.single.id, 'done');
  });

  test('offline refresh surfaces inline and keeps the cached list', () async {
    final repo = _FakeRepository()
      ..sessionRows = [_session('s1')]
      ..refreshError = ConversationOfflineException();
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());

    await viewModel.refresh();

    expect(viewModel.loadError, CodeSessionsError.offline);
    expect(viewModel.sessions.single.id, 's1');
  });

  test('offline refresh re-kicks the dial when paired', () async {
    final repo = _FakeRepository()
      ..refreshError = ConversationOfflineException();
    final transport = _PokeTransport()..stored = true;
    repo.transportField = transport;
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());

    await viewModel.refresh();

    expect(transport.resumeCount, 1,
        reason: 'a failed pull re-kicks the dial so a late desktop is found');
    expect(viewModel.loadError, CodeSessionsError.offline);
    expect(viewModel.needsPairing, isFalse);
  });

  test('offline with nothing stored surfaces the pairing affordance', () async {
    final repo = _FakeRepository()
      ..refreshError = ConversationOfflineException();
    final transport = _PokeTransport()..stored = false;
    repo.transportField = transport;
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());

    await viewModel.refresh();

    expect(viewModel.needsPairing, isTrue);
    expect(transport.resumeCount, 0,
        reason: 'resume is a no-op without a session — offer the scanner');
  });

  test('connected announcement re-pulls automatically', () async {
    final repo = _FakeRepository()..sessionRows = [_session('s1')];
    final transport = _PokeTransport();
    repo.transportField = transport;
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());

    viewModel.listenTransport();
    transport.emit(ArxaConnectionStatus(ArxaConnectionState.connected,
        studioUrl: Uri.parse('http://127.0.0.1:45890/')));
    await pumpEventQueue();

    expect(viewModel.sessions.single.id, 's1',
        reason: 'the tunnel coming up re-pulls the list with no user action');
  });

  test('a session ping re-pulls the list (reorder + running ride it)', () async {
    final repo = _FakeRepository()..sessionRows = [_session('s1', updatedAt: 9)];
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());
    viewModel.listenLive();
    addTearDown(viewModel.dispose);

    repo.emitLive(
        const ConversationLiveEvent(type: 'session', sessionId: 'arxa-s1'));
    // the 400ms live-refresh debounce must fire — poll, never a fixed sleep
    // (a fixed delay flakes when the suite runs under load)
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (viewModel.sessions.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    expect(viewModel.sessions.single.id, 's1',
        reason: 'per-session pings refresh the list too — the updatedAt '
            'reorder and the running flag turn over exactly at them');
  });

  test('isRunning keys on the dsh session id (the flag namespace)', () {
    final repo = _FakeRepository()
      ..runningRows = {'arxa-s-live'}
      ..sessionRows = [
        _session('s-idle'),
        _session('s-live', dshSessionId: 'arxa-s-live'),
      ];
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());

    expect(viewModel.isRunning(repo.sessionRows[0]), isFalse);
    expect(viewModel.isRunning(repo.sessionRows[1]), isTrue);
  });
}
