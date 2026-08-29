// Approval wire codec (grill D61): the engine's record shape round-trips
// through the model into the cairn cache row and back; the entity
// registration schema matches the wire fields.
import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine record round-trips through the model', () {
    final wire = {
      'id': '0192ab3c-1111-4000-8000-abcdef000001',
      'session_id': 'sess-42',
      'kind': 'approval',
      'summary': 'Approve the deploy?',
      'questions': [
        {
          'id': 'q1',
          'question': 'Approve the deploy?',
          'header': 'Deploy',
          'options': [
            {'label': 'Approve', 'description': 'ship it'},
            {'label': 'Deny'},
          ],
        },
      ],
      'raised_at': 1760000000000,
      'status': 'pending',
    };
    final approval = Approval.fromJson(wire);
    expect(approval.id, wire['id']);
    expect(approval.sessionId, 'sess-42');
    expect(approval.summary, 'Approve the deploy?');
    expect(approval.questions.single.options.first.description, 'ship it');
    final back = approval.toJson();
    expect(back['id'], wire['id']);
    expect(back['session_id'], 'sess-42');
    expect(back['raised_at'], 1760000000000);
    expect(
      (back['questions'] as List).single['options'],
      (wire['questions'] as List).single['options'],
    );
  });

  test('the registration schema names the wire columns', () {
    final schema = approvalEntityRegistration.schema;
    expect(schema.table, 'approvals');
    expect(
      schema.columns.map((c) => c.name),
      containsAll(const [
        'id', 'session_id', 'kind', 'summary', 'questions', 'raised_at', 'status',
      ]),
    );
  });

  test('answers encode to the engine decide shape', () {
    const answer = ApprovalAnswer(
      questionId: 'q1',
      selected: ['Approve'],
    );
    expect(answer.toJson(), {
      'id': 'q1',
      'selected': ['Approve'],
    });
    const custom = ApprovalAnswer(questionId: 'q2', selected: [], custom: ' later ');
    expect(custom.toJson(), {'id': 'q2', 'selected': [], 'custom': ' later '});
  });
}
