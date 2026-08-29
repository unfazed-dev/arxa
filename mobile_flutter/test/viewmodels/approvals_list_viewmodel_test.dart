// ApprovalsListViewModel (grill D60): loads through the repository,
// surfaces offline/remote refresh failures inline (D62: loud), and
// decides through the repository — accepted answers leave the list,
// conflicts report answered-elsewhere and refresh.
import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_api_client.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:arxa_studio_mobile/ui/views/approvals_shell/approvals_list/approvals_list_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements ApprovalsRepository {
  List<Approval> rows = const [];
  Object? refreshError;
  Object? decideError;
  (String, List<ApprovalAnswer>)? lastDecided;

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
    expect(ApprovalsListViewModel(_FakeRepository()).approvals, isEmpty);
  });

  test('refresh loads the repository list', () async {
    final repo = _FakeRepository()..rows = [_pending];
    final viewModel = ApprovalsListViewModel(repo);

    await viewModel.refresh();

    expect(viewModel.approvals.single.id, 'a1');
    expect(viewModel.loadError, isNull);
  });

  test('offline refresh surfaces inline and keeps the cached list', () async {
    final repo = _FakeRepository()
      ..rows = [_pending]
      ..refreshError = ApprovalsOfflineException();
    final viewModel = ApprovalsListViewModel(repo);

    await viewModel.refresh();

    expect(viewModel.loadError, ApprovalsError.offline);
    expect(viewModel.approvals.single.id, 'a1');
  });

  test('decide accepted: answer posts and the approval leaves the list', () async {
    final repo = _FakeRepository()..rows = [_pending];
    final viewModel = ApprovalsListViewModel(repo);
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
    final viewModel = ApprovalsListViewModel(repo);
    await viewModel.refresh();

    final accepted = await viewModel.decide(_pending, const [
      ApprovalAnswer(questionId: 'q1', selected: ['Approve']),
    ]);

    expect(accepted, isFalse);
    expect(viewModel.approvals.single.id, 'a1',
        reason: 'the fake kept the row; the view surfaces answered-elsewhere');
  });
}
