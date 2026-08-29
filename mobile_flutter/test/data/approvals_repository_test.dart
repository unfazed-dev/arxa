// ApprovalsRepository (grill D61/D62): refresh reconciles the cache to the
// engine's list (upsert present, delete stale, keep cache on offline),
// decide deletes the cache row only on acceptance, and conflicts
// propagate for inline surfacing.
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_api_client.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// A tiny mutable fake of the ArxaKitRepository port — enough to assert the
// reconcile semantics without a backend.
class _FakeCache implements ArxaKitRepository<Approval> {
  final Map<String, Approval> rows = {};

  @override
  Future<Approval?> getById(String id) async => rows[id];

  @override
  Future<List<Approval>> getAll([ArxaKitQuery query = const ArxaKitQuery()]) async =>
      rows.values.toList();

  @override
  Stream<Approval?> watchById(String id) => const Stream.empty();

  @override
  Stream<List<Approval>> watchAll([ArxaKitQuery query = const ArxaKitQuery()]) =>
      const Stream.empty();

  @override
  Future<Approval> upsert(Approval entity) async => rows.putIfAbsent(entity.id, () => entity);

  @override
  Future<List<Approval>> upsertMany(List<Approval> entities) async =>
      [for (final e in entities) await upsert(e)];

  @override
  Future<Approval> patch(Approval original, Approval patched) async => patched;

  @override
  Future<void> delete(String id) async => rows.remove(id);
}

class _FakeApi implements ApprovalsApiClient {
  _FakeApi(this.remote);

  List<Approval> remote;
  Object? listError;

  // Interface completeness only — the fake never dials a transport.
  @override
  TransportService get transport => throw UnimplementedError();
  Object? decideResult;
  List<(String, List<ApprovalAnswer>)>? decided;

  @override
  Future<List<Approval>> list() async {
    final error = listError;
    if (error != null) throw error;
    return remote;
  }

  @override
  Future<void> decide(String id, List<ApprovalAnswer> answers) async {
    decided?.add((id, answers));
    final result = decideResult;
    if (result != null) throw result;
  }
}

Approval _approval(String id, {int raisedAt = 0}) => Approval(
      id: id,
      sessionId: 's',
      kind: 'approval',
      summary: 'q $id',
      questions: const [],
      raisedAt: raisedAt,
    );

void main() {
  test('refresh upserts the engine list and deletes stale cache rows', () async {
    final cache = _FakeCache()
      ..rows['gone'] = _approval('gone')
      ..rows['kept'] = _approval('kept');
    final repo = ApprovalsRepository(
      cache: cache,
      api: _FakeApi([_approval('kept'), _approval('new')]),
    );

    await repo.refresh();

    expect(cache.rows.keys, containsAll(const ['kept', 'new']));
    expect(cache.rows.containsKey('gone'), isFalse);
    expect((await repo.list()).map((a) => a.id), ['kept', 'new']);
  });

  test('list sorts oldest first', () async {
    final cache = _FakeCache()
      ..rows['late'] = _approval('late', raisedAt: 20)
      ..rows['early'] = _approval('early', raisedAt: 10);
    final repo = ApprovalsRepository(cache: cache, api: _FakeApi(const []));

    expect((await repo.list()).map((a) => a.id), ['early', 'late']);
  });

  test('refresh offline keeps the cached list for reading', () async {
    final cache = _FakeCache()..rows['kept'] = _approval('kept');
    final api = _FakeApi(const [])..listError = ApprovalsOfflineException();
    final repo = ApprovalsRepository(cache: cache, api: api);

    await expectLater(
      () => repo.refresh(),
      throwsA(isA<ApprovalsOfflineException>()),
    );
    expect((await repo.list()).map((a) => a.id), ['kept'],
        reason: 'the cache survives an offline refresh for reading');
  });

  test('decide deletes the cache row on acceptance and posts the answers', () async {
    final cache = _FakeCache()..rows['a1'] = _approval('a1');
    final api = _FakeApi(const [])..decided = [];
    final repo = ApprovalsRepository(cache: cache, api: api);

    await repo.decide('a1', const [
      ApprovalAnswer(questionId: 'q1', selected: ['Approve']),
    ]);

    expect(api.decided?.single.$1, 'a1');
    expect(api.decided?.single.$2.single.selected, ['Approve']);
    expect(cache.rows, isEmpty);
  });

  test('decide conflict propagates and keeps the row (refresh resyncs)', () async {
    final cache = _FakeCache()..rows['a1'] = _approval('a1');
    final api = _FakeApi(const [])
      ..decideResult = ApprovalsConflictException('not-pending');
    final repo = ApprovalsRepository(cache: cache, api: api);

    await expectLater(
      () => repo.decide('a1', const [ApprovalAnswer(questionId: 'q1', selected: ['x'])]),
      throwsA(isA<ApprovalsConflictException>()),
    );
    expect(cache.rows.containsKey('a1'), isTrue,
        reason: 'a refused decision must not silently drop the projection');
  });
}
