// CodeConversationViewModel: loads one session's transcript (ascending by
// seq), threads that session's pending approvals inline, sends through the
// repository (never throwing; the composer clears on every outcome), and
// re-pulls on a connected announcement.
import 'dart:async';

import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation_api_client.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation_repository.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_conversation/code_conversation_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConversationRepository implements ConversationRepository {
  Map<String, List<ConversationMessage>> transcripts = const {};
  Object? refreshError;
  (String, String)? lastSent;

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
  Stream<ConversationLiveEvent> get liveEvents => const Stream.empty();

  @override
  void startLive() {}

  @override
  DateTime? get lastLiveAt => null;
  @override
  Set<String> get runningIds => const {};

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
      List<({String mediaType, String data})> images = const []}) async {
    lastSent = (sessionId, text);
    lastImages = images;
  }

  List<({String mediaType, String data})> lastImages = const [];


  @override
  TransportService get transport => transportField;

  @override
  Duration get healWait => const Duration(seconds: 20);

  @override
  Future<List<CodeSession>> listSessions() async => const [];

  @override
  Stream<List<CodeSession>> watchSessions() => const Stream.empty();

  @override
  Future<List<ConversationMessage>> transcript(String sessionId) async {
    // Mirror the real repository contract: ascending by seq.
    final rows = [...(transcripts[sessionId] ?? const <ConversationMessage>[])]
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return rows;
  }

  @override
  Stream<List<ConversationMessage>> watchTranscript(String sessionId) =>
      const Stream.empty();

  @override
  Future<void> refreshSessions() async {}

  @override
  Future<void> refreshSession(String sessionId) async {
    final error = refreshError;
    if (error != null) throw error;
  }
}

class _FakeApprovalsRepository implements ApprovalsRepository {
  List<Approval> rows = const [];
  (String, List<ApprovalAnswer>)? lastDecided;

  TransportService transportField = FakeTransportService();

  @override
  TransportService get transport => transportField;

  @override
  Duration get healWait => const Duration(seconds: 20);

  @override
  Future<List<Approval>> list() async => rows;

  @override
  Stream<List<Approval>> watch() => const Stream.empty();

  @override
  Future<void> refresh() async {}

  @override
  Future<void> decide(String id, List<ApprovalAnswer> answers) async {
    lastDecided = (id, answers);
    rows = [for (final a in rows) if (a.id != id) a];
  }
}

/// A transport whose status the test pokes directly — the reactive
/// refresh seam, no timers.
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

const _approval = Approval(
  id: 'a1',
  sessionId: 's1',
  kind: 'approval',
  summary: 'Approve?',
  questions: [
    ApprovalQuestion(id: 'q1', question: 'Approve?'),
  ],
  raisedAt: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ConversationMessage parses the expandable kinds and tool fields', () {
    final tool = ConversationMessage.fromJson({
      'id': 'arxa-s-1:3:1',
      'seq': 3,
      'sessionId': 'arxa-s-1',
      'role': 'assistant',
      'kind': 'tool',
      'name': 'ctx_batch_execute',
      'input': '{ "commands": [] }',
      'text': 'Executed 4 commands.',
      'error': true,
      'at': 9,
    });
    expect(tool.isTool, isTrue);
    expect(tool.toolLabel, 'Ctx Batch Execute',
        reason: 'snake_case tool names humanize for the row label');
    expect(tool.toolInput, '{ "commands": [] }');
    expect(tool.toolError, isTrue);

    final thinking = ConversationMessage.fromJson({
      'seq': 2,
      'sessionId': 'arxa-s-1',
      'role': 'assistant',
      'kind': 'thinking',
      'text': 'Let me check.',
    });
    expect(thinking.isThinking, isTrue);
    expect(thinking.isTool, isFalse);
    expect(thinking.toolLabel, 'Tool', reason: 'no name — neutral fallback');

    // A legacy/plain row (no kind on the wire) is just a bubble.
    final plain = ConversationMessage.fromJson({
      'seq': 1,
      'sessionId': 'arxa-s-1',
      'role': 'user',
      'text': 'go',
    });
    expect(plain.kind, 'text');
    expect(plain.isTool, isFalse);
    // Transients never persist (no schema columns carry them).
    expect(tool.toJson().containsKey('kind'), isFalse);
    expect(tool.toJson().containsKey('name'), isFalse);
  });

  test('starts with an empty transcript', () {
    final viewModel = CodeConversationViewModel(
        's1', _FakeConversationRepository(), _FakeApprovalsRepository(),
        () => Future.value());
    expect(viewModel.messages, isEmpty);
    expect(viewModel.pendingApprovals, isEmpty);
  });

  test('refresh loads the session transcript ascending by seq', () async {
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:2', seq: 2, sessionId: 's1', role: 'assistant', text: 'b'),
          const ConversationMessage(
              id: 's1:1', seq: 1, sessionId: 's1', role: 'user', text: 'a'),
        ],
      };
    final approvals = _FakeApprovalsRepository();
    final viewModel = CodeConversationViewModel('s1', repo, approvals,
        () => Future.value());

    await viewModel.refresh();

    expect(viewModel.messages.map((m) => m.seq), [1, 2]);
    expect(viewModel.loadError, isNull);
  });

  test('only this session pending approvals thread inline', () async {
    final repo = _FakeConversationRepository();
    final approvals = _FakeApprovalsRepository()
      ..rows = [
        const Approval(
            id: 'mine',
            sessionId: 's1',
            kind: 'approval',
            summary: 'mine',
            questions: [],
            raisedAt: 1),
        const Approval(
            id: 'other',
            sessionId: 's2',
            kind: 'approval',
            summary: 'other',
            questions: [],
            raisedAt: 2),
      ];
    final viewModel = CodeConversationViewModel('s1', repo, approvals,
        () => Future.value());

    await viewModel.refresh();

    expect(viewModel.pendingApprovals.single.id, 'mine');
  });

  test('send posts to the session and the transcript refreshes', () async {
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:1', seq: 1, sessionId: 's1', role: 'user', text: 'hi'),
        ],
      };
    final viewModel = CodeConversationViewModel(
        's1', repo, _FakeApprovalsRepository(), () => Future.value());

    final accepted = await viewModel.send('  hi  ');

    expect(accepted, isTrue);
    expect(repo.lastSent, ('s1', 'hi'),
        reason: 'the composer trims before posting');
    expect(viewModel.messages.single.text, 'hi');
  });

  test('send with blank text is a no-op', () async {
    final repo = _FakeConversationRepository();
    final viewModel = CodeConversationViewModel(
        's1', repo, _FakeApprovalsRepository(), () => Future.value());

    final accepted = await viewModel.send('   ');

    expect(accepted, isFalse);
    expect(repo.lastSent, isNull);
  });

  test('offline send surfaces inline and never throws', () async {
    final repo = _FakeConversationRepository()
      ..refreshError = ConversationOfflineException();
    // send() itself throws offline when the tunnel is down: model that by
    // making the transcript pull fail after the POST too.
    final viewModel = CodeConversationViewModel(
        's1', repo, _FakeApprovalsRepository(), () => Future.value());

    final accepted = await viewModel.send('hello');

    expect(accepted, isTrue, reason: 'the POST succeeded; the refresh failed');
  });

  test('offline refresh re-kicks the dial and keeps the cached transcript',
      () async {
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:1', seq: 1, sessionId: 's1', role: 'user', text: 'a'),
        ],
      }
      ..refreshError = ConversationOfflineException();
    final transport = _PokeTransport()..stored = true;
    repo.transportField = transport;
    final viewModel = CodeConversationViewModel(
        's1', repo, _FakeApprovalsRepository(), () => Future.value());

    await viewModel.refresh();

    expect(viewModel.loadError, CodeConversationError.offline);
    expect(viewModel.messages.single.seq, 1,
        reason: 'the cached transcript still renders');
    expect(transport.resumeCount, 1, reason: 'a failed pull re-kicks the dial');
  });

  test('connected announcement re-pulls automatically', () async {
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:1', seq: 1, sessionId: 's1', role: 'user', text: 'a'),
        ],
      };
    final transport = _PokeTransport();
    repo.transportField = transport;
    final viewModel = CodeConversationViewModel(
        's1', repo, _FakeApprovalsRepository(), () => Future.value());

    viewModel.listenTransport();
    transport.emit(ArxaConnectionStatus(ArxaConnectionState.connected,
        studioUrl: Uri.parse('http://127.0.0.1:45890/')));
    await pumpEventQueue();

    expect(viewModel.messages.single.seq, 1,
        reason: 'the tunnel coming up re-pulls the transcript');
  });

  test('decide posts the answers and the approval leaves the thread', () async {
    final repo = _FakeConversationRepository();
    final approvals = _FakeApprovalsRepository()..rows = [_approval];
    final viewModel = CodeConversationViewModel('s1', repo, approvals,
        () => Future.value());
    await viewModel.refresh();

    final accepted = await viewModel.decide(_approval, const [
      ApprovalAnswer(questionId: 'q1', selected: ['yes']),
    ]);

    expect(accepted, isTrue);
    expect(approvals.lastDecided?.$1, 'a1');
    expect(viewModel.pendingApprovals, isEmpty);
    expect(viewModel.decidingId, isNull);
  });
}
