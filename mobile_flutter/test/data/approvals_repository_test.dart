// ApprovalsRepository (grill D61/D62): refresh reconciles the cache to the
// engine's list (upsert present, delete stale, keep cache on offline),
// decide deletes the cache row only on acceptance, and conflicts
// propagate for inline surfacing. A transport-level failure while PAIRED
// heals once: resume() the transport, wait for it to re-establish, retry
// the pull exactly once (memo 3b — the zombie-link failure mode).
import 'dart:io';

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
  Future<List<Approval>> getAll([
    ArxaKitQuery query = const ArxaKitQuery(),
  ]) async => rows.values.toList();

  @override
  Stream<Approval?> watchById(String id) => const Stream.empty();

  @override
  Stream<List<Approval>> watchAll([
    ArxaKitQuery query = const ArxaKitQuery(),
  ]) => const Stream.empty();

  @override
  Future<Approval> upsert(Approval entity) async =>
      rows.putIfAbsent(entity.id, () => entity);

  @override
  Future<List<Approval>> upsertMany(List<Approval> entities) async => [
    for (final e in entities) await upsert(e),
  ];

  @override
  Future<Approval> patch(Approval original, Approval patched) async => patched;

  @override
  Future<void> delete(String id) async => rows.remove(id);
}

class _FakeApi implements ApprovalsApiClient {
  _FakeApi(this.remote);

  List<Approval> remote;

  /// Errors consumed FIFO by [list] before the remote list is served —
  /// models a transport that fails fast (the zombie link) then heals.
  List<Object> listErrors = [];

  @override
  TransportService transport = FakeTransportService();

  Object? decideResult;
  List<(String, List<ApprovalAnswer>)>? decided;

  @override
  Future<List<Approval>> list() async {
    if (listErrors.isNotEmpty) throw listErrors.removeAt(0);
    return remote;
  }

  @override
  Future<void> decide(String id, List<ApprovalAnswer> answers) async {
    decided?.add((id, answers));
    final result = decideResult;
    if (result != null) throw result;
  }
}

/// Connected on paper, but resume() never re-announces connected — the
/// zombie link that refuses to heal within any wait window.
class _SilentTransport implements TransportService {
  @override
  ArxaConnectionStatus get current => ArxaConnectionStatus(
    ArxaConnectionState.connected,
    studioUrl: Uri.parse('http://127.0.0.1:45890/'),
  );

  @override
  Stream<ArxaConnectionStatus> get status => const Stream.empty();

  @override
  Future<bool> hasStoredPairing() async => true;

  @override
  Future<void> beginPairing(String ticket) async {}

  @override
  Future<void> setPushToken(String platform, String token) async {}

  @override
  Future<void> unpair() async {}

  int resumeCount = 0;

  @override
  Future<void> resume() async => resumeCount += 1;

  @override
  Future<void> dispose() async {}
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
  test(
    'refresh upserts the engine list and deletes stale cache rows',
    () async {
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
    },
  );

  test(
    'list sorts newest first — the live question is what the owner needs on top',
    () async {
      final cache = _FakeCache()
        ..rows['late'] = _approval('late', raisedAt: 20)
        ..rows['early'] = _approval('early', raisedAt: 10);
      final repo = ApprovalsRepository(cache: cache, api: _FakeApi(const []));

      expect((await repo.list()).map((a) => a.id), ['late', 'early']);
    },
  );

  test('refresh offline keeps the cached list for reading', () async {
    final cache = _FakeCache()..rows['kept'] = _approval('kept');
    final api = _FakeApi(const [])..listErrors = [ApprovalsOfflineException()];
    final repo = ApprovalsRepository(cache: cache, api: api);

    await expectLater(
      () => repo.refresh(),
      throwsA(isA<ApprovalsOfflineException>()),
    );
    expect(
      (await repo.list()).map((a) => a.id),
      ['kept'],
      reason: 'the cache survives an offline refresh for reading',
    );
  });

  test('refresh heals a zombie link: resume, reconnect, retry once', () async {
    final transport = FakeTransportService();
    await transport.beginPairing('ticket'); // connected, studioUrl set
    final api = _FakeApi([_approval('a1')])
      ..transport = transport
      ..listErrors = [
        ApprovalsOfflineException(
          HttpException('Connection closed before full header'),
        ),
      ];
    final cache = _FakeCache()..rows['stale'] = _approval('stale');
    final repo = ApprovalsRepository(cache: cache, api: api);

    await repo.refresh();

    expect(
      transport.resumeCount,
      1,
      reason: 'the heal resumes the transport exactly once',
    );
    expect(cache.rows.keys, [
      'a1',
    ], reason: 'the retried pull reconciles the cache');
  });

  test('refresh heal gives up after one failed retry (no loops)', () async {
    final transport = FakeTransportService();
    await transport.beginPairing('ticket');
    final api = _FakeApi(const [])
      ..transport = transport
      ..listErrors = [ApprovalsOfflineException(), ApprovalsOfflineException()];
    final cache = _FakeCache()..rows['kept'] = _approval('kept');
    final repo = ApprovalsRepository(cache: cache, api: api);

    await expectLater(
      () => repo.refresh(),
      throwsA(isA<ApprovalsOfflineException>()),
    );
    expect(
      transport.resumeCount,
      1,
      reason: 'one heal per refresh, never a loop',
    );
    expect(cache.rows.keys, [
      'kept',
    ], reason: 'a failed heal leaves the cached projection alone');
  });

  test(
    'refresh heal rethrows the original error when the tunnel never returns',
    () async {
      final api = _FakeApi(const [])
        ..transport = _SilentTransport()
        ..listErrors = [ApprovalsOfflineException(HttpException('zombie'))];
      final cache = _FakeCache()..rows['kept'] = _approval('kept');
      final repo = ApprovalsRepository(
        cache: cache,
        api: api,
        healWait: const Duration(milliseconds: 50),
      );

      await expectLater(
        () => repo.refresh(),
        throwsA(isA<ApprovalsOfflineException>()),
      );
      expect((await repo.list()).map((a) => a.id), ['kept']);
    },
  );

  test(
    'refresh does not heal when unpaired (nothing to resume into)',
    () async {
      final transport = FakeTransportService(); // notPaired — no studioUrl
      final api = _FakeApi(const [])
        ..transport = transport
        ..listErrors = [ApprovalsOfflineException()];
      final cache = _FakeCache()..rows['kept'] = _approval('kept');
      final repo = ApprovalsRepository(cache: cache, api: api);

      await expectLater(
        () => repo.refresh(),
        throwsA(isA<ApprovalsOfflineException>()),
      );
      expect(
        transport.resumeCount,
        0,
        reason: 'resume is a no-op without a session — do not pretend to heal',
      );
      expect(cache.rows.keys, ['kept']);
    },
  );

  test(
    'refresh does not heal on a remote error (the engine answered)',
    () async {
      final transport = FakeTransportService();
      await transport.beginPairing('ticket');
      final api = _FakeApi(const [])
        ..transport = transport
        ..listErrors = [ApprovalsRemoteException(500, 'boom')];
      final repo = ApprovalsRepository(cache: _FakeCache(), api: api);

      await expectLater(
        () => repo.refresh(),
        throwsA(isA<ApprovalsRemoteException>()),
      );
      expect(
        transport.resumeCount,
        0,
        reason: 'a 5xx means the tunnel works — resuming cannot help',
      );
    },
  );

  test(
    'decide deletes the cache row on acceptance and posts the answers',
    () async {
      final cache = _FakeCache()..rows['a1'] = _approval('a1');
      final api = _FakeApi(const [])..decided = [];
      final repo = ApprovalsRepository(cache: cache, api: api);

      await repo.decide('a1', const [
        ApprovalAnswer(questionId: 'q1', selected: ['Approve']),
      ]);

      expect(api.decided?.single.$1, 'a1');
      expect(api.decided?.single.$2.single.selected, ['Approve']);
      expect(cache.rows, isEmpty);
    },
  );

  test(
    'decide conflict propagates and keeps the row (refresh resyncs)',
    () async {
      final cache = _FakeCache()..rows['a1'] = _approval('a1');
      final api = _FakeApi(const [])
        ..decideResult = ApprovalsConflictException('not-pending');
      final repo = ApprovalsRepository(cache: cache, api: api);

      await expectLater(
        () => repo.decide('a1', const [
          ApprovalAnswer(questionId: 'q1', selected: ['x']),
        ]),
        throwsA(isA<ApprovalsConflictException>()),
      );
      expect(
        cache.rows.containsKey('a1'),
        isTrue,
        reason: 'a refused decision must not silently drop the projection',
      );
    },
  );
}
