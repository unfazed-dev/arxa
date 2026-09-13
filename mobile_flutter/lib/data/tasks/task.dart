// The Task domain model — the phone's projection of a dsh session's
// background job (B3: 'everything the session tools trigger' — task
// completions ride the phone rail beside approvals). One row per terminal
// job; running jobs never land (the mirror-out only emits terminal).

import 'package:arxa_kit_data/arxa_kit_data.dart';

/// A finished background task: the outcome picks the presentation (D60–D68
/// content-free discipline — the row carries what happened, never payload).
class Task {
  const Task({
    required this.id,
    required this.sessionId,
    required this.label,
    required this.status,
    required this.raisedAt,
    this.finishedAt,
  });

  final String id;
  final String sessionId;
  final String label;

  /// 'completed' or 'failed' (killed folds into failed engine-side).
  final String status;
  final int raisedAt;
  final int? finishedAt;

  bool get isFailed => status != 'completed';

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    sessionId: json['session_id'] as String? ?? '',
    label: json['summary'] as String? ?? '',
    status: json['status'] as String? ?? 'completed',
    raisedAt: (json['raised_at'] as num?)?.toInt() ?? 0,
    finishedAt: (json['finished_at'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'session_id': sessionId,
    'kind': 'task',
    'summary': label,
    'status': status,
    'raised_at': raisedAt,
    'finished_at': finishedAt,
  };
}

/// The entity registration: the tasks table schema mirrors the row the
/// engine's mirror-out writer emits (summary column carries the label).
const taskEntityRegistration = ArxaKitEntityRegistration<Task>(
  schema: ArxaKitTableSchema(
    table: 'tasks',
    columns: [
      ArxaKitColumn.id(),
      ArxaKitColumn('session_id', ArxaKitColumnType.text),
      ArxaKitColumn('kind', ArxaKitColumnType.text),
      ArxaKitColumn('summary', ArxaKitColumnType.text),
      ArxaKitColumn('status', ArxaKitColumnType.text),
      ArxaKitColumn('raised_at', ArxaKitColumnType.integer),
      ArxaKitColumn('finished_at', ArxaKitColumnType.integer, nullable: true),
    ],
  ),
  fromJson: Task.fromJson,
  toJson: _taskToJson,
);

Map<String, dynamic> _taskToJson(Task task) => task.toJson();
