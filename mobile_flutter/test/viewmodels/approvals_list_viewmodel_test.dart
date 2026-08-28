import 'package:flutter_test/flutter_test.dart';

import 'package:arxa_studio_mobile/ui/views/approvals_shell/approvals_list/approvals_list_viewmodel.dart';

void main() {
  group('ApprovalsListViewModel', () {
    // Skeleton stage: the approvals data slice (cairn schema) has not landed;
    // the list is empty by contract so the view renders its empty state.
    test('starts with no pending approvals', () {
      expect(ApprovalsListViewModel().approvals, isEmpty);
    });
  });
}
