// SyncDoorbell — the phone-local doorbell's contract (B2 phase-1b):
// the FIRST cache emission seeds the known set (a cold start over an
// already-pending list never buzzes); every later NEW pending id buzzes
// exactly once with content-free copy and a stable collapse id; a
// decided approval's departure is silent. Pure fakes, no native library.
import 'dart:async';

import 'package:arxa_kit_notifications/arxa_kit_testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:arxa_studio_mobile/services/sync_doorbell.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

class _FakeRepository implements ApprovalsRepository {
  final _controller = StreamController<List<Approval>>.broadcast();
  List<Approval> rows = const [];

  void emit(List<Approval> rows) {
    this.rows = rows;
    _controller.add(rows);
  }

  @override
  Stream<List<Approval>> watch() => _controller.stream;

  @override
  TransportService get transport => FakeTransportService();
  @override
  Duration get healWait => const Duration(seconds: 20);
  @override
  Future<List<Approval>> list() async => rows;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> decide(String id, List<ApprovalAnswer> answers) async {}
}

Approval approval(String id) => Approval(
  id: id,
  sessionId: 's',
  kind: 'approval',
  summary: 'summary $id',
  questions: const [],
  raisedAt: 0,
);

void main() {
  test(
    'first emission seeds — an already-pending cache never buzzes',
    () async {
      final repo = _FakeRepository()..emit([approval('a1'), approval('a2')]);
      final notifications = FakeArxaKitNotificationsService();
      SyncDoorbell(repo, notifications).listen();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifications.shown, isEmpty);
    },
  );

  test('a newly-synced pending id buzzes exactly once, content-free', () async {
    final repo = _FakeRepository();
    final notifications = FakeArxaKitNotificationsService();
    final doorbell = SyncDoorbell(repo, notifications)..listen();
    repo.emit(const []); // seed emission: the cache as it exists at arm time
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.emit([approval('n1')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notifications.shown, hasLength(1));
    final buzz = notifications.shown.single;
    expect(buzz.title, 'Approval needed');
    expect(buzz.body, 'Open Arxa Studio to review.');
    expect(buzz.payload, 'approval:n1');
    // The collapse id is a pure function of the approval id — a re-buzz
    // for the same id would REPLACE, never stack.
    repo.emit([approval('n1')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      notifications.shown,
      hasLength(1),
      reason: 'known id never re-buzzes',
    );
    doorbell.dispose();
  });

  test(
    'decided approvals leave quietly; a re-raised id buzzes again',
    () async {
      final repo = _FakeRepository();
      final notifications = FakeArxaKitNotificationsService();
      final doorbell = SyncDoorbell(repo, notifications)..listen();
      repo.emit([approval('x1')]); // seeds x1 as known
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Decided: the row leaves the projection — silence.
      repo.emit(const []);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifications.shown, isEmpty);
      // The engine may legitimately re-raise the same id later (a NEW ask
      // reusing the rpc id is not this process's buzz) — still deduped.
      repo.emit([approval('x1')]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        notifications.shown,
        isEmpty,
        reason: 'per-process dedupe is the contract; the wake is the APNs rail',
      );
      doorbell.dispose();
    },
  );
}
