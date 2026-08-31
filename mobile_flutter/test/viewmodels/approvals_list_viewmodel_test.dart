// ApprovalsListViewModel (grill D60): loads through the repository,
// surfaces offline/remote refresh failures inline (D62: loud), and
// decides through the repository — accepted answers leave the list,
// conflicts report answered-elsewhere and refresh. Reactive (D68): a
// connected announcement re-pulls automatically, a failed pull re-kicks
// the dial, and nothing-stored surfaces the pairing affordance.
import 'dart:async';

import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_api_client.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/approvals_shell/approvals_list/approvals_list_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements ApprovalsRepository {
  List<Approval> rows = const [];
  Object? refreshError;
  Object? decideError;
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
  Future<void> refresh() async {
    final error = refreshError;
    if (error != null) throw error;
  }

  @override
  Future<void> decide(String id, List<ApprovalAnswer> answers) async {
    lastDecided = (id, answers);
    final error = decideError;
    if (error != null) throw error;
    rows = [for (final a in rows) if (a.id != id) a];
  }
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

const _pending = Approval(
  id: 'a1',
  sessionId: 's1',
  kind: 'approval',
  summary: 'Approve the deploy?',
  questions: [
    ApprovalQuestion(
      id: 'q1',
      question: 'Approve the deploy?',
      options: [
        ApprovalOption(label: 'Approve'),
        ApprovalOption(label: 'Deny'),
      ],
    ),
  ],
  raisedAt: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts with no pending approvals', () {
    expect(ApprovalsListViewModel(_FakeRepository(), () => Future.value()).approvals, isEmpty);
  });

  test('refresh loads the repository list', () async {
    final repo = _FakeRepository()..rows = [_pending];
    final viewModel = ApprovalsListViewModel(repo, () => Future.value());

    await viewModel.refresh();

    expect(viewModel.approvals.single.id, 'a1');
    expect(viewModel.loadError, isNull);
  });

  test('offline refresh surfaces inline and keeps the cached list', () async {
    final repo = _FakeRepository()
      ..rows = [_pending]
      ..refreshError = ApprovalsOfflineException();
    final viewModel = ApprovalsListViewModel(repo, () => Future.value());

    await viewModel.refresh();

    expect(viewModel.loadError, ApprovalsError.offline);
    expect(viewModel.approvals.single.id, 'a1');
  });

  test('connected announcement re-pulls automatically', () async {
    final repo = _FakeRepository()..rows = [_pending];
    final transport = _PokeTransport();
    repo.transportField = transport;
    final viewModel = ApprovalsListViewModel(repo, () => Future.value());

    viewModel.listenTransport();
    transport.emit(ArxaConnectionStatus(ArxaConnectionState.connected,
        studioUrl: Uri.parse('http://127.0.0.1:45890/')));
    await pumpEventQueue();

    expect(viewModel.approvals.single.id, 'a1',
        reason: 'the tunnel coming up re-pulls the list with no user action');
  });

  test('offline refresh re-kicks the dial when paired', () async {
    final repo = _FakeRepository()..refreshError = ApprovalsOfflineException();
    final transport = _PokeTransport()..stored = true;
    repo.transportField = transport;
    final viewModel = ApprovalsListViewModel(repo, () => Future.value());

    await viewModel.refresh();

    expect(transport.resumeCount, 1,
        reason: 'a failed pull re-kicks the dial so a late desktop is found');
    expect(viewModel.loadError, ApprovalsError.offline);
    expect(viewModel.needsPairing, isFalse);
  });

  test('offline with nothing stored surfaces the pairing affordance', () async {
    final repo = _FakeRepository()..refreshError = ApprovalsOfflineException();
    final transport = _PokeTransport()..stored = false;
    repo.transportField = transport;
    final viewModel = ApprovalsListViewModel(repo, () => Future.value());

    await viewModel.refresh();

    expect(viewModel.needsPairing, isTrue);
    expect(transport.resumeCount, 0,
        reason: 'resume is a no-op without a session — offer the scanner');
  });

  test('a later successful refresh clears the pairing affordance', () async {
    final repo = _FakeRepository()..refreshError = ApprovalsOfflineException();
    final transport = _PokeTransport()..stored = false;
    repo.transportField = transport;
    final viewModel = ApprovalsListViewModel(repo, () => Future.value());
    await viewModel.refresh();
    expect(viewModel.needsPairing, isTrue);

    repo
      ..refreshError = null
      ..rows = [_pending];
    await viewModel.refresh();

    expect(viewModel.needsPairing, isFalse);
    expect(viewModel.approvals.single.id, 'a1');
  });

  test('decide accepted: answer posts and the approval leaves the list', () async {
    final repo = _FakeRepository()..rows = [_pending];
    final viewModel = ApprovalsListViewModel(repo, () => Future.value());
    await viewModel.refresh();

    final accepted = await viewModel.decide(_pending, const [
      ApprovalAnswer(questionId: 'q1', selected: ['Approve']),
    ]);

    expect(accepted, isTrue);
    expect(viewModel.approvals, isEmpty);
    expect(repo.lastDecided?.$1, 'a1');
  });

  test('decide conflict: reports answered elsewhere and refreshes', () async {
    final repo = _FakeRepository()
      ..rows = [_pending]
      ..decideError = ApprovalsConflictException('not-pending');
    final viewModel = ApprovalsListViewModel(repo, () => Future.value());
    await viewModel.refresh();

    final accepted = await viewModel.decide(_pending, const [
      ApprovalAnswer(questionId: 'q1', selected: ['x']),
    ]);

    expect(accepted, isFalse);
    expect(viewModel.approvals.single.id, 'a1',
        reason: 'the fake kept the row; the view surfaces answered-elsewhere');
  });
}