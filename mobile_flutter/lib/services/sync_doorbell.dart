// SyncDoorbell (B2 phase-1b) — the visible→silent swap's phone half: the
// silent APNs wake brings the app up, sync feeds the cache, and THIS is
// what the user actually hears — one local notification per newly-synced
// pending approval, collapsed per id (the kit replaces on id reuse). A
// re-sync, a pull reconciliation, or a decision that leaves the id
// unchanged never re-buzzes; the FIRST watch emission seeds the known set,
// so a cold start over an already-pending list stays quiet. Content-free
// copy (D60–D68 discipline — the engine's copy never rides the local rail).
import 'dart:async';

import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';

import '../data/approvals/approval.dart';
import '../data/approvals/approvals_repository.dart';
import '../data/tasks/task.dart';

class SyncDoorbell {
  SyncDoorbell(this._repository, this._notifications);

  static const _title = 'Approval needed';
  static const _body = 'Open Arxa Studio to review.';

  final ApprovalsRepository _repository;
  final ArxaKitNotificationsService _notifications;
  final Set<String> _doorbelled = <String>{};
  StreamSubscription<List<Approval>>? _sub;
  bool _seeded = false;

  /// Arm once; the cache watch fires on sync applies AND pull
  /// reconciliations — both arrival paths ring through the same dedupe.
  void listen() {
    _sub ??= _repository.watch().listen(_onRows);
  }

  void _onRows(List<Approval> rows) {
    final pending = rows.where((a) => a.status == 'pending');
    if (!_seeded) {
      _doorbelled.addAll(pending.map((a) => a.id));
      _seeded = true;
      return;
    }
    for (final approval in pending) {
      if (_doorbelled.contains(approval.id)) continue;
      _doorbelled.add(approval.id);
      unawaited(_buzz(approval));
    }
  }

  /// One buzz per new pending id. The stable kit id makes a repeat for the
  /// SAME id replace (collapse) rather than stack, belt-and-braces against
  /// a process-lifetime dedupe miss.
  Future<void> _buzz(Approval approval) {
    return _notifications.showLocalNotification(ArxaKitLocalNotification(
      id: approval.id.hashCode & 0x7fffffff,
      title: _title,
      body: _body,
      payload: 'approval:${approval.id}',
    ));
  }

  void dispose() {
    unawaited(_sub?.cancel());
  }
}

/// TaskDoorbell — the task-completions half of the same swap (B3: everything
/// the session tools trigger): one local notification per newly-synced
/// terminal task, 'Task finished'/'Task failed' by outcome, collapsed per id.
/// Same seed-and-dedupe contract as the approvals doorbell.
class TaskDoorbell {
  TaskDoorbell(this._repository, this._notifications);

  final ArxaKitRepository<Task> _repository;
  final ArxaKitNotificationsService _notifications;
  final Set<String> _doorbelled = <String>{};
  StreamSubscription<List<Task>>? _sub;
  bool _seeded = false;

  void listen() {
    _sub ??= _repository.watchAll().listen(_onRows);
  }

  void _onRows(List<Task> rows) {
    if (!_seeded) {
      _doorbelled.addAll(rows.map((t) => t.id));
      _seeded = true;
      return;
    }
    for (final task in rows) {
      if (_doorbelled.contains(task.id)) continue;
      _doorbelled.add(task.id);
      unawaited(_buzz(task));
    }
  }

  Future<void> _buzz(Task task) {
    return _notifications.showLocalNotification(ArxaKitLocalNotification(
      id: task.id.hashCode & 0x7fffffff,
      title: task.isFailed ? 'Task failed' : 'Task finished',
      body: 'Open Arxa Studio to see the result.',
      payload: 'task:${task.id}',
    ));
  }

  void dispose() {
    unawaited(_sub?.cancel());
  }
}
