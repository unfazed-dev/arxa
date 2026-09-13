// The Approval domain model — the phone's projection of a dsh session's
// pending human-input request (grill D60–D68; engine half: arxa-studio
// plugins/approvals). Wire shape IS the future cairn row (D61): field names
// map 1:1 onto the engine's record, so the B2 swap (approvals riding real
// cairn sync) changes transport, not model.
//
// D63: an approval is DERIVED state on the engine — nothing here is
// authoritative; the cache row is a projection that refresh() replaces and
// decide() deletes. D64: kind stays 'approval' for every pending question.

import 'package:arxa_kit_data/arxa_kit_data.dart';

/// One answer, engine-shaped: the question id plus either selected option
/// labels, a custom free-text answer, or both (multi-select only).
class ApprovalAnswer {
  const ApprovalAnswer({
    required this.questionId,
    this.selected = const [],
    this.custom,
  });

  final String questionId;
  final List<String> selected;
  final String? custom;

  Map<String, dynamic> toJson() => {
    'id': questionId,
    'selected': selected,
    if (custom != null && custom!.trim().isNotEmpty) 'custom': custom,
  };
}

/// One selectable option of a question (engine verbatim).
class ApprovalOption {
  const ApprovalOption({required this.label, this.description});

  final String label;
  final String? description;

  factory ApprovalOption.fromJson(Map<String, dynamic> json) => ApprovalOption(
    label: json['label'] as String,
    description: json['description'] as String?,
  );
}

/// One question in a pending request (engine verbatim — needed to answer).
class ApprovalQuestion {
  const ApprovalQuestion({
    required this.id,
    required this.question,
    this.header,
    this.detail,
    this.options = const [],
    this.multiSelect = false,
  });

  final String id;
  final String question;
  final String? header;
  final String? detail;
  final List<ApprovalOption> options;
  final bool multiSelect;

  factory ApprovalQuestion.fromJson(Map<String, dynamic> json) =>
      ApprovalQuestion(
        id: json['id'] as String,
        question: json['question'] as String,
        header: json['header'] as String?,
        detail: json['detail'] as String?,
        multiSelect: json['multiSelect'] == true,
        options: [
          for (final option
              in (json['options'] as List<dynamic>? ?? <dynamic>[]))
            ApprovalOption.fromJson(option as Map<String, dynamic>),
        ],
      );
}

/// A pending approval: the engine's projection record. status ships
/// 'pending' only — decided approvals leave the list (history is a B2
/// concern); the field exists because the cairn row will want it.
class Approval {
  const Approval({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.summary,
    required this.questions,
    required this.raisedAt,
    this.status = 'pending',
  });

  final String id;
  final String sessionId;
  final String kind;
  final String summary;
  final List<ApprovalQuestion> questions;
  final int raisedAt;
  final String status;

  factory Approval.fromJson(Map<String, dynamic> json) => Approval(
    id: json['id'] as String,
    sessionId: json['session_id'] as String? ?? '',
    kind: json['kind'] as String? ?? 'approval',
    summary: json['summary'] as String? ?? '',
    questions: [
      for (final question
          in (json['questions'] as List<dynamic>? ?? <dynamic>[]))
        ApprovalQuestion.fromJson(question as Map<String, dynamic>),
    ],
    raisedAt: (json['raised_at'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'pending',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'session_id': sessionId,
    'kind': kind,
    'summary': summary,
    'questions': [
      for (final question in questions)
        {
          'id': question.id,
          'question': question.question,
          if (question.header != null) 'header': question.header,
          if (question.detail != null) 'detail': question.detail,
          if (question.multiSelect) 'multiSelect': true,
          'options': [
            for (final option in question.options)
              {
                'label': option.label,
                if (option.description != null)
                  'description': option.description,
              },
          ],
        },
    ],
    'raised_at': raisedAt,
    'status': status,
  };
}

/// The entity registration the app passes to ArxaKitData.initialize: the
/// approvals table schema + the wire codec. Nested questions live in ONE
/// jsonb column (kit rule: nested collections never become child tables, so
/// repositories stay single-table and realtime-streamable).
const approvalEntityRegistration = ArxaKitEntityRegistration<Approval>(
  schema: ArxaKitTableSchema(
    table: 'approvals',
    columns: [
      ArxaKitColumn.id(),
      ArxaKitColumn('session_id', ArxaKitColumnType.text),
      ArxaKitColumn('kind', ArxaKitColumnType.text),
      ArxaKitColumn('summary', ArxaKitColumnType.text),
      ArxaKitColumn('questions', ArxaKitColumnType.jsonb),
      ArxaKitColumn('raised_at', ArxaKitColumnType.integer),
      ArxaKitColumn('status', ArxaKitColumnType.text),
    ],
  ),
  fromJson: Approval.fromJson,
  toJson: _approvalToJson,
);

// A tear-off of the instance member would not be const; a top-level
// function keeps the registration const.
Map<String, dynamic> _approvalToJson(Approval approval) => approval.toJson();
