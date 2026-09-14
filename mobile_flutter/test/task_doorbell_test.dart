// TaskDoorbell — the task-completions half of the swap: seed on the first
// emission, buzz once per newly-synced terminal task ('Task finished' /
// 'Task failed' by outcome), collapsed per id. Pure fakes.
import 'dart:async';

import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_notifications/arxa_kit_testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arxa_studio_mobile/data/tasks/task.dart';
import 'package:arxa_studio_mobile/services/sync_doorbell.dart';

class _FakeTaskRepository implements ArxaKitRepository<Task> {
  final _controller = StreamController<List<Task>>.broadcast();
  List<Task> rows = const [];

  void emit(List<Task> rows) {
    this.rows = rows;
    _controller.add(rows);
  }

  @override
  Stream<List<Task>> watchAll([ArxaKitQuery? query]) => _controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Task task(String id, {String status = 'completed'}) => Task(
  id: id,
  sessionId: 's',
  label: 'job $id',
  status: status,
  raisedAt: 0,
  finishedAt: 1,
);

void main() {
  test('seeds silently, buzzes new terminal tasks once by outcome', () async {
    final repo = _FakeTaskRepository();
    final notifications = FakeArxaKitNotificationsService();
    final doorbell = TaskDoorbell(repo, notifications)..listen();
    repo.emit([task('t1')]); // seed
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notifications.shown, isEmpty);
    repo.emit([task('t1'), task('t2')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notifications.shown, hasLength(1));
    expect(notifications.shown.single.title, 'Task finished');
    expect(notifications.shown.single.payload, 'task:t2');
    doorbell.dispose();
  });

  test(
    'failed outcome rings Task failed; dedupe holds across re-emits',
    () async {
      final repo = _FakeTaskRepository();
      final notifications = FakeArxaKitNotificationsService();
      final doorbell = TaskDoorbell(repo, notifications)..listen();
      repo.emit(const []);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repo.emit([task('f1', status: 'failed')]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifications.shown.single.title, 'Task failed');
      repo.emit([task('f1', status: 'failed')]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        notifications.shown,
        hasLength(1),
        reason: 'known id never re-buzzes',
      );
      doorbell.dispose();
    },
  );
}
